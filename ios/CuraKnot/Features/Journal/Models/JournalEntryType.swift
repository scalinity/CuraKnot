import Foundation

/// Type of journal entry
enum JournalEntryType: String, Codable, CaseIterable, Identifiable {
    /// Quick gratitude or positive moment entry
    case goodMoment = "GOOD_MOMENT"

    /// Significant milestone in the care journey
    case milestone = "MILESTONE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .goodMoment: return "Good Moment"
        case .milestone: return "Milestone"
        }
    }

    var description: String {
        switch self {
        case .goodMoment:
            return "Capture something that made you smile"
        case .milestone:
            return "Mark a significant moment in your journey"
        }
    }

    var icon: String {
        switch self {
        case .goodMoment: return "face.smiling"
        case .milestone: return "flag.fill"
        }
    }

    var promptPlaceholder: String {
        switch self {
        case .goodMoment:
            return "What made you smile today?"
        case .milestone:
            return "What does this milestone mean to you?"
        }
    }
}
