import Foundation
import GRDB

// MARK: - Calendar Connection Model

/// Represents a connection to an external calendar provider
struct CalendarConnection: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let circleId: String
    let provider: CalendarProvider

    // Connection status
    var status: CalendarConnectionStatus
    var statusMessage: String?

    // Apple Calendar specific (EventKit)
    var appleCalendarId: String?
    var appleCalendarTitle: String?

    // OAuth providers (Google/Outlook)
    var calendarId: String?
    var calendarTitle: String?

    // Sync configuration
    var syncDirection: SyncDirection
    var conflictStrategy: ConflictStrategy
    var syncIntervalMinutes: Int

    // Event type toggles
    var syncTasks: Bool
    var syncShifts: Bool
    var syncAppointments: Bool
    var syncHandoffFollowups: Bool

    // Privacy - SECURITY: Default to true to prevent PHI leakage to external calendars
    var showMinimalDetails: Bool

    // Sync state
    var lastSyncAt: Date?
    var lastSyncStatus: String?
    var lastSyncError: String?
    var eventsSyncedCount: Int

    // Timestamps
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var displayCalendarName: String {
        switch provider {
        case .apple:
            return appleCalendarTitle ?? "Apple Calendar"
        case .google, .outlook:
            return calendarTitle ?? provider.displayName
        }
    }

    var isConnected: Bool {
        status == .active
    }

    var needsReauth: Bool {
        status == .error || status == .revoked
    }

    var lastSyncFormatted: String {
        guard let lastSyncAt = lastSyncAt else {
            return "Never"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSyncAt, relativeTo: Date())
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        userId: String,
        circleId: String,
        provider: CalendarProvider,
        status: CalendarConnectionStatus = .pending,
        statusMessage: String? = nil,
        appleCalendarId: String? = nil,
        appleCalendarTitle: String? = nil,
        calendarId: String? = nil,
        calendarTitle: String? = nil,
        syncDirection: SyncDirection = .bidirectional,
        conflictStrategy: ConflictStrategy = .curaknotWins,
        syncIntervalMinutes: Int = 15,
        syncTasks: Bool = true,
        syncShifts: Bool = true,
        syncAppointments: Bool = true,
        syncHandoffFollowups: Bool = false,
        showMinimalDetails: Bool = true,  // SECURITY: Default true to protect PHI
        lastSyncAt: Date? = nil,
        lastSyncStatus: String? = nil,
        lastSyncError: String? = nil,
        eventsSyncedCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.circleId = circleId
        self.provider = provider
        self.status = status
        self.statusMessage = statusMessage
        self.appleCalendarId = appleCalendarId
        self.appleCalendarTitle = appleCalendarTitle
        self.calendarId = calendarId
        self.calendarTitle = calendarTitle
        self.syncDirection = syncDirection
        self.conflictStrategy = conflictStrategy
        self.syncIntervalMinutes = syncIntervalMinutes
        self.syncTasks = syncTasks
        self.syncShifts = syncShifts
        self.syncAppointments = syncAppointments
        self.syncHandoffFollowups = syncHandoffFollowups
        self.showMinimalDetails = showMinimalDetails
        self.lastSyncAt = lastSyncAt
        self.lastSyncStatus = lastSyncStatus
        self.lastSyncError = lastSyncError
        self.eventsSyncedCount = eventsSyncedCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Conformance

extension CalendarConnection: FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_connections"

    // CodingKeys for snake_case database column mapping
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case circleId = "circle_id"
        case provider
        case status
        case statusMessage = "status_message"
        case appleCalendarId = "apple_calendar_id"
        case appleCalendarTitle = "apple_calendar_title"
        case calendarId = "calendar_id"
        case calendarTitle = "calendar_title"
        case syncDirection = "sync_direction"
        case conflictStrategy = "conflict_strategy"
        case syncIntervalMinutes = "sync_interval_minutes"
        case syncTasks = "sync_tasks"
        case syncShifts = "sync_shifts"
        case syncAppointments = "sync_appointments"
        case syncHandoffFollowups = "sync_handoff_followups"
        case showMinimalDetails = "show_minimal_details"
        case lastSyncAt = "last_sync_at"
        case lastSyncStatus = "last_sync_status"
        case lastSyncError = "last_sync_error"
        case eventsSyncedCount = "events_synced_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Column references for GRDB queries
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let userId = Column(CodingKeys.userId)
        static let circleId = Column(CodingKeys.circleId)
        static let provider = Column(CodingKeys.provider)
        static let status = Column(CodingKeys.status)
        static let statusMessage = Column(CodingKeys.statusMessage)
        static let appleCalendarId = Column(CodingKeys.appleCalendarId)
        static let appleCalendarTitle = Column(CodingKeys.appleCalendarTitle)
        static let calendarId = Column(CodingKeys.calendarId)
        static let calendarTitle = Column(CodingKeys.calendarTitle)
        static let syncDirection = Column(CodingKeys.syncDirection)
        static let conflictStrategy = Column(CodingKeys.conflictStrategy)
        static let syncIntervalMinutes = Column(CodingKeys.syncIntervalMinutes)
        static let syncTasks = Column(CodingKeys.syncTasks)
        static let syncShifts = Column(CodingKeys.syncShifts)
        static let syncAppointments = Column(CodingKeys.syncAppointments)
        static let syncHandoffFollowups = Column(CodingKeys.syncHandoffFollowups)
        static let showMinimalDetails = Column(CodingKeys.showMinimalDetails)
        static let lastSyncAt = Column(CodingKeys.lastSyncAt)
        static let lastSyncStatus = Column(CodingKeys.lastSyncStatus)
        static let lastSyncError = Column(CodingKeys.lastSyncError)
        static let eventsSyncedCount = Column(CodingKeys.eventsSyncedCount)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Supabase Encoding

extension CalendarConnection {
    /// Creates a dictionary for Supabase insert/update
    func toSupabasePayload() -> [String: Any?] {
        [
            "id": id,
            "user_id": userId,
            "circle_id": circleId,
            "provider": provider.rawValue,
            "status": status.rawValue,
            "status_message": statusMessage,
            "apple_calendar_id": appleCalendarId,
            "apple_calendar_title": appleCalendarTitle,
            "calendar_id": calendarId,
            "calendar_title": calendarTitle,
            "sync_direction": syncDirection.rawValue,
            "conflict_strategy": conflictStrategy.rawValue,
            "sync_interval_minutes": syncIntervalMinutes,
            "sync_tasks": syncTasks,
            "sync_shifts": syncShifts,
            "sync_appointments": syncAppointments,
            "sync_handoff_followups": syncHandoffFollowups,
            "show_minimal_details": showMinimalDetails,
            "last_sync_at": lastSyncAt?.ISO8601Format(),
            "last_sync_status": lastSyncStatus,
            "last_sync_error": lastSyncError,
            "events_synced_count": eventsSyncedCount,
        ]
    }
}
