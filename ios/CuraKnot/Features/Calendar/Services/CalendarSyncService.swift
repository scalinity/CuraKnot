import Foundation
import GRDB
import Combine
import os.log
import EventKit

// MARK: - Calendar Sync Service

/// Orchestrates calendar synchronization between CuraKnot and external calendar providers
@MainActor
final class CalendarSyncService: ObservableObject {
    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient
    private let syncCoordinator: SyncCoordinator
    private let appleProvider: AppleCalendarProvider

    // MARK: - Logging

    private static let logger = Logger(subsystem: "com.curaknot", category: "CalendarSync")

    // MARK: - Published State

    @Published var connections: [CalendarConnection] = []
    @Published var isSyncing: Bool = false
    @Published var lastSyncError: Error?
    @Published var syncWarning: String?  // Non-fatal warnings for UI display
    @Published var accessLevel: CalendarAccessLevel = .none
    @Published var pendingConflicts: [CalendarEvent] = []

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var syncTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        syncCoordinator: SyncCoordinator,
        appleProvider: AppleCalendarProvider
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.syncCoordinator = syncCoordinator
        self.appleProvider = appleProvider

        setupObservers()
    }

    deinit {
        syncTask?.cancel()
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func setupObservers() {
        // Observe Apple Calendar changes
        changeObserver = NotificationCenter.default.addObserver(
            forName: .appleCalendarDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAppleCalendarChange()
            }
        }
    }

    // MARK: - Access Level

    /// Check user's calendar access level based on subscription tier
    func checkAccessLevel(circleId: String, userId: String? = nil) async {
        do {
            guard let effectiveUserId = userId, !effectiveUserId.isEmpty else {
                Self.logger.warning("No user ID provided for calendar access check")
                accessLevel = .none
                return
            }

            // RPC returns a TEXT value directly
            let level: String = try await supabaseClient.rpc(
                "has_calendar_access",
                params: ["p_user_id": effectiveUserId, "p_circle_id": circleId]
            )

            switch level {
            case "MULTI_PROVIDER":
                accessLevel = .multiProvider
            case "SINGLE_PROVIDER":
                accessLevel = .singleProvider
            case "READ_ONLY":
                accessLevel = .readOnly
            default:
                accessLevel = .none
            }
        } catch {
            // SECURITY: Use sanitized error code to prevent PHI leakage in logs
            Self.logger.error("Failed to check calendar access level: \(error.sanitizedErrorCode)")
            accessLevel = .none
            syncWarning = "Unable to verify calendar access. Some features may be limited."
        }
    }

    // MARK: - Connection Management

    /// Load calendar connections for a circle
    func loadConnections(circleId: String) async throws {
        connections = try databaseManager.read { db in
            try CalendarConnection
                .filter(CalendarConnection.Columns.circleId == circleId)
                .fetchAll(db)
        }

        // Also fetch from server and merge
        await syncConnections(circleId: circleId)
    }

    /// Sync connections from server
    private func syncConnections(circleId: String) async {
        do {
            let remoteConnections: [CalendarConnection] = try await supabaseClient
                .from("calendar_connections")
                .select()
                .eq("circle_id", circleId)
                .execute()

            // Update local database
            try databaseManager.write { db in
                for connection in remoteConnections {
                    try connection.save(db)
                }
            }

            connections = remoteConnections
            syncWarning = nil  // Clear any previous warning on success
        } catch {
            // SECURITY: Use sanitized error code to prevent PHI leakage in logs
            Self.logger.error("Failed to sync calendar connections: \(error.sanitizedErrorCode)")
            syncWarning = "Unable to sync calendar settings. Using cached data."
        }
    }

    /// Connect Apple Calendar
    func connectAppleCalendar(
        circleId: String,
        userId: String,
        calendarId: String,
        calendarTitle: String,
        syncDirection: SyncDirection = .bidirectional,
        conflictStrategy: ConflictStrategy = .curaknotWins
    ) async throws -> CalendarConnection {
        // Request access if needed
        if !appleProvider.isAuthorized {
            let granted = try await appleProvider.requestAccess()
            guard granted else {
                throw CalendarError.notAuthorized
            }
        }

        let connection = CalendarConnection(
            userId: userId,
            circleId: circleId,
            provider: .apple,
            status: .active,
            appleCalendarId: calendarId,
            appleCalendarTitle: calendarTitle
        )

        // Save locally
        try databaseManager.write { db in
            try connection.save(db)
        }

        // Save to server
        try await supabaseClient
            .from("calendar_connections")
            .upsert(connection.toSupabasePayload())

        // Add to local list
        connections.append(connection)

        // Perform initial sync
        try await syncConnection(connection)

        // SECURITY: Audit the connection
        await logAuditEvent(
            circleId: circleId,
            eventType: .calendarConnected,
            objectType: "calendar_connection",
            objectId: connection.id,
            metadata: [
                "provider": CalendarProvider.apple.rawValue,
                "sync_direction": syncDirection.rawValue
            ]
        )

        return connection
    }

    /// Disconnect a calendar provider
    func disconnectProvider(connectionId: String) async throws {
        guard let connection = connections.first(where: { $0.id == connectionId }) else {
            throw CalendarError.calendarNotFound
        }

        // Delete from server
        try await supabaseClient
            .from("calendar_connections")
            .eq("id", connectionId)
            .delete()

        // Delete locally
        try databaseManager.write { db in
            try CalendarConnection
                .filter(CalendarConnection.Columns.id == connectionId)
                .deleteAll(db)
        }

        // Remove from local list
        connections.removeAll { $0.id == connectionId }

        // SECURITY: Audit the disconnection
        await logAuditEvent(
            circleId: connection.circleId,
            eventType: .calendarDisconnected,
            objectType: "calendar_connection",
            objectId: connectionId,
            metadata: ["provider": connection.provider.rawValue]
        )
    }

    /// Update connection settings
    func updateConnection(_ connection: CalendarConnection) async throws {
        var updatedConnection = connection
        updatedConnection.updatedAt = Date()

        try databaseManager.write { db in
            try updatedConnection.update(db)
        }

        try await supabaseClient
            .from("calendar_connections")
            .eq("id", connection.id)
            .update(updatedConnection.toSupabasePayload())

        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = updatedConnection
        }
    }

    // MARK: - Sync Operations

    /// Sync all active connections
    func syncAll(circleId: String) async {
        guard !isSyncing else {
            Self.logger.info("Sync already in progress, skipping")
            return
        }
        isSyncing = true
        lastSyncError = nil

        defer { isSyncing = false }

        let activeConnections = connections.filter { $0.status == .active }
        Self.logger.info("Starting sync for \(activeConnections.count) active connections")

        for connection in activeConnections {
            // Check for task cancellation between connections
            if Task.isCancelled {
                Self.logger.info("Sync cancelled")
                return
            }

            do {
                try await syncWithRetry(connection, maxAttempts: 3)
            } catch is CancellationError {
                Self.logger.info("Sync cancelled during connection \(connection.id)")
                return
            } catch {
                // SECURITY: Use sanitized error code to prevent PHI leakage in logs
                Self.logger.error("Sync failed for connection \(connection.id): \(error.sanitizedErrorCode)")
                lastSyncError = error
            }
        }
    }

    /// Sync with exponential backoff retry
    private func syncWithRetry(_ connection: CalendarConnection, maxAttempts: Int = 3) async throws {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            // Check for cancellation before each attempt
            try Task.checkCancellation()

            do {
                try await syncConnection(connection)
                Self.logger.info("Sync succeeded for \(connection.provider.rawValue) on attempt \(attempt)")
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                // SECURITY: Use sanitized error code to prevent PHI leakage in logs
                Self.logger.warning("Sync attempt \(attempt)/\(maxAttempts) failed: \(error.sanitizedErrorCode)")

                if attempt < maxAttempts {
                    // Exponential backoff: 1s, 2s, 4s - use try to propagate cancellation
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        if let error = lastError {
            throw error
        }
    }

    /// Sync a specific connection
    func syncConnection(_ connection: CalendarConnection) async throws {
        switch connection.provider {
        case .apple:
            try await syncAppleCalendar(connection)
        case .google, .outlook:
            // OAuth providers sync via Edge Function
            try await syncOAuthProvider(connection)
        }
    }

    /// Sync with Apple Calendar via EventKit
    private func syncAppleCalendar(_ connection: CalendarConnection) async throws {
        guard let calendarId = connection.appleCalendarId else {
            throw CalendarError.calendarNotFound
        }

        let syncStartTime = Date()
        let lastSyncDate = connection.lastSyncAt ?? Date.distantPast

        // 1. Push local changes to calendar
        if connection.syncDirection != .readOnly {
            try await pushLocalChanges(connection: connection, calendarId: calendarId)
        }

        // 2. Pull external changes from calendar
        if connection.syncDirection != .writeOnly {
            try await pullExternalChanges(connection: connection, calendarId: calendarId, since: lastSyncDate)
        }

        // 3. Update connection sync state
        var updatedConnection = connection
        updatedConnection.lastSyncAt = syncStartTime
        updatedConnection.lastSyncStatus = "SUCCESS"
        updatedConnection.lastSyncError = nil
        updatedConnection.updatedAt = Date()

        try databaseManager.write { db in
            try updatedConnection.update(db)
        }

        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = updatedConnection
        }
    }

    /// Push local calendar changes to external provider
    private func pushLocalChanges(connection: CalendarConnection, calendarId: String) async throws {
        // Fetch pending events
        let pendingEvents = try databaseManager.read { db in
            try CalendarEvent
                .filter(CalendarEvent.Columns.connectionId == connection.id)
                .filter(CalendarEvent.Columns.syncStatus == CalendarSyncStatus.pendingPush.rawValue)
                .fetchAll(db)
        }

        var syncedCount = 0
        for event in pendingEvents {
            do {
                if event.externalEventId.isEmpty {
                    // Create new event
                    let externalId = try appleProvider.createEvent(from: event, in: calendarId)
                    var updatedEvent = event
                    updatedEvent.externalEventId = externalId
                    updatedEvent.syncStatus = .synced
                    updatedEvent.lastSyncedAt = Date()
                    // SECURITY: Update checksum before persisting
                    updatedEvent.updateChecksum()

                    try databaseManager.write { db in
                        try updatedEvent.update(db)
                    }
                    syncedCount += 1
                } else {
                    // Update existing event
                    try appleProvider.updateEvent(eventIdentifier: event.externalEventId, with: event)
                    var updatedEvent = event
                    updatedEvent.syncStatus = .synced
                    updatedEvent.lastSyncedAt = Date()
                    // SECURITY: Update checksum before persisting
                    updatedEvent.updateChecksum()

                    try databaseManager.write { db in
                        try updatedEvent.update(db)
                    }
                    syncedCount += 1
                }
            } catch {
                // SECURITY: Use sanitized error code in logs AND stored in database
                Self.logger.error("Failed to push event \(event.id): \(error.sanitizedErrorCode)")
                var errorEvent = event
                errorEvent.syncStatus = .error
                errorEvent.syncError = error.sanitizedErrorCode

                try? databaseManager.write { db in
                    try errorEvent.update(db)
                }
            }
        }

        // SECURITY: Audit sync completion
        if syncedCount > 0 {
            await logAuditEvent(
                circleId: connection.circleId,
                eventType: .calendarSynced,
                objectType: "calendar_connection",
                objectId: connection.id,
                metadata: [
                    "provider": connection.provider.rawValue,
                    "sync_direction": "push",
                    "event_count": syncedCount
                ]
            )
        }

        // Handle deleted events
        let deletedEvents = try databaseManager.read { db in
            try CalendarEvent
                .filter(CalendarEvent.Columns.connectionId == connection.id)
                .filter(CalendarEvent.Columns.syncStatus == CalendarSyncStatus.deleted.rawValue)
                .fetchAll(db)
        }

        for event in deletedEvents {
            do {
                try appleProvider.deleteEvent(eventIdentifier: event.externalEventId)

                try databaseManager.write { db in
                    try CalendarEvent
                        .filter(CalendarEvent.Columns.id == event.id)
                        .deleteAll(db)
                }
            } catch {
                // SECURITY: Use sanitized error code to prevent PHI leakage in logs
                Self.logger.error("Failed to delete event \(event.id): \(error.sanitizedErrorCode)")
            }
        }
    }

    /// Pull external calendar changes into CuraKnot
    private func pullExternalChanges(connection: CalendarConnection, calendarId: String, since: Date) async throws {
        let externalEvents = appleProvider.fetchCuraKnotEvents(in: calendarId, since: since)

        for ekEvent in externalEvents {
            // Find corresponding local event
            let localEvent = try databaseManager.read { db -> CalendarEvent? in
                try CalendarEvent
                    .filter(CalendarEvent.Columns.connectionId == connection.id)
                    .filter(CalendarEvent.Columns.externalEventId == ekEvent.eventIdentifier)
                    .fetchOne(db)
            }

            if let localEvent = localEvent {
                let localModified = localEvent.localUpdatedAt.timeIntervalSince1970
                let externalModified = ekEvent.lastModifiedDate?.timeIntervalSince1970 ?? 0
                let lastSynced = localEvent.lastSyncedAt?.timeIntervalSince1970 ?? 0

                // Check for conflicts
                let localChanged = localModified > lastSynced
                let externalChanged = externalModified > lastSynced

                if localChanged && externalChanged {
                    // Both sides modified - conflict!
                    try handleConflict(localEvent: localEvent, externalEvent: ekEvent, connection: connection)
                } else if externalChanged {
                    // External is newer - update local
                    try updateLocalFromExternal(localEvent: localEvent, externalEvent: ekEvent, connection: connection)
                }
            }
        }
    }

    /// Handle a sync conflict
    private func handleConflict(localEvent: CalendarEvent, externalEvent: EKEvent, connection: CalendarConnection) throws {
        switch connection.conflictStrategy {
        case .curaknotWins:
            // Push local to external
            var updatedEvent = localEvent
            updatedEvent.syncStatus = .pendingPush
            updatedEvent.updateChecksum()
            try databaseManager.write { db in
                try updatedEvent.update(db)
            }

        case .externalWins:
            // Pull external to local
            try updateLocalFromExternal(localEvent: localEvent, externalEvent: externalEvent, connection: connection)

        case .manual:
            // Mark as conflict for manual resolution
            let externalSnapshot = CalendarEventConflict.CalendarEventSnapshot(
                title: externalEvent.title ?? "",
                description: externalEvent.notes,
                startAt: externalEvent.startDate,
                endAt: externalEvent.endDate,
                allDay: externalEvent.isAllDay,
                location: externalEvent.location,
                updatedAt: externalEvent.lastModifiedDate ?? Date()
            )

            let localSnapshot = CalendarEventConflict.CalendarEventSnapshot(
                title: localEvent.title,
                description: localEvent.eventDescription,
                startAt: localEvent.startAt,
                endAt: localEvent.endAt,
                allDay: localEvent.allDay,
                location: localEvent.location,
                updatedAt: localEvent.localUpdatedAt
            )

            let conflict = CalendarEventConflict(
                localVersion: localSnapshot,
                externalVersion: externalSnapshot,
                detectedAt: Date(),
                fieldConflicts: detectFieldConflicts(local: localSnapshot, external: externalSnapshot)
            )

            var conflictEvent = localEvent
            conflictEvent.syncStatus = .conflict
            // SECURITY: Use encrypted conflict data storage
            conflictEvent.setConflictData(conflict)
            conflictEvent.conflictDetectedAt = Date()
            conflictEvent.updateChecksum()

            try databaseManager.write { db in
                try conflictEvent.update(db)
            }

            pendingConflicts.append(conflictEvent)

            // SECURITY: Audit conflict detection
            Task {
                await logAuditEvent(
                    circleId: connection.circleId,
                    eventType: .conflictDetected,
                    objectType: "calendar_event",
                    objectId: localEvent.id,
                    metadata: ["conflict_strategy": connection.conflictStrategy.rawValue]
                )
            }

        case .merge:
            // Merge non-conflicting fields
            try mergeConflict(localEvent: localEvent, externalEvent: externalEvent, connection: connection)
        }
    }

    /// Update local event from external calendar
    /// SECURITY: Sanitizes all external input before storing locally
    private func updateLocalFromExternal(localEvent: CalendarEvent, externalEvent: EKEvent, connection: CalendarConnection) throws {
        var updatedEvent = localEvent

        // SECURITY: Sanitize and validate all external input
        // External calendars are untrusted sources - validate before storing
        updatedEvent.title = Self.sanitizeInput(externalEvent.title, maxLength: 200) ?? localEvent.title
        updatedEvent.eventDescription = Self.sanitizeInput(externalEvent.notes, maxLength: 2000)
        updatedEvent.location = Self.sanitizeInput(externalEvent.location, maxLength: 200)

        // Validate date ranges - EKEvent dates can be nil in some edge cases
        guard let startDate = externalEvent.startDate else {
            Self.logger.warning("External event missing start date, skipping update")
            return
        }
        let endDate = externalEvent.endDate

        // Reject obviously invalid date ranges (end before start, or spans > 1 year)
        if let end = endDate {
            let maxSpan: TimeInterval = 365 * 24 * 60 * 60 // 1 year
            if end < startDate || end.timeIntervalSince(startDate) > maxSpan {
                Self.logger.warning("Rejected invalid date range from external calendar")
                return // Reject the update
            }
        }

        updatedEvent.startAt = startDate
        updatedEvent.endAt = endDate
        updatedEvent.allDay = externalEvent.isAllDay
        updatedEvent.externalUpdatedAt = externalEvent.lastModifiedDate
        updatedEvent.lastSyncedAt = Date()
        updatedEvent.syncStatus = .synced

        try databaseManager.write { db in
            try updatedEvent.update(db)
        }

        // Update source entity if bi-directional for appointments
        if localEvent.sourceType == .appointment,
           connection.syncDirection == .bidirectional {
            // Update would go through binder service
            // NotificationCenter.default.post for binderItemNeedsUpdate
        }
    }

    /// Merge non-conflicting fields from both versions
    private func mergeConflict(localEvent: CalendarEvent, externalEvent: EKEvent, connection: CalendarConnection) throws {
        // For merge strategy: keep local title/description (source of truth for care data)
        // but accept external time changes (user may reschedule in calendar)
        var mergedEvent = localEvent
        mergedEvent.startAt = externalEvent.startDate
        mergedEvent.endAt = externalEvent.endDate
        mergedEvent.allDay = externalEvent.isAllDay
        mergedEvent.location = externalEvent.location ?? localEvent.location
        mergedEvent.externalUpdatedAt = externalEvent.lastModifiedDate
        mergedEvent.lastSyncedAt = Date()
        mergedEvent.syncStatus = .pendingPush  // Push merged result back
        mergedEvent.conflictResolution = "MERGED"

        try databaseManager.write { db in
            try mergedEvent.update(db)
        }
    }

    /// Detect which fields have conflicts
    private func detectFieldConflicts(
        local: CalendarEventConflict.CalendarEventSnapshot,
        external: CalendarEventConflict.CalendarEventSnapshot
    ) -> [String] {
        var conflicts: [String] = []

        if local.title != external.title { conflicts.append("title") }
        if local.description != external.description { conflicts.append("description") }
        if local.startAt != external.startAt { conflicts.append("startAt") }
        if local.endAt != external.endAt { conflicts.append("endAt") }
        if local.allDay != external.allDay { conflicts.append("allDay") }
        if local.location != external.location { conflicts.append("location") }

        return conflicts
    }

    /// Sync with OAuth provider via Edge Function
    private func syncOAuthProvider(_ connection: CalendarConnection) async throws {
        // Call calendar-sync Edge Function
        struct SyncRequest: Encodable {
            let connection_id: String
            let full_sync: Bool
        }

        struct SyncResponse: Decodable {
            let success: Bool
            let events_pushed: Int?
            let events_pulled: Int?
            let conflicts: Int?
            let error: ErrorInfo?

            struct ErrorInfo: Decodable {
                let code: String
                let message: String
            }
        }

        let response: SyncResponse = try await supabaseClient
            .functions("calendar-sync")
            .invoke(body: SyncRequest(connection_id: connection.id, full_sync: false))

        if !response.success, let error = response.error {
            throw CalendarSyncError.serverError(code: error.code, message: error.message)
        }
    }

    // MARK: - Conflict Resolution

    /// Resolve a conflict with the specified resolution
    func resolveConflict(eventId: String, resolution: CalendarConflictResolution) async throws {
        guard var event = try databaseManager.read({ db in
            try CalendarEvent.filter(CalendarEvent.Columns.id == eventId).fetchOne(db)
        }) else {
            throw CalendarError.eventNotFound
        }

        let circleId = event.circleId

        switch resolution {
        case .keepLocal:
            event.syncStatus = .pendingPush
            event.conflictResolution = "LOCAL"

        case .keepExternal:
            // Apply external version using decrypted conflict data
            if let conflict = event.conflictData {
                event.title = conflict.externalVersion.title
                event.eventDescription = conflict.externalVersion.description
                event.startAt = conflict.externalVersion.startAt
                event.endAt = conflict.externalVersion.endAt
                event.allDay = conflict.externalVersion.allDay
                event.location = conflict.externalVersion.location
            }
            event.syncStatus = .synced
            event.conflictResolution = "EXTERNAL"

        case .merge:
            // Keep local content but external time
            if let conflict = event.conflictData {
                event.startAt = conflict.externalVersion.startAt
                event.endAt = conflict.externalVersion.endAt
                event.allDay = conflict.externalVersion.allDay
            }
            event.syncStatus = .pendingPush
            event.conflictResolution = "MERGED"

        case .discard:
            event.syncStatus = .synced
            event.conflictResolution = "DISCARDED"
        }

        event.conflictResolvedAt = Date()
        event.conflictDataJson = nil  // Clear encrypted conflict data after resolution
        // SECURITY: Update checksum before persisting
        event.updateChecksum()

        try databaseManager.write { db in
            try event.update(db)
        }

        pendingConflicts.removeAll { $0.id == eventId }

        // SECURITY: Audit conflict resolution
        await logAuditEvent(
            circleId: circleId,
            eventType: .conflictResolved,
            objectType: "calendar_event",
            objectId: eventId,
            metadata: ["resolution": resolution.rawValue]
        )
    }

    // MARK: - Event Creation

    /// Create a calendar event from a task
    func createEventFromTask(_ task: CareTask, connectionId: String) async throws {
        guard let connection = connections.first(where: { $0.id == connectionId }),
              connection.syncTasks else {
            return
        }

        guard let calendarEvent = CalendarEvent.fromTask(
            task,
            connectionId: connectionId,
            circleId: connection.circleId,
            externalEventId: "",
            showMinimalDetails: connection.showMinimalDetails
        ) else {
            return // Task has no due date
        }

        try databaseManager.write { db in
            try calendarEvent.save(db)
        }

        // Trigger sync
        try await syncConnection(connection)
    }

    /// Mark a task's calendar event for deletion
    func deleteEventForTask(taskId: String) async throws {
        let events = try databaseManager.read { db in
            try CalendarEvent
                .filter(CalendarEvent.Columns.sourceTaskId == taskId)
                .fetchAll(db)
        }

        for var event in events {
            event.syncStatus = .deleted
            try databaseManager.write { db in
                try event.update(db)
            }

            if let connection = connections.first(where: { $0.id == event.connectionId }) {
                try await syncConnection(connection)
            }
        }
    }

    // MARK: - Background Sync

    /// Perform background sync (called from BGTaskScheduler)
    func performBackgroundSync() async throws {
        for connection in connections where connection.status == .active {
            try await syncConnection(connection)
        }
    }

    /// Handle Apple Calendar change notification
    private func handleAppleCalendarChange() async {
        // Find active Apple Calendar connections and sync
        let appleConnections = connections.filter {
            $0.provider == .apple && $0.status == .active
        }

        Self.logger.info("Apple Calendar changed, syncing \(appleConnections.count) connections")

        for connection in appleConnections {
            do {
                try await syncConnection(connection)
            } catch {
                // SECURITY: Use sanitized error code to prevent PHI leakage in logs
                Self.logger.error("Background sync failed for \(connection.id): \(error.sanitizedErrorCode)")
            }
        }
    }

    // MARK: - Audit Logging

    /// Log a calendar operation to the audit trail
    /// SECURITY: All sensitive calendar operations must be audited for compliance
    private func logAuditEvent(
        circleId: String,
        eventType: CalendarAuditEventType,
        objectType: String,
        objectId: String?,
        metadata: [String: Any]? = nil
    ) async {
        do {
            // Build metadata JSON - filter out any PHI
            var safeMetadata: [String: Any] = [:]
            if let metadata = metadata {
                // Only include safe fields, never titles/descriptions
                for (key, value) in metadata {
                    if ["provider", "sync_direction", "conflict_strategy", "resolution", "event_count", "error_code"].contains(key) {
                        safeMetadata[key] = value
                    }
                }
            }

            let auditPayload: [String: Any] = [
                "circle_id": circleId,
                "event_type": eventType.rawValue,
                "object_type": objectType,
                "object_id": objectId as Any,
                "metadata_json": safeMetadata
            ]

            try await supabaseClient
                .from("audit_events")
                .insert(auditPayload)

            Self.logger.debug("Audit: \(eventType.rawValue, privacy: .public) on \(objectType, privacy: .public)")
        } catch {
            // Don't fail operations due to audit logging errors, but log them
            Self.logger.error("Failed to log audit event: \(error.sanitizedErrorCode, privacy: .public)")
        }
    }
}

// MARK: - Calendar Audit Event Types

enum CalendarAuditEventType: String {
    case calendarConnected = "CALENDAR_CONNECTED"
    case calendarDisconnected = "CALENDAR_DISCONNECTED"
    case calendarSynced = "CALENDAR_SYNCED"
    case conflictDetected = "CALENDAR_CONFLICT_DETECTED"
    case conflictResolved = "CALENDAR_CONFLICT_RESOLVED"
    case syncFailed = "CALENDAR_SYNC_FAILED"
}

// MARK: - Conflict Resolution

enum CalendarConflictResolution: String {
    case keepLocal = "KEEP_LOCAL"
    case keepExternal = "KEEP_EXTERNAL"
    case merge = "MERGE"
    case discard = "DISCARD"
}

// MARK: - Calendar Sync Errors

enum CalendarSyncError: LocalizedError {
    case serverError(code: String, message: String)
    case networkError
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .serverError(_, let message):
            return message
        case .networkError:
            return "Network connection unavailable"
        case .unauthorized:
            return "Please reconnect your calendar"
        }
    }
}

// MARK: - PHI-Safe Error Handling

extension Error {
    /// SECURITY: Returns a sanitized error code suitable for logging without PHI exposure
    /// Per CLAUDE.md: "No PHI in logs, crash reports, or analytics events"
    var sanitizedErrorCode: String {
        if let calError = self as? CalendarError {
            switch calError {
            case .notAuthorized: return "CAL_NOT_AUTHORIZED"
            case .calendarNotFound: return "CAL_NOT_FOUND"
            case .eventNotFound: return "CAL_EVENT_NOT_FOUND"
            case .noCalendarSource: return "CAL_NO_SOURCE"
            case .saveFailed: return "CAL_SAVE_FAILED"
            case .invalidConfiguration: return "CAL_INVALID_CONFIG"
            }
        }
        if let syncError = self as? CalendarSyncError {
            switch syncError {
            case .serverError(let code, _): return "SYNC_SERVER_\(code)"
            case .networkError: return "SYNC_NETWORK"
            case .unauthorized: return "SYNC_UNAUTHORIZED"
            }
        }
        if let nsError = self as NSError? {
            return "ERR_\(nsError.domain)_\(nsError.code)"
        }
        return "ERR_UNKNOWN"
    }
}

// MARK: - Input Sanitization

extension CalendarSyncService {
    /// SECURITY: Sanitizes external input to prevent injection attacks
    /// Used when pulling data from external calendars (untrusted sources)
    static func sanitizeInput(_ input: String?, maxLength: Int = 1000) -> String? {
        guard let input = input else { return nil }

        // Trim whitespace
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if empty after trimming
        guard !trimmed.isEmpty else { return nil }

        // Enforce max length
        guard trimmed.count <= maxLength else {
            return String(trimmed.prefix(maxLength))
        }

        // Remove control characters (except newlines in descriptions)
        return trimmed.unicodeScalars
            .filter { !CharacterSet.controlCharacters.subtracting(.newlines).contains($0) }
            .map { Character($0) }
            .reduce(into: "") { $0.append($1) }
    }
}
