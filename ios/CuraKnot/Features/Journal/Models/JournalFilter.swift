import Foundation

/// Filter criteria for journal entries
struct JournalFilter: Equatable {
    /// Filter by entry type
    var entryType: JournalEntryType?

    /// Filter by patient
    var patientId: String?

    /// Filter by date range start
    var startDate: Date?

    /// Filter by date range end
    var endDate: Date?

    /// Show only private entries
    var privateOnly: Bool = false

    /// Show only author's own entries
    var myEntriesOnly: Bool = false

    /// Default filter showing all entries
    static let all = JournalFilter()

    /// Check if any filter is active
    var isActive: Bool {
        entryType != nil ||
        patientId != nil ||
        startDate != nil ||
        endDate != nil ||
        privateOnly ||
        myEntriesOnly
    }

    /// Clear all filters
    mutating func reset() {
        entryType = nil
        patientId = nil
        startDate = nil
        endDate = nil
        privateOnly = false
        myEntriesOnly = false
    }

    /// Check if filters are equal
    static func == (lhs: JournalFilter, rhs: JournalFilter) -> Bool {
        lhs.entryType == rhs.entryType &&
        lhs.patientId == rhs.patientId &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.privateOnly == rhs.privateOnly &&
        lhs.myEntriesOnly == rhs.myEntriesOnly
    }
}

/// Filter preset options
enum JournalFilterPreset: String, CaseIterable, Identifiable {
    case all = "all"
    case goodMoments = "good_moments"
    case milestones = "milestones"
    case myEntries = "my_entries"
    case privateOnly = "private_only"
    case thisWeek = "this_week"
    case thisMonth = "this_month"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All Entries"
        case .goodMoments: return "Good Moments"
        case .milestones: return "Milestones"
        case .myEntries: return "My Entries"
        case .privateOnly: return "Private Only"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        }
    }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .goodMoments: return "face.smiling"
        case .milestones: return "flag.fill"
        case .myEntries: return "person.fill"
        case .privateOnly: return "lock.fill"
        case .thisWeek: return "calendar"
        case .thisMonth: return "calendar.badge.clock"
        }
    }

    func toFilter() -> JournalFilter {
        var filter = JournalFilter()

        switch self {
        case .all:
            break
        case .goodMoments:
            filter.entryType = JournalEntryType.goodMoment
        case .milestones:
            filter.entryType = JournalEntryType.milestone
        case .myEntries:
            filter.myEntriesOnly = true
        case .privateOnly:
            filter.privateOnly = true
        case .thisWeek:
            filter.startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .thisMonth:
            filter.startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())
        }

        return filter
    }
}
