import Foundation
import GRDB

// MARK: - Calendar Event Model

/// Maps a CuraKnot entity to an external calendar event
struct CalendarEvent: Codable, Identifiable, Equatable {
    let id: String
    let connectionId: String
    let circleId: String
    var patientId: String?

    // Source entity
    let sourceType: CalendarEventSourceType
    var sourceTaskId: String?
    var sourceShiftId: String?
    var sourceBinderItemId: String?
    var sourceHandoffId: String?

    // External calendar reference
    var externalEventId: String
    var externalCalendarId: String?
    var externalEtag: String?
    var externalIcalUid: String?

    // Event data
    var title: String
    var eventDescription: String?
    var startAt: Date
    var endAt: Date?
    var allDay: Bool
    var location: String?

    // Recurrence
    var recurrenceRule: String?
    var recurrenceId: String?

    // Sync state
    var syncStatus: CalendarSyncStatus
    var syncError: String?

    // SECURITY: HMAC checksum for integrity verification
    // Computed on write, verified on read to detect tampering
    var dataChecksum: String?

    // Conflict data (SECURITY: Stored encrypted via conflictDataEncrypted)
    var conflictDataJson: String?
    var conflictDetectedAt: Date?
    var conflictResolvedAt: Date?
    var conflictResolution: String?

    // Timestamps
    var lastSyncedAt: Date?
    var localUpdatedAt: Date
    var externalUpdatedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var sourceId: String? {
        switch sourceType {
        case .task: return sourceTaskId
        case .shift: return sourceShiftId
        case .appointment: return sourceBinderItemId
        case .handoffFollowup: return sourceHandoffId
        }
    }

    var hasConflict: Bool {
        syncStatus == .conflict
    }

    var needsSync: Bool {
        syncStatus == .pendingPush || syncStatus == .pendingPull
    }

    var duration: TimeInterval? {
        guard let endAt = endAt else { return nil }
        return endAt.timeIntervalSince(startAt)
    }

    var formattedTimeRange: String {
        let formatter = DateFormatter()

        if allDay {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: startAt)
        }

        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let startStr = formatter.string(from: startAt)
        if let endAt = endAt {
            let endStr = formatter.string(from: endAt)
            return "\(startStr) - \(endStr)"
        }
        return startStr
    }

    /// Get decrypted conflict data (SECURITY: Conflict data is encrypted at rest)
    var conflictData: CalendarEventConflict? {
        guard let encrypted = conflictDataJson else { return nil }

        // Try to decrypt first (new encrypted format)
        if let decrypted = CalendarSecurityManager.shared.decryptConflictData(encrypted),
           let data = decrypted.data(using: .utf8) {
            return try? JSONDecoder().decode(CalendarEventConflict.self, from: data)
        }

        // Fallback: try parsing as unencrypted JSON (legacy data)
        if let data = encrypted.data(using: .utf8) {
            return try? JSONDecoder().decode(CalendarEventConflict.self, from: data)
        }

        return nil
    }

    /// Set conflict data with encryption (SECURITY: Encrypts PHI before storage)
    mutating func setConflictData(_ conflict: CalendarEventConflict?) {
        guard let conflict = conflict else {
            conflictDataJson = nil
            return
        }

        guard let jsonData = try? JSONEncoder().encode(conflict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        // Encrypt before storing
        conflictDataJson = CalendarSecurityManager.shared.encryptConflictData(jsonString) ?? jsonString
    }

    /// Compute and update the data checksum (SECURITY: Call before persisting)
    mutating func updateChecksum() {
        dataChecksum = CalendarSecurityManager.shared.computeChecksum(for: self)
    }

    /// Verify data integrity (SECURITY: Call after reading from storage)
    func verifyIntegrity() -> Bool {
        return CalendarSecurityManager.shared.verifyChecksum(for: self, expectedChecksum: dataChecksum)
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        connectionId: String,
        circleId: String,
        patientId: String? = nil,
        sourceType: CalendarEventSourceType,
        sourceTaskId: String? = nil,
        sourceShiftId: String? = nil,
        sourceBinderItemId: String? = nil,
        sourceHandoffId: String? = nil,
        externalEventId: String,
        externalCalendarId: String? = nil,
        externalEtag: String? = nil,
        externalIcalUid: String? = nil,
        title: String,
        eventDescription: String? = nil,
        startAt: Date,
        endAt: Date? = nil,
        allDay: Bool = false,
        location: String? = nil,
        recurrenceRule: String? = nil,
        recurrenceId: String? = nil,
        syncStatus: CalendarSyncStatus = .synced,
        syncError: String? = nil,
        dataChecksum: String? = nil,
        conflictDataJson: String? = nil,
        conflictDetectedAt: Date? = nil,
        conflictResolvedAt: Date? = nil,
        conflictResolution: String? = nil,
        lastSyncedAt: Date? = nil,
        localUpdatedAt: Date = Date(),
        externalUpdatedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.connectionId = connectionId
        self.circleId = circleId
        self.patientId = patientId
        self.sourceType = sourceType
        self.sourceTaskId = sourceTaskId
        self.sourceShiftId = sourceShiftId
        self.sourceBinderItemId = sourceBinderItemId
        self.sourceHandoffId = sourceHandoffId
        self.externalEventId = externalEventId
        self.externalCalendarId = externalCalendarId
        self.externalEtag = externalEtag
        self.externalIcalUid = externalIcalUid
        self.title = title
        self.eventDescription = eventDescription
        self.startAt = startAt
        self.endAt = endAt
        self.allDay = allDay
        self.location = location
        self.recurrenceRule = recurrenceRule
        self.recurrenceId = recurrenceId
        self.syncStatus = syncStatus
        self.syncError = syncError
        self.dataChecksum = dataChecksum
        self.conflictDataJson = conflictDataJson
        self.conflictDetectedAt = conflictDetectedAt
        self.conflictResolvedAt = conflictResolvedAt
        self.conflictResolution = conflictResolution
        self.lastSyncedAt = lastSyncedAt
        self.localUpdatedAt = localUpdatedAt
        self.externalUpdatedAt = externalUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Factory Methods

    /// Creates a calendar event from a task
    static func fromTask(
        _ task: CareTask,
        connectionId: String,
        circleId: String,
        externalEventId: String,
        showMinimalDetails: Bool = false
    ) -> CalendarEvent? {
        guard let dueAt = task.dueAt else { return nil }

        let title = showMinimalDetails
            ? "CuraKnot Event"
            : "\(CalendarEventSourceType.task.titlePrefix) \(task.title)"

        let endAt = dueAt.addingTimeInterval(30 * 60) // 30 minute duration

        return CalendarEvent(
            connectionId: connectionId,
            circleId: circleId,
            patientId: task.patientId,
            sourceType: .task,
            sourceTaskId: task.id,
            externalEventId: externalEventId,
            title: title,
            eventDescription: showMinimalDetails ? nil : task.description,
            startAt: dueAt,
            endAt: endAt,
            allDay: false,
            syncStatus: .pendingPush,
            localUpdatedAt: task.updatedAt
        )
    }
}

// MARK: - CalendarEventChecksumData Conformance

extension CalendarEvent: CalendarEventChecksumData {
    var description: String? { eventDescription }
}

// MARK: - GRDB Conformance

extension CalendarEvent: FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_events"

    // CodingKeys for snake_case database column mapping
    enum CodingKeys: String, CodingKey {
        case id
        case connectionId = "connection_id"
        case circleId = "circle_id"
        case patientId = "patient_id"
        case sourceType = "source_type"
        case sourceTaskId = "source_task_id"
        case sourceShiftId = "source_shift_id"
        case sourceBinderItemId = "source_binder_item_id"
        case sourceHandoffId = "source_handoff_id"
        case externalEventId = "external_event_id"
        case externalCalendarId = "external_calendar_id"
        case externalEtag = "external_etag"
        case externalIcalUid = "external_ical_uid"
        case title
        case eventDescription = "description"
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case location
        case recurrenceRule = "recurrence_rule"
        case recurrenceId = "recurrence_id"
        case syncStatus = "sync_status"
        case syncError = "sync_error"
        case dataChecksum = "data_checksum"
        case conflictDataJson = "conflict_data_json"
        case conflictDetectedAt = "conflict_detected_at"
        case conflictResolvedAt = "conflict_resolved_at"
        case conflictResolution = "conflict_resolution"
        case lastSyncedAt = "last_synced_at"
        case localUpdatedAt = "local_updated_at"
        case externalUpdatedAt = "external_updated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Column references for GRDB queries
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let connectionId = Column(CodingKeys.connectionId)
        static let circleId = Column(CodingKeys.circleId)
        static let patientId = Column(CodingKeys.patientId)
        static let sourceType = Column(CodingKeys.sourceType)
        static let sourceTaskId = Column(CodingKeys.sourceTaskId)
        static let sourceShiftId = Column(CodingKeys.sourceShiftId)
        static let sourceBinderItemId = Column(CodingKeys.sourceBinderItemId)
        static let sourceHandoffId = Column(CodingKeys.sourceHandoffId)
        static let externalEventId = Column(CodingKeys.externalEventId)
        static let externalCalendarId = Column(CodingKeys.externalCalendarId)
        static let externalEtag = Column(CodingKeys.externalEtag)
        static let externalIcalUid = Column(CodingKeys.externalIcalUid)
        static let title = Column(CodingKeys.title)
        static let eventDescription = Column(CodingKeys.eventDescription)
        static let startAt = Column(CodingKeys.startAt)
        static let endAt = Column(CodingKeys.endAt)
        static let allDay = Column(CodingKeys.allDay)
        static let location = Column(CodingKeys.location)
        static let recurrenceRule = Column(CodingKeys.recurrenceRule)
        static let recurrenceId = Column(CodingKeys.recurrenceId)
        static let syncStatus = Column(CodingKeys.syncStatus)
        static let syncError = Column(CodingKeys.syncError)
        static let dataChecksum = Column(CodingKeys.dataChecksum)
        static let conflictDataJson = Column(CodingKeys.conflictDataJson)
        static let conflictDetectedAt = Column(CodingKeys.conflictDetectedAt)
        static let conflictResolvedAt = Column(CodingKeys.conflictResolvedAt)
        static let conflictResolution = Column(CodingKeys.conflictResolution)
        static let lastSyncedAt = Column(CodingKeys.lastSyncedAt)
        static let localUpdatedAt = Column(CodingKeys.localUpdatedAt)
        static let externalUpdatedAt = Column(CodingKeys.externalUpdatedAt)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Conflict Data

/// Stores both versions of an event during a conflict
struct CalendarEventConflict: Codable {
    let localVersion: CalendarEventSnapshot
    let externalVersion: CalendarEventSnapshot
    let detectedAt: Date
    let fieldConflicts: [String]  // Names of conflicting fields

    struct CalendarEventSnapshot: Codable {
        let title: String
        let description: String?
        let startAt: Date
        let endAt: Date?
        let allDay: Bool
        let location: String?
        let updatedAt: Date
    }
}
