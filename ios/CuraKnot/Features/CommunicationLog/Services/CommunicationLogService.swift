import Foundation
import GRDB
import OSLog

// MARK: - String Extension for Validation

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Communication Log Service

@MainActor
final class CommunicationLogService {
    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient
    private let syncCoordinator: SyncCoordinator
    private let subscriptionManager: SubscriptionManager
    private let authManager: AuthManager
    private let taskService: TaskService

    private let logger = Logger(subsystem: "com.curaknot", category: "CommunicationLogService")

    // MARK: - Cached Constants (thread-safe, avoids repeated allocations)

    private static let calendar = Calendar.current
    private static let roleHierarchy = ["VIEWER": 0, "CONTRIBUTOR": 1, "ADMIN": 2, "OWNER": 3]

    /// Escapes SQL LIKE wildcards to prevent injection
    private func escapeSQLLike(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        syncCoordinator: SyncCoordinator,
        subscriptionManager: SubscriptionManager,
        authManager: AuthManager,
        taskService: TaskService
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.syncCoordinator = syncCoordinator
        self.subscriptionManager = subscriptionManager
        self.authManager = authManager
        self.taskService = taskService
    }

    // MARK: - Feature Access

    var hasFeatureAccess: Bool {
        subscriptionManager.currentPlan != .free
    }

    var hasAISuggestionsAccess: Bool {
        subscriptionManager.currentPlan == .family
    }

    // MARK: - CRUD Operations

    func createLog(
        circleId: String,
        patientId: String,
        facilityName: String,
        facilityId: String? = nil,
        contactName: String,
        contactRole: [CommunicationLog.ContactRole],
        contactPhone: String? = nil,
        contactEmail: String? = nil,
        communicationType: CommunicationLog.CommunicationType = .call,
        callType: CommunicationLog.CallType,
        callDate: Date = Date(),
        durationMinutes: Int? = nil,
        summary: String,
        followUpDate: Date? = nil,
        followUpReason: String? = nil,
        linkedHandoffId: String? = nil
    ) async throws -> CommunicationLog {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is a CONTRIBUTOR+ in this circle
        try await verifyRole(circleId: circleId, userId: userId, minimumRole: "CONTRIBUTOR")

        // Input validation
        let trimmedFacilityName = facilityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContactName = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedFacilityName.isEmpty else {
            throw CommunicationLogError.invalidData
        }
        guard !trimmedContactName.isEmpty else {
            throw CommunicationLogError.invalidData
        }
        guard !trimmedSummary.isEmpty else {
            throw CommunicationLogError.invalidData
        }

        // Validate duration if provided (must be at least 1 minute, max 24 hours)
        if let duration = durationMinutes, duration < 1 || duration > 1440 {
            throw CommunicationLogError.invalidData
        }

        // Validate follow-up date if provided (must be today or in the future)
        let today = Self.calendar.startOfDay(for: Date())
        if let followUp = followUpDate, Self.calendar.startOfDay(for: followUp) < today {
            throw CommunicationLogError.invalidData
        }

        let log = CommunicationLog(
            circleId: circleId,
            patientId: patientId,
            createdBy: userId,
            facilityName: trimmedFacilityName,
            facilityId: facilityId,
            contactName: trimmedContactName,
            contactRole: contactRole,
            contactPhone: contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            contactEmail: contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            communicationType: communicationType,
            callType: callType,
            callDate: callDate,
            durationMinutes: durationMinutes,
            summary: trimmedSummary,
            followUpDate: followUpDate,
            followUpReason: followUpReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            followUpStatus: followUpDate != nil ? .pending : .none
        )

        // Save locally
        try databaseManager.write { db in
            try log.save(db)
        }

        // Enqueue for sync
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "INSERT",
            entityType: "communication_logs",
            entityId: log.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(log), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))

        // Request AI suggestions if FAMILY tier (background task with weak self to prevent retain cycle)
        if hasAISuggestionsAccess {
            Task { [weak self] in
                await self?.requestAISuggestions(for: log)
            }
        }

        return log
    }

    func updateLog(_ log: CommunicationLog) async throws {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is a CONTRIBUTOR+ in this circle
        try await verifyRole(circleId: log.circleId, userId: userId, minimumRole: "CONTRIBUTOR")

        var updated = log
        updated.updatedAt = Date()

        try databaseManager.write { db in
            try updated.update(db)
        }

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "communication_logs",
            entityId: log.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(updated), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    func deleteLog(_ log: CommunicationLog) async throws {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is ADMIN+ to delete logs
        try await verifyRole(circleId: log.circleId, userId: userId, minimumRole: "ADMIN")

        try databaseManager.write { db in
            try log.delete(db)
        }

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "DELETE",
            entityType: "communication_logs",
            entityId: log.id,
            payloadJson: "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    // MARK: - Query Methods

    func fetchLogs(
        circleId: String,
        patientId: String? = nil,
        facilityName: String? = nil,
        callType: CommunicationLog.CallType? = nil,
        followUpStatus: CommunicationLog.FollowUpStatus? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [CommunicationLog] {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is a member of this circle
        try await verifyCircleMembership(circleId: circleId, userId: userId)

        let sanitizedLimit = min(max(1, limit), 100)
        let sanitizedOffset = max(0, offset)

        return try databaseManager.read { db in
            var query = CommunicationLog.filter(CommunicationLog.Columns.circleId == circleId)

            if let patientId = patientId {
                query = query.filter(CommunicationLog.Columns.patientId == patientId)
            }

            if let facilityName = facilityName {
                let escapedName = escapeSQLLike(facilityName)
                query = query.filter(CommunicationLog.Columns.facilityName.like("%\(escapedName)%"))
            }

            if let callType = callType {
                query = query.filter(CommunicationLog.Columns.callType == callType.rawValue)
            }

            if let followUpStatus = followUpStatus {
                query = query.filter(CommunicationLog.Columns.followUpStatus == followUpStatus.rawValue)
            }

            return try query
                .order(CommunicationLog.Columns.callDate.desc)
                .limit(sanitizedLimit, offset: sanitizedOffset)
                .fetchAll(db)
        }
    }

    func fetchGroupedLogs(
        circleId: String,
        patientId: String? = nil
    ) async throws -> [CommunicationLogGroup] {
        // Auth check is handled by fetchLogs
        let logs = try await fetchLogs(circleId: circleId, patientId: patientId)

        let grouped = Dictionary(grouping: logs) { log in
            Self.calendar.startOfDay(for: log.callDate)
        }

        return grouped.map { date, logs in
            CommunicationLogGroup(
                id: date.ISO8601Format(),
                date: date,
                logs: logs.sorted { $0.callDate > $1.callDate }
            )
        }.sorted { $0.date > $1.date }
    }

    func fetchPendingFollowUps(circleId: String) async throws -> [CommunicationLog] {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is a member of this circle
        try await verifyCircleMembership(circleId: circleId, userId: userId)

        return try databaseManager.read { db in
            try CommunicationLog
                .filter(CommunicationLog.Columns.circleId == circleId)
                .filter(CommunicationLog.Columns.followUpStatus == CommunicationLog.FollowUpStatus.pending.rawValue)
                .filter(CommunicationLog.Columns.followUpDate != nil)
                .order(CommunicationLog.Columns.followUpDate.asc)
                .fetchAll(db)
        }
    }

    func fetchOverdueFollowUps(circleId: String) async throws -> [CommunicationLog] {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is a member of this circle
        try await verifyCircleMembership(circleId: circleId, userId: userId)

        let today = Self.calendar.startOfDay(for: Date())
        return try databaseManager.read { db in
            try CommunicationLog
                .filter(CommunicationLog.Columns.circleId == circleId)
                .filter(CommunicationLog.Columns.followUpStatus == CommunicationLog.FollowUpStatus.pending.rawValue)
                .filter(CommunicationLog.Columns.followUpDate < today)
                .order(CommunicationLog.Columns.followUpDate.asc)
                .fetchAll(db)
        }
    }

    func searchLogs(
        circleId: String,
        query: String,
        patientId: String? = nil,
        limit: Int = 50
    ) async throws -> [CommunicationLog] {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is a member of this circle
        try await verifyCircleMembership(circleId: circleId, userId: userId)

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return try await fetchLogs(circleId: circleId, patientId: patientId, limit: limit)
        }

        let sanitizedLimit = min(max(1, limit), 100)

        let escapedQuery = escapeSQLLike(trimmedQuery)
        let likePattern = "%\(escapedQuery)%"

        return try databaseManager.read { db in
            var baseQuery = CommunicationLog.filter(CommunicationLog.Columns.circleId == circleId)

            if let patientId = patientId {
                baseQuery = baseQuery.filter(CommunicationLog.Columns.patientId == patientId)
            }

            // Use database-level LIKE for efficient search (case-insensitive with COLLATE NOCASE)
            let searchFilter = CommunicationLog.Columns.summary.collating(.nocase).like(likePattern) ||
                               CommunicationLog.Columns.facilityName.collating(.nocase).like(likePattern) ||
                               CommunicationLog.Columns.contactName.collating(.nocase).like(likePattern)

            return try baseQuery
                .filter(searchFilter)
                .order(CommunicationLog.Columns.callDate.desc)
                .limit(sanitizedLimit)
                .fetchAll(db)
        }
    }

    // MARK: - Follow-up Operations

    func createFollowUpTask(for log: CommunicationLog) async throws -> String {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Validate state: cannot create task if one already exists
        guard log.followUpTaskId == nil else {
            throw CommunicationLogError.invalidStateTransition
        }

        // Validate state: cannot create task for completed or cancelled follow-ups
        guard log.followUpStatus != .complete && log.followUpStatus != .cancelled else {
            throw CommunicationLogError.invalidStateTransition
        }

        // Verify user is a CONTRIBUTOR+ in this circle
        try await verifyRole(circleId: log.circleId, userId: userId, minimumRole: "CONTRIBUTOR")

        struct CreateFollowUpResponse: Decodable {
            let taskId: String
        }

        let response: CreateFollowUpResponse = try await supabaseClient.rpc(
            "create_follow_up_task_from_log",
            params: ["p_log_id": log.id, "p_user_id": userId]
        )

        // Update local log
        var updated = log
        updated.followUpTaskId = response.taskId
        updated.followUpStatus = .pending
        updated.updatedAt = Date()

        try databaseManager.write { db in
            try updated.update(db)
        }

        return response.taskId
    }

    func markFollowUpComplete(_ log: CommunicationLog) async throws {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        // CRITICAL: Validate state - must have pending follow-up date
        guard log.followUpStatus == .pending, log.followUpDate != nil else {
            throw CommunicationLogError.invalidStateTransition
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is a CONTRIBUTOR+ in this circle
        try await verifyRole(circleId: log.circleId, userId: userId, minimumRole: "CONTRIBUTOR")

        var updated = log
        updated.followUpStatus = .complete
        updated.followUpCompletedAt = Date()
        updated.updatedAt = Date()

        try databaseManager.write { db in
            try updated.update(db)
        }

        // Sync to server
        try await supabaseClient.rpc(
            "complete_follow_up",
            params: ["p_log_id": log.id]
        )
    }

    func rescheduleFollowUp(_ log: CommunicationLog, to newDate: Date) async throws {
        // Validate state: can only reschedule pending follow-ups
        guard log.followUpStatus == .pending else {
            throw CommunicationLogError.invalidStateTransition
        }

        // Validate that new date is today or in the future (normalize both sides for consistency)
        let today = Self.calendar.startOfDay(for: Date())
        guard Self.calendar.startOfDay(for: newDate) >= today else {
            throw CommunicationLogError.invalidData
        }

        var updated = log
        updated.followUpDate = newDate
        updated.updatedAt = Date()

        // Auth check is handled by updateLog
        try await updateLog(updated)
    }

    // MARK: - AI Suggestions

    private func requestAISuggestions(for log: CommunicationLog) async {
        guard hasAISuggestionsAccess else { return }

        // Check user consent before sending data to third-party AI
        guard let userId = await getCurrentUserId() else { return }
        let hasConsent = await checkAIConsent(userId: userId)
        guard hasConsent else {
            logger.info("Skipping AI suggestions: user has not consented to AI processing")
            return
        }

        do {
            struct SuggestTasksRequest: Encodable {
                let logId: String
                let summary: String
                let callType: String
                let facilityName: String
            }

            struct SuggestTasksResponse: Decodable {
                let suggestions: [SuggestedTask]
            }

            let response: SuggestTasksResponse = try await supabaseClient
                .functions("suggest-tasks-from-log")
                .invoke(body: SuggestTasksRequest(
                    logId: log.id,
                    summary: log.summary,
                    callType: log.callType.rawValue,
                    facilityName: log.facilityName
                ))

            // Update local log with suggestions
            var updated = log
            updated.aiSuggestedTasks = response.suggestions
            updated.updatedAt = Date()

            try databaseManager.write { db in
                try updated.update(db)
            }
        } catch {
            // Log without PHI - do not include summary or facility name
            logger.warning("Failed to get AI suggestions for log \(log.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func acceptSuggestedTask(_ task: SuggestedTask, from log: CommunicationLog) async throws {
        guard hasFeatureAccess else {
            throw CommunicationLogError.featureNotAvailable
        }

        guard let userId = await getCurrentUserId() else {
            throw CommunicationLogError.notAuthenticated
        }

        // Verify user is a CONTRIBUTOR+ in this circle
        try await verifyRole(circleId: log.circleId, userId: userId, minimumRole: "CONTRIBUTOR")

        // Use TaskService for proper task creation (architecture layer compliance)
        // Safely handle optional dueInDays - return nil if calculation fails
        let dueAt: Date? = task.dueInDays.flatMap { days in
            Self.calendar.date(byAdding: .day, value: days, to: Date())
        }

        _ = try await taskService.createTask(
            circleId: log.circleId,
            patientId: log.patientId,
            title: task.title,
            description: task.description,
            dueAt: dueAt,
            priority: CareTask.Priority(rawValue: task.priority) ?? .med,
            assigneeId: userId
        )

        // Update the suggestion as accepted
        var updated = log
        if var suggestions = updated.aiSuggestedTasks {
            if let index = suggestions.firstIndex(where: { $0.id == task.id }) {
                suggestions[index].isAccepted = true
                updated.aiSuggestedTasks = suggestions
            }
        }
        updated.updatedAt = Date()

        try databaseManager.write { db in
            try updated.update(db)
        }

        // Enqueue sync for the updated log
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "communication_logs",
            entityId: log.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(updated), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    // MARK: - Authorization Helpers

    private func getCurrentUserId() async -> String? {
        authManager.currentUser?.id
    }

    /// Verifies the current user is an active member of the specified circle
    private func verifyCircleMembership(circleId: String, userId: String) async throws {
        struct MemberCheck: Decodable {
            let id: String
        }

        do {
            let members: [MemberCheck] = try await supabaseClient
                .from("circle_members")
                .select("id")
                .eq("circle_id", circleId)
                .eq("user_id", userId)
                .eq("status", "ACTIVE")
                .execute()

            guard !members.isEmpty else {
                throw CommunicationLogError.permissionDenied
            }
        } catch let error as CommunicationLogError {
            throw error
        } catch {
            // If we can't verify membership (e.g., offline), allow local operation
            // RLS will enforce on sync
            logger.notice("Could not verify circle membership (offline?): \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Verifies the user has at least the specified role in the circle
    private func verifyRole(circleId: String, userId: String, minimumRole: String) async throws {
        struct MemberRole: Decodable {
            let role: String
        }

        do {
            let members: [MemberRole] = try await supabaseClient
                .from("circle_members")
                .select("role")
                .eq("circle_id", circleId)
                .eq("user_id", userId)
                .eq("status", "ACTIVE")
                .execute()

            guard let member = members.first else {
                throw CommunicationLogError.permissionDenied
            }

            let userLevel = Self.roleHierarchy[member.role] ?? 0
            let requiredLevel = Self.roleHierarchy[minimumRole] ?? 0

            guard userLevel >= requiredLevel else {
                throw CommunicationLogError.permissionDenied
            }
        } catch let error as CommunicationLogError {
            throw error
        } catch {
            // If we can't verify role (e.g., offline), allow local operation
            // RLS will enforce on sync
            logger.notice("Could not verify role (offline?): \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Checks if user has consented to AI processing of their data
    private func checkAIConsent(userId: String) async -> Bool {
        struct ConsentCheck: Decodable {
            let aiProcessingEnabled: Bool
        }

        do {
            let consents: [ConsentCheck] = try await supabaseClient
                .from("user_ai_consent")
                .select("ai_processing_enabled")
                .eq("user_id", userId)
                .execute()

            return consents.first?.aiProcessingEnabled ?? false
        } catch {
            // Default to no consent if record doesn't exist or error occurs
            return false
        }
    }
}

// MARK: - Errors

enum CommunicationLogError: Error, LocalizedError {
    case notAuthenticated
    case featureNotAvailable
    case notFound
    case permissionDenied
    case invalidData
    case invalidStateTransition

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in"
        case .featureNotAvailable:
            return "This feature requires a Plus or Family subscription"
        case .notFound:
            return "Communication log not found"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .invalidData:
            return "Invalid data provided"
        case .invalidStateTransition:
            return "This follow-up cannot be marked complete because it is not pending"
        }
    }
}
