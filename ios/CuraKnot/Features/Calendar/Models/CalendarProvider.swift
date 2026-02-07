import Foundation

// MARK: - Calendar Provider

/// Supported external calendar providers
enum CalendarProvider: String, Codable, CaseIterable, Identifiable {
    case apple = "APPLE"
    case google = "GOOGLE"
    case outlook = "OUTLOOK"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple Calendar"
        case .google: return "Google Calendar"
        case .outlook: return "Microsoft Outlook"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "calendar"
        case .google: return "g.circle.fill"
        case .outlook: return "envelope.fill"
        }
    }

    /// Whether this provider requires OAuth (vs native API like EventKit)
    var requiresOAuth: Bool {
        switch self {
        case .apple: return false
        case .google, .outlook: return true
        }
    }

    /// Minimum subscription tier required for this provider (FREE, PLUS, FAMILY)
    var minimumTier: String {
        switch self {
        case .apple: return "PLUS"
        case .google, .outlook: return "FAMILY"
        }
    }

    /// Check if provider is available for a given plan
    func isAvailable(for plan: String) -> Bool {
        switch self {
        case .apple:
            return plan == "PLUS" || plan == "FAMILY"
        case .google, .outlook:
            return plan == "FAMILY"
        }
    }
}

// MARK: - Sync Direction

/// Direction of calendar synchronization
enum SyncDirection: String, Codable, CaseIterable, Identifiable {
    case readOnly = "READ_ONLY"
    case writeOnly = "WRITE_ONLY"
    case bidirectional = "BIDIRECTIONAL"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .readOnly: return "Read Only"
        case .writeOnly: return "Write Only"
        case .bidirectional: return "Two-Way Sync"
        }
    }

    var description: String {
        switch self {
        case .readOnly:
            return "External calendar changes update CuraKnot"
        case .writeOnly:
            return "CuraKnot changes update external calendar"
        case .bidirectional:
            return "Changes sync both ways"
        }
    }
}

// MARK: - Conflict Strategy

/// Strategy for resolving sync conflicts
enum ConflictStrategy: String, Codable, CaseIterable, Identifiable {
    case curaknotWins = "CURAKNOT_WINS"
    case externalWins = "EXTERNAL_WINS"
    case manual = "MANUAL"
    case merge = "MERGE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curaknotWins: return "CuraKnot Wins"
        case .externalWins: return "Calendar Wins"
        case .manual: return "Ask Me"
        case .merge: return "Merge Changes"
        }
    }

    var description: String {
        switch self {
        case .curaknotWins:
            return "CuraKnot changes overwrite calendar changes"
        case .externalWins:
            return "Calendar changes overwrite CuraKnot changes"
        case .manual:
            return "Show conflicts for manual resolution"
        case .merge:
            return "Combine non-conflicting fields from both"
        }
    }
}

// MARK: - Connection Status

/// Status of a calendar connection
enum CalendarConnectionStatus: String, Codable {
    case pending = "PENDING"
    case active = "ACTIVE"
    case revoked = "REVOKED"
    case error = "ERROR"

    var displayName: String {
        switch self {
        case .pending: return "Connecting..."
        case .active: return "Connected"
        case .revoked: return "Disconnected"
        case .error: return "Error"
        }
    }

    var isHealthy: Bool {
        self == .active
    }
}

// MARK: - Sync Status

/// Status of a calendar event's sync state
enum CalendarSyncStatus: String, Codable {
    case synced = "SYNCED"
    case pendingPush = "PENDING_PUSH"
    case pendingPull = "PENDING_PULL"
    case conflict = "CONFLICT"
    case error = "ERROR"
    case deleted = "DELETED"

    var displayName: String {
        switch self {
        case .synced: return "Synced"
        case .pendingPush: return "Uploading..."
        case .pendingPull: return "Downloading..."
        case .conflict: return "Conflict"
        case .error: return "Error"
        case .deleted: return "Deleted"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .conflict, .error:
            return true
        default:
            return false
        }
    }
}

// MARK: - Calendar Event Source Type

/// Type of CuraKnot entity that generated a calendar event
enum CalendarEventSourceType: String, Codable {
    case task = "TASK"
    case shift = "SHIFT"
    case appointment = "APPOINTMENT"
    case handoffFollowup = "HANDOFF_FOLLOWUP"

    var displayName: String {
        switch self {
        case .task: return "Task"
        case .shift: return "Shift"
        case .appointment: return "Appointment"
        case .handoffFollowup: return "Follow-up"
        }
    }

    var icon: String {
        switch self {
        case .task: return "checklist"
        case .shift: return "clock.badge.checkmark"
        case .appointment: return "calendar.badge.clock"
        case .handoffFollowup: return "arrow.turn.right.up"
        }
    }

    /// Prefix used in calendar event titles
    var titlePrefix: String {
        switch self {
        case .task: return "CK:"
        case .shift: return "CK Shift:"
        case .appointment: return "CK Appt:"
        case .handoffFollowup: return "CK Follow-up:"
        }
    }
}

// MARK: - Calendar Access Level

/// User's calendar access level based on subscription tier
enum CalendarAccessLevel: Comparable {
    case none
    case readOnly
    case singleProvider  // PLUS tier - Apple only
    case multiProvider   // FAMILY tier - all providers

    var canSync: Bool {
        self >= .singleProvider
    }

    var canUseAppleCalendar: Bool {
        self >= .singleProvider
    }

    var canUseGoogleCalendar: Bool {
        self >= .multiProvider
    }

    var canUseOutlookCalendar: Bool {
        self >= .multiProvider
    }

    var canGenerateICalFeed: Bool {
        self >= .singleProvider
    }
}
