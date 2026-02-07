import Foundation
import EventKit
import Combine

// MARK: - Calendar Settings View Model

@MainActor
final class CalendarSettingsViewModel: ObservableObject {
    // MARK: - Dependencies

    private let calendarSyncService: CalendarSyncService
    private let appleProvider: AppleCalendarProvider
    private var circleId: String
    private var userId: String

    // MARK: - Published State

    @Published var connections: [CalendarConnection] = []
    @Published var accessLevel: CalendarAccessLevel = .none
    @Published var isSyncing: Bool = false
    @Published var isLoading: Bool = true
    @Published var lastSyncFormatted: String = "Never"
    @Published var error: Error?

    // Settings
    @Published var syncTasks: Bool = true
    @Published var syncShifts: Bool = true
    @Published var syncAppointments: Bool = true
    @Published var conflictStrategy: ConflictStrategy = .curaknotWins

    // Sheet states
    @Published var showAddCalendar: Bool = false
    @Published var showConflictResolution: Bool = false
    @Published var showICalFeed: Bool = false

    // Apple Calendar
    @Published var availableCalendars: [EKCalendar] = []
    @Published var selectedCalendarId: String?
    @Published var calendarAuthStatus: EKAuthorizationStatus = .notDetermined

    // Conflicts
    @Published var pendingConflicts: [CalendarEvent] = []

    // MARK: - Computed Properties

    var canAddConnection: Bool {
        guard accessLevel.canSync else { return false }

        // Check if user already has maximum connections for their tier
        switch accessLevel {
        case .singleProvider:
            // PLUS: Only Apple Calendar
            return !connections.contains { $0.provider == .apple }
        case .multiProvider:
            // FAMILY: All providers
            return connections.count < 3
        default:
            return false
        }
    }

    var availableProviders: [CalendarProvider] {
        switch accessLevel {
        case .singleProvider:
            return [.apple]
        case .multiProvider:
            return CalendarProvider.allCases
        default:
            return []
        }
    }

    var hasActiveConnection: Bool {
        connections.contains { $0.status == .active }
    }

    var hasConflicts: Bool {
        !pendingConflicts.isEmpty
    }

    // MARK: - Initialization

    init(
        calendarSyncService: CalendarSyncService,
        appleProvider: AppleCalendarProvider,
        circleId: String,
        userId: String
    ) {
        self.calendarSyncService = calendarSyncService
        self.appleProvider = appleProvider
        self.circleId = circleId
        self.userId = userId

        setupBindings()
    }

    private func setupBindings() {
        // Bind to sync service state
        calendarSyncService.$connections
            .receive(on: DispatchQueue.main)
            .assign(to: &$connections)

        calendarSyncService.$accessLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$accessLevel)

        calendarSyncService.$isSyncing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSyncing)

        calendarSyncService.$pendingConflicts
            .receive(on: DispatchQueue.main)
            .assign(to: &$pendingConflicts)

        appleProvider.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$calendarAuthStatus)
    }

    // MARK: - Configuration

    /// Updates the circle and user IDs from AppState
    /// Must be called before load() when IDs change
    func configure(circleId: String, userId: String) {
        guard !circleId.isEmpty, !userId.isEmpty else {
            return
        }
        self.circleId = circleId
        self.userId = userId
    }

    // MARK: - Loading

    func load() async {
        // Guard against empty IDs - calendar operations will fail without them
        guard !circleId.isEmpty, !userId.isEmpty else {
            error = CalendarError.invalidConfiguration
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        do {
            // Check access level
            await calendarSyncService.checkAccessLevel(circleId: circleId, userId: userId)

            // Load connections
            try await calendarSyncService.loadConnections(circleId: circleId)

            // Update last sync time
            updateLastSyncTime()

            // Load available calendars if authorized
            if appleProvider.isAuthorized {
                availableCalendars = appleProvider.getWritableCalendars()
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Calendar Connection

    func requestCalendarAccess() async {
        do {
            let granted = try await appleProvider.requestAccess()
            if granted {
                availableCalendars = appleProvider.getWritableCalendars()

                // Auto-select default calendar
                if let defaultCalendar = appleProvider.getDefaultCalendar() {
                    selectedCalendarId = defaultCalendar.calendarIdentifier
                }
            }
        } catch {
            self.error = error
        }
    }

    func connectAppleCalendar() async {
        guard let calendarId = selectedCalendarId,
              !userId.isEmpty,
              !circleId.isEmpty,
              let calendar = appleProvider.getCalendar(identifier: calendarId) else {
            error = CalendarError.notAuthorized
            return
        }

        do {
            _ = try await calendarSyncService.connectAppleCalendar(
                circleId: circleId,
                userId: userId,
                calendarId: calendarId,
                calendarTitle: calendar.title
            )
            showAddCalendar = false
        } catch {
            self.error = error
        }
    }

    func disconnectCalendar(_ connection: CalendarConnection) async {
        do {
            try await calendarSyncService.disconnectProvider(connectionId: connection.id)
        } catch {
            self.error = error
        }
    }

    // MARK: - Sync

    func syncNow() async {
        do {
            await calendarSyncService.syncAll(circleId: circleId)
            updateLastSyncTime()
        } catch {
            self.error = error
        }
    }

    func syncConnection(_ connection: CalendarConnection) async {
        do {
            try await calendarSyncService.syncConnection(connection)
            updateLastSyncTime()
        } catch {
            self.error = error
        }
    }

    private func updateLastSyncTime() {
        if let mostRecent = connections.compactMap({ $0.lastSyncAt }).max() {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            lastSyncFormatted = formatter.localizedString(for: mostRecent, relativeTo: Date())
        } else {
            lastSyncFormatted = "Never"
        }
    }

    // MARK: - Settings

    func updateSettings(for connection: CalendarConnection) async {
        var updated = connection
        updated.syncTasks = syncTasks
        updated.syncShifts = syncShifts
        updated.syncAppointments = syncAppointments
        updated.conflictStrategy = conflictStrategy

        do {
            try await calendarSyncService.updateConnection(updated)
        } catch {
            self.error = error
        }
    }

    // MARK: - Conflict Resolution

    func resolveConflict(_ event: CalendarEvent, resolution: CalendarConflictResolution) async {
        do {
            try await calendarSyncService.resolveConflict(eventId: event.id, resolution: resolution)
        } catch {
            self.error = error
        }
    }

    // MARK: - Apple Provider Access

    var appleProviderAuthStatus: Bool {
        appleProvider.isAuthorized
    }
}
