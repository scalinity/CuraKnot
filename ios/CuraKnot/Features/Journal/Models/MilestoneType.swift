import Foundation

/// Types of milestones in the caregiving journey
/// These represent significant markers worth celebrating
enum MilestoneType: String, Codable, CaseIterable, Identifiable {
    case anniversary = "ANNIVERSARY"
    case progress = "PROGRESS"
    case first = "FIRST"
    case achievement = "ACHIEVEMENT"
    case memory = "MEMORY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anniversary: return "Anniversary"
        case .progress: return "Progress"
        case .first: return "First Time"
        case .achievement: return "Achievement"
        case .memory: return "Memory"
        }
    }

    var description: String {
        switch self {
        case .anniversary:
            return "Marking a significant date in your care journey"
        case .progress:
            return "Celebrating improvement or positive change"
        case .first:
            return "A meaningful first-time moment"
        case .achievement:
            return "A goal reached or obstacle overcome"
        case .memory:
            return "A special moment worth remembering"
        }
    }

    var icon: String {
        switch self {
        case .anniversary: return "calendar.badge.clock"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .first: return "star.fill"
        case .achievement: return "trophy.fill"
        case .memory: return "heart.fill"
        }
    }

    var color: String {
        switch self {
        case .anniversary: return "purple"
        case .progress: return "green"
        case .first: return "yellow"
        case .achievement: return "orange"
        case .memory: return "pink"
        }
    }
}
