import Foundation
import GRDB

// MARK: - Discharge Wizard Service

@MainActor
final class DischargeWizardService {
    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient
    private let syncCoordinator: SyncCoordinator
    private let taskService: TaskService
    private let subscriptionManager: SubscriptionManager

    // Cache for subscription access (valid for 5 minutes)
    private var _hasAccessCache: Bool?
    private var _hasAccessCacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        syncCoordinator: SyncCoordinator,
        taskService: TaskService,
        subscriptionManager: SubscriptionManager
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.syncCoordinator = syncCoordinator
        self.taskService = taskService
        self.subscriptionManager = subscriptionManager

        // Observe subscription changes to invalidate cache
        setupSubscriptionObserver()
    }

    private func setupSubscriptionObserver() {
        // Invalidate cache when subscription changes
        NotificationCenter.default.addObserver(
            forName: .subscriptionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateAccessCache()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Access Control

    func hasAccess() -> Bool {
        // Check if cache is still valid
        if let cached = _hasAccessCache,
           let timestamp = _hasAccessCacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration {
            return cached
        }

        let access = subscriptionManager.hasFeature(.dischargeWizard)
        _hasAccessCache = access
        _hasAccessCacheTimestamp = Date()
        return access
    }

    func invalidateAccessCache() {
        _hasAccessCache = nil
        _hasAccessCacheTimestamp = nil
    }

    // MARK: - Authorization Helpers

    /// Verify user is an active member of a circle
    private func verifyCircleMembership(circleId: String, userId: String) async throws -> Bool {
        do {
            let membership: [CircleMember] = try await supabaseClient
                .from("circle_members")
                .select()
                .eq("circle_id", circleId)
                .eq("user_id", userId)
                .eq("status", "ACTIVE")
                .execute()

            return !membership.isEmpty
        } catch {
            return false
        }
    }

    /// Verify user has at least the required role in the circle
    private func verifyRole(circleId: String, userId: String, minimumRole: String) async throws -> Bool {
        let membership: [CircleMember] = try await supabaseClient
            .from("circle_members")
            .select()
            .eq("circle_id", circleId)
            .eq("user_id", userId)
            .eq("status", "ACTIVE")
            .execute()

        guard let member = membership.first else {
            return false
        }

        let roleHierarchy = ["VIEWER": 0, "CONTRIBUTOR": 1, "ADMIN": 2, "OWNER": 3]
        let userRoleLevel = roleHierarchy[member.role.rawValue] ?? 0
        let requiredLevel = roleHierarchy[minimumRole] ?? 0

        return userRoleLevel >= requiredLevel
    }

    // MARK: - Input Validation

    private func validateTextInput(_ input: String, maxLength: Int, fieldName: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw DischargeWizardError.validationFailed("\(fieldName) cannot be empty")
        }
        guard trimmed.count <= maxLength else {
            throw DischargeWizardError.validationFailed("\(fieldName) exceeds maximum length of \(maxLength)")
        }

        // Control character check
        let controlChars = CharacterSet.controlCharacters.subtracting(.whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: controlChars) == nil else {
            throw DischargeWizardError.validationFailed("\(fieldName) contains invalid characters")
        }
    }

    // MARK: - Sanitized Logging

    private func logSanitizedError(_ error: Error, context: String) {
        // Only log error type, never the full error which may contain PHI
        let errorType = String(describing: type(of: error))
        #if DEBUG
        print("[\(context)] Error type: \(errorType)")
        #endif
    }

    // MARK: - Template Operations

    /// Fetch all available discharge templates
    func fetchTemplates() async throws -> [DischargeTemplate] {
        // First try to fetch from remote
        do {
            let templates: [DischargeTemplate] = try await supabaseClient
                .from("discharge_templates")
                .select()
                .eq("is_active", "true")
                .order("sort_order")
                .execute()

            // Cache locally
            try databaseManager.write { db in
                for template in templates {
                    try template.save(db)
                }
            }

            return templates
        } catch {
            // Fall back to local cache
            return try databaseManager.read { db in
                try DischargeTemplate
                    .filter(DischargeTemplate.Columns.isActive == true)
                    .order(DischargeTemplate.Columns.sortOrder)
                    .fetchAll(db)
            }
        }
    }

    /// Get template for a specific discharge type
    func getTemplate(for dischargeType: DischargeRecord.DischargeType) async throws -> DischargeTemplate? {
        let templateType = DischargeTemplate.template(for: dischargeType)

        // Try local first
        let localTemplate = try databaseManager.read { db in
            try DischargeTemplate
                .filter(DischargeTemplate.Columns.dischargeType == templateType)
                .filter(DischargeTemplate.Columns.isActive == true)
                .filter(DischargeTemplate.Columns.isSystem == true)
                .fetchOne(db)
        }

        if let template = localTemplate {
            return template
        }

        // Fetch from remote
        let templates = try await fetchTemplates()
        return templates.first { $0.dischargeType == templateType }
    }

    // MARK: - Discharge Record Operations

    /// Create a new discharge record
    func createDischargeRecord(
        circleId: String,
        patientId: String,
        userId: String,
        facilityName: String,
        dischargeDate: Date,
        admissionDate: Date? = nil,
        reasonForStay: String,
        dischargeType: DischargeRecord.DischargeType
    ) async throws -> DischargeRecord {
        // Validate inputs
        try validateTextInput(facilityName, maxLength: 200, fieldName: "Facility name")
        try validateTextInput(reasonForStay, maxLength: 500, fieldName: "Reason for stay")

        // Verify user has at least CONTRIBUTOR role
        guard try await verifyRole(circleId: circleId, userId: userId, minimumRole: "CONTRIBUTOR") else {
            throw DischargeWizardError.accessDenied
        }

        // Verify subscription access
        guard hasAccess() else {
            throw DischargeWizardError.accessDenied
        }

        let record = DischargeRecord(
            id: UUID().uuidString,
            circleId: circleId,
            patientId: patientId,
            createdBy: userId,
            facilityName: facilityName.trimmingCharacters(in: .whitespacesAndNewlines),
            dischargeDate: dischargeDate,
            admissionDate: admissionDate,
            reasonForStay: reasonForStay.trimmingCharacters(in: .whitespacesAndNewlines),
            dischargeType: dischargeType,
            templateId: nil,
            status: .inProgress,
            currentStep: 1,
            completedAt: nil,
            completedBy: nil,
            generatedTasks: [],
            generatedHandoffId: nil,
            generatedShifts: [],
            generatedBinderItems: [],
            checklistStateJson: nil,
            shiftAssignmentsJson: nil,
            medicationChangesJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save locally
        try databaseManager.write { db in
            try record.save(db)
        }

        // Sync to remote
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "INSERT",
            entityType: "discharge_records",
            entityId: record.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(record), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))

        // Initialize checklist items from template
        if let template = try await getTemplate(for: dischargeType) {
            try await initializeChecklist(for: record, from: template)
        }

        return record
    }

    /// Get the active discharge record for a patient
    func getActiveRecord(circleId: String, patientId: String) async throws -> DischargeRecord? {
        try databaseManager.read { db in
            try DischargeRecord
                .filter(DischargeRecord.Columns.circleId == circleId)
                .filter(DischargeRecord.Columns.patientId == patientId)
                .filter(DischargeRecord.Columns.status == DischargeRecord.Status.inProgress.rawValue)
                .order(DischargeRecord.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    /// Get a discharge record by ID
    func getRecord(id: String) async throws -> DischargeRecord? {
        try databaseManager.read { db in
            try DischargeRecord.fetchOne(db, key: id)
        }
    }

    /// Update discharge record
    func updateRecord(_ record: DischargeRecord) async throws {
        var updatedRecord = record
        updatedRecord.updatedAt = Date()

        try databaseManager.write { db in
            try updatedRecord.update(db)
        }

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "discharge_records",
            entityId: record.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(updatedRecord), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    /// Update current wizard step
    func updateStep(recordId: String, step: Int) async throws {
        guard var record = try await getRecord(id: recordId) else {
            throw DischargeWizardError.recordNotFound
        }

        record.currentStep = step
        try await updateRecord(record)
    }

    /// Save checklist state for resume capability
    func saveChecklistState(recordId: String, state: ChecklistState) async throws {
        guard var record = try await getRecord(id: recordId) else {
            throw DischargeWizardError.recordNotFound
        }

        record.checklistState = state
        try await updateRecord(record)
    }

    /// Save shift assignments
    func saveShiftAssignments(recordId: String, assignments: [Int: String]) async throws {
        guard var record = try await getRecord(id: recordId) else {
            throw DischargeWizardError.recordNotFound
        }

        record.shiftAssignments = assignments
        try await updateRecord(record)
    }

    /// Save medication changes
    func saveMedicationChanges(recordId: String, changes: [DischargeMedicationChange]) async throws {
        guard var record = try await getRecord(id: recordId) else {
            throw DischargeWizardError.recordNotFound
        }

        record.medicationChanges = changes
        try await updateRecord(record)
    }

    /// Cancel a discharge record
    func cancelRecord(id: String) async throws {
        guard var record = try await getRecord(id: id) else {
            throw DischargeWizardError.recordNotFound
        }

        record.status = .cancelled
        record.updatedAt = Date()
        try await updateRecord(record)
    }

    // MARK: - Checklist Item Operations

    /// Initialize checklist items from a template
    private func initializeChecklist(
        for record: DischargeRecord,
        from template: DischargeTemplate
    ) async throws {
        let items = DischargeChecklistItem.createItems(
            from: template,
            dischargeRecordId: record.id
        )

        try databaseManager.write { db in
            for item in items {
                try item.save(db)
            }
        }

        // Update record with template ID
        var updatedRecord = record
        updatedRecord.templateId = template.id
        try await updateRecord(updatedRecord)
    }

    /// Get checklist items for a discharge record
    func getChecklistItems(recordId: String) async throws -> [DischargeChecklistItem] {
        try databaseManager.read { db in
            try DischargeChecklistItem
                .filter(DischargeChecklistItem.Columns.dischargeRecordId == recordId)
                .order(DischargeChecklistItem.Columns.category)
                .order(DischargeChecklistItem.Columns.sortOrder)
                .fetchAll(db)
        }
    }

    /// Update a checklist item
    func updateChecklistItem(_ item: DischargeChecklistItem) async throws {
        var updatedItem = item
        updatedItem.updatedAt = Date()

        try databaseManager.write { db in
            try updatedItem.update(db)
        }

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "discharge_checklist_items",
            entityId: item.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(updatedItem), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    /// Toggle checklist item completion
    func toggleItemCompletion(
        itemId: String,
        userId: String
    ) async throws -> DischargeChecklistItem {
        guard var item = try databaseManager.read({ db in
            try DischargeChecklistItem.fetchOne(db, key: itemId)
        }) else {
            throw DischargeWizardError.itemNotFound
        }

        if item.isCompleted {
            item.isCompleted = false
            item.completedAt = nil
            item.completedBy = nil
        } else {
            item.isCompleted = true
            item.completedAt = Date()
            item.completedBy = userId
        }

        try await updateChecklistItem(item)
        return item
    }

    /// Configure task creation for a checklist item
    func configureTaskForItem(
        itemId: String,
        createTask: Bool,
        assignedTo: String?,
        dueDate: Date?
    ) async throws {
        guard var item = try databaseManager.read({ db in
            try DischargeChecklistItem.fetchOne(db, key: itemId)
        }) else {
            throw DischargeWizardError.itemNotFound
        }

        item.createTask = createTask
        item.assignedTo = assignedTo
        item.dueDate = dueDate
        try await updateChecklistItem(item)
    }

    // MARK: - Output Generation

    /// Generate all outputs (tasks, handoff, shifts) from completed wizard
    func generateOutputs(recordId: String, userId: String) async throws -> GenerateOutputsResult {
        guard let record = try await getRecord(id: recordId) else {
            throw DischargeWizardError.recordNotFound
        }

        // Verify user has access to this circle
        guard try await verifyCircleMembership(circleId: record.circleId, userId: userId) else {
            throw DischargeWizardError.accessDenied
        }

        // Verify subscription access
        guard hasAccess() else {
            throw DischargeWizardError.accessDenied
        }

        // Call Edge Function with timeout
        let request = GenerateOutputsRequest(dischargeRecordId: recordId)

        do {
            let response: GenerateOutputsResponse = try await withTimeout(seconds: 60) {
                try await self.supabaseClient
                    .functions("generate-discharge-outputs")
                    .invoke(body: request)
            }

            // Update record with generated IDs
            var updatedRecord = record
            updatedRecord.generatedTasks = response.tasksCreated
            updatedRecord.generatedHandoffId = response.handoffId
            updatedRecord.generatedShifts = response.shiftsCreated
            updatedRecord.generatedBinderItems = response.binderItemsCreated
            updatedRecord.status = .completed
            updatedRecord.completedAt = Date()
            updatedRecord.completedBy = userId

            try await updateRecord(updatedRecord)

            return GenerateOutputsResult(
                tasksCreated: response.tasksCreated.count,
                handoffCreated: response.handoffId != nil,
                shiftsCreated: response.shiftsCreated.count,
                binderItemsCreated: response.binderItemsCreated.count
            )
        } catch let error as GenerateOutputsError {
            // Handle partial success
            if let partial = error.partialSuccess {
                logSanitizedError(error, context: "generateOutputs-partial")
                throw DischargeWizardError.partialFailure(
                    created: GenerateOutputsResult(
                        tasksCreated: partial.tasksCreated,
                        handoffCreated: partial.handoffCreated,
                        shiftsCreated: partial.shiftsCreated,
                        binderItemsCreated: partial.binderItemsCreated
                    )
                )
            }
            throw DischargeWizardError.generationFailed(error.localizedDescription)
        } catch {
            if error is TimeoutError {
                throw DischargeWizardError.generationFailed("Request timed out. Please try again.")
            }
            logSanitizedError(error, context: "generateOutputs")
            throw DischargeWizardError.generationFailed("An unexpected error occurred")
        }
    }

    /// Preview outputs that will be generated
    func previewOutputs(recordId: String) async throws -> DischargeOutputSummary {
        let items = try await getChecklistItems(recordId: recordId)
        guard let record = try await getRecord(id: recordId) else {
            throw DischargeWizardError.recordNotFound
        }

        let tasksToCreate = items.filter { $0.createTask && $0.taskId == nil }
        let shiftAssignments = record.shiftAssignments ?? [:]
        let medChanges = record.medicationChanges ?? []

        return DischargeOutputSummary(
            tasksToCreate: tasksToCreate.count,
            medicationTasks: items.filter { $0.category == .medications && $0.createTask }.count,
            equipmentTasks: items.filter { $0.category == .equipment && $0.createTask }.count,
            appointmentTasks: 0,  // Calculated from follow-ups step
            careScheduleTasks: 0,  // Calculated from care schedule step
            binderUpdates: medChanges.count,
            newMedications: medChanges.filter { $0.changeType == .new }.count,
            newContacts: 0,  // From facility/provider entries
            shiftsScheduled: shiftAssignments.count,
            handoffCreated: true
        )
    }
}

// MARK: - Timeout Helper

struct TimeoutError: Error {}

func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Request/Response Types

struct GenerateOutputsRequest: Encodable {
    let dischargeRecordId: String
}

struct GenerateOutputsResponse: Decodable {
    let tasksCreated: [String]
    let handoffId: String?
    let shiftsCreated: [String]
    let binderItemsCreated: [String]
}

struct GenerateOutputsErrorResponse: Decodable {
    let error: String
    let partialSuccess: PartialSuccess?

    struct PartialSuccess: Decodable {
        let tasksCreated: Int
        let shiftsCreated: Int
        let binderItemsCreated: Int
        let handoffCreated: Bool
    }
}

struct GenerateOutputsError: Error {
    let message: String
    let partialSuccess: PartialSuccess?

    struct PartialSuccess {
        let tasksCreated: Int
        let shiftsCreated: Int
        let binderItemsCreated: Int
        let handoffCreated: Bool
    }
}

struct GenerateOutputsResult {
    let tasksCreated: Int
    let handoffCreated: Bool
    let shiftsCreated: Int
    let binderItemsCreated: Int

    var summary: String {
        var parts: [String] = []
        if tasksCreated > 0 {
            parts.append("\(tasksCreated) task\(tasksCreated == 1 ? "" : "s")")
        }
        if handoffCreated {
            parts.append("1 handoff")
        }
        if shiftsCreated > 0 {
            parts.append("\(shiftsCreated) shift\(shiftsCreated == 1 ? "" : "s")")
        }
        if binderItemsCreated > 0 {
            parts.append("\(binderItemsCreated) binder item\(binderItemsCreated == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Errors

enum DischargeWizardError: Error, LocalizedError {
    case recordNotFound
    case itemNotFound
    case templateNotFound
    case accessDenied
    case generationFailed(String)
    case validationFailed(String)
    case partialFailure(created: GenerateOutputsResult)
    case timeout

    var errorDescription: String? {
        switch self {
        case .recordNotFound:
            return "Discharge record not found"
        case .itemNotFound:
            return "Checklist item not found"
        case .templateNotFound:
            return "Discharge template not found"
        case .accessDenied:
            return "You don't have access to the Discharge Wizard. Upgrade to Plus or Family to use this feature."
        case .generationFailed(let reason):
            return "Failed to generate outputs: \(reason)"
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .partialFailure(let created):
            return "Some outputs were created but the operation didn't complete fully. Created: \(created.summary)"
        case .timeout:
            return "The operation timed out. Please try again."
        }
    }
}
