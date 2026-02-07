import Foundation
import EventKit
import Combine

// MARK: - Apple Calendar Provider

/// Provides integration with Apple Calendar via EventKit
@MainActor
final class AppleCalendarProvider: ObservableObject {
    // MARK: - Properties

    private let eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false

    private var changeObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        updateAuthorizationStatus()
        setupChangeObserver()
    }

    deinit {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Authorization

    /// Request full access to calendar events
    func requestAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                updateAuthorizationStatus()
            }
            return granted
        } else {
            let granted = try await eventStore.requestAccess(to: .event)
            await MainActor.run {
                updateAuthorizationStatus()
            }
            return granted
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    private func updateAuthorizationStatus() {
        authorizationStatus = checkAuthorizationStatus()
        if #available(iOS 17.0, *) {
            isAuthorized = authorizationStatus == .fullAccess
        } else {
            isAuthorized = authorizationStatus == .authorized
        }
    }

    // MARK: - Calendar Selection

    /// Get all writable calendars
    /// Returns empty array if not authorized (check isAuthorized first for error handling)
    func getWritableCalendars() -> [EKCalendar] {
        guard isAuthorized else {
            return []
        }
        return eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    /// Get the default calendar for new events
    func getDefaultCalendar() -> EKCalendar? {
        guard isAuthorized else { return nil }
        return eventStore.defaultCalendarForNewEvents
    }

    /// Get a calendar by its identifier
    func getCalendar(identifier: String) -> EKCalendar? {
        guard isAuthorized else { return nil }
        return eventStore.calendar(withIdentifier: identifier)
    }

    /// Create a new calendar for CuraKnot events
    func createCuraKnotCalendar(name: String) throws -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = name

        // Find a suitable source (prefer iCloud, then Local)
        if let iCloudSource = eventStore.sources.first(where: { $0.sourceType == .calDAV }) {
            calendar.source = iCloudSource
        } else if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let defaultSource = eventStore.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        } else {
            throw CalendarError.noCalendarSource
        }

        // Set a distinct color (purple for CuraKnot)
        calendar.cgColor = CGColor(red: 0.5, green: 0.0, blue: 0.8, alpha: 1.0)

        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    // MARK: - Event CRUD

    /// Create an event in the specified calendar
    func createEvent(from calendarEvent: CalendarEvent, in calendarId: String) throws -> String {
        guard let calendar = getCalendar(identifier: calendarId) else {
            throw CalendarError.calendarNotFound
        }

        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.calendar = calendar
        applyCalendarEventToEKEvent(calendarEvent, ekEvent: ekEvent)

        try eventStore.save(ekEvent, span: .thisEvent)

        return ekEvent.eventIdentifier
    }

    /// Update an existing event
    func updateEvent(eventIdentifier: String, with calendarEvent: CalendarEvent) throws {
        guard let ekEvent = eventStore.event(withIdentifier: eventIdentifier) else {
            throw CalendarError.eventNotFound
        }

        applyCalendarEventToEKEvent(calendarEvent, ekEvent: ekEvent)

        try eventStore.save(ekEvent, span: .thisEvent)
    }

    /// Delete an event
    func deleteEvent(eventIdentifier: String) throws {
        guard let ekEvent = eventStore.event(withIdentifier: eventIdentifier) else {
            // Event already deleted, not an error
            return
        }

        try eventStore.remove(ekEvent, span: .thisEvent)
    }

    /// Fetch an event by identifier
    func fetchEvent(eventIdentifier: String) -> EKEvent? {
        eventStore.event(withIdentifier: eventIdentifier)
    }

    // MARK: - Sync Operations

    /// Fetch events that have changed since the given date
    func fetchChangedEvents(since date: Date, calendarId: String) -> [EKEvent] {
        guard let calendar = getCalendar(identifier: calendarId) else {
            return []
        }

        let endDate = Date().addingTimeInterval(90 * 24 * 60 * 60) // 90 days ahead
        let predicate = eventStore.predicateForEvents(
            withStart: date,
            end: endDate,
            calendars: [calendar]
        )

        return eventStore.events(matching: predicate)
    }

    /// Fetch all events in a date range for a calendar
    func fetchEvents(from startDate: Date, to endDate: Date, calendarId: String) -> [EKEvent] {
        guard let calendar = getCalendar(identifier: calendarId) else {
            return []
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: [calendar]
        )

        return eventStore.events(matching: predicate)
    }

    /// Fetch events with CuraKnot prefix in title
    func fetchCuraKnotEvents(in calendarId: String, since date: Date) -> [EKEvent] {
        let events = fetchChangedEvents(since: date, calendarId: calendarId)
        return events.filter { event in
            CalendarEventSourceType.allCases.contains { sourceType in
                event.title?.hasPrefix(sourceType.titlePrefix) == true
            }
        }
    }

    // MARK: - Change Observation

    private func setupChangeObserver() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleStoreChanged()
            }
        }
    }

    private func handleStoreChanged() {
        // Post notification for sync coordinator to pick up
        NotificationCenter.default.post(
            name: .appleCalendarDidChange,
            object: nil
        )
    }

    // MARK: - Conversion Helpers

    /// Apply CalendarEvent data to an EKEvent
    /// SECURITY: Does NOT embed internal CuraKnot IDs in external calendar events
    /// Reverse lookup is done via externalEventId stored in CalendarEvent table
    private func applyCalendarEventToEKEvent(_ calendarEvent: CalendarEvent, ekEvent: EKEvent) {
        ekEvent.title = calendarEvent.title
        // SECURITY: Only include description, never internal IDs
        ekEvent.notes = calendarEvent.eventDescription
        ekEvent.startDate = calendarEvent.startAt
        ekEvent.endDate = calendarEvent.endAt ?? calendarEvent.startAt.addingTimeInterval(30 * 60)
        ekEvent.isAllDay = calendarEvent.allDay
        ekEvent.location = calendarEvent.location

        // SECURITY: Do NOT embed internal CuraKnot IDs in external calendars
        // This prevents data correlation attacks and ID leakage to third-party services
        // Reverse lookup is maintained via CalendarEvent.externalEventId mapping

        // Handle recurrence if present
        if let rrule = calendarEvent.recurrenceRule {
            // Parse RRULE string and create EKRecurrenceRule
            if let recurrenceRule = parseRecurrenceRule(rrule) {
                ekEvent.recurrenceRules = [recurrenceRule]
            } else {
                // Log recurrence parsing failure for debugging
                #if DEBUG
                print("Warning: Failed to parse recurrence rule: \(rrule)")
                #endif
            }
        }
    }

    /// Convert an EKEvent to a CalendarEvent
    /// Note: Source ID lookup is done via database using externalEventId, not from notes
    func toCalendarEvent(
        _ ekEvent: EKEvent,
        connectionId: String,
        circleId: String,
        patientId: String? = nil
    ) -> CalendarEvent {
        // Try to detect source type from title prefix
        let sourceType: CalendarEventSourceType = {
            for type in CalendarEventSourceType.allCases {
                if ekEvent.title?.hasPrefix(type.titlePrefix) == true {
                    return type
                }
            }
            return .appointment // Default
        }()

        // SECURITY: Source IDs are NOT extracted from notes (we don't embed them)
        // Instead, lookup existing CalendarEvent by externalEventId to get source IDs
        // This is handled by the sync service, not here

        return CalendarEvent(
            connectionId: connectionId,
            circleId: circleId,
            patientId: patientId,
            sourceType: sourceType,
            // Source IDs are populated by sync service via database lookup using externalEventId
            sourceTaskId: nil,
            sourceShiftId: nil,
            sourceBinderItemId: nil,
            sourceHandoffId: nil,
            externalEventId: ekEvent.eventIdentifier,
            externalCalendarId: ekEvent.calendar?.calendarIdentifier,
            title: ekEvent.title ?? "Untitled Event",
            eventDescription: ekEvent.notes,
            startAt: ekEvent.startDate,
            endAt: ekEvent.endDate,
            allDay: ekEvent.isAllDay,
            location: ekEvent.location,
            syncStatus: .synced,
            localUpdatedAt: ekEvent.lastModifiedDate ?? Date(),
            externalUpdatedAt: ekEvent.lastModifiedDate
        )
    }

    /// Parse a simplified RRULE string
    private func parseRecurrenceRule(_ rrule: String) -> EKRecurrenceRule? {
        // Basic RRULE parsing - supports FREQ=DAILY|WEEKLY|MONTHLY|YEARLY
        guard rrule.hasPrefix("RRULE:") || rrule.contains("FREQ=") else {
            return nil
        }

        let cleanRule = rrule.replacingOccurrences(of: "RRULE:", with: "")
        let components = cleanRule.split(separator: ";").reduce(into: [String: String]()) { dict, part in
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                dict[String(kv[0])] = String(kv[1])
            }
        }

        guard let freqString = components["FREQ"] else {
            return nil
        }

        let frequency: EKRecurrenceFrequency
        switch freqString {
        case "DAILY": frequency = .daily
        case "WEEKLY": frequency = .weekly
        case "MONTHLY": frequency = .monthly
        case "YEARLY": frequency = .yearly
        default: return nil
        }

        let interval = Int(components["INTERVAL"] ?? "1") ?? 1

        var end: EKRecurrenceEnd? = nil
        if let countString = components["COUNT"], let count = Int(countString) {
            end = EKRecurrenceEnd(occurrenceCount: count)
        } else if let untilString = components["UNTIL"] {
            // Parse UNTIL date (basic format: YYYYMMDD or YYYYMMDDTHHMMSSZ)
            let formatter = DateFormatter()
            formatter.dateFormat = untilString.contains("T") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let untilDate = formatter.date(from: untilString) {
                end = EKRecurrenceEnd(end: untilDate)
            }
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            end: end
        )
    }
}

// MARK: - Calendar Errors

enum CalendarError: LocalizedError {
    case notAuthorized
    case calendarNotFound
    case eventNotFound
    case noCalendarSource
    case saveFailed(String)
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized. Please enable in Settings."
        case .calendarNotFound:
            return "The selected calendar was not found."
        case .eventNotFound:
            return "The event was not found."
        case .noCalendarSource:
            return "No suitable calendar source available."
        case .saveFailed(let message):
            return "Failed to save: \(message)"
        case .invalidConfiguration:
            return "Calendar settings could not be loaded. Please try again."
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appleCalendarDidChange = Notification.Name("appleCalendarDidChange")
}

// MARK: - Source Type Extension

extension CalendarEventSourceType: CaseIterable {
    static var allCases: [CalendarEventSourceType] {
        [.task, .shift, .appointment, .handoffFollowup]
    }
}
