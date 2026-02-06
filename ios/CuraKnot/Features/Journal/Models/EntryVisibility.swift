import Foundation

/// Privacy level for journal entries
enum EntryVisibility: String, Codable, CaseIterable, Identifiable {
    /// Only the author can see this entry
    case `private` = "PRIVATE"

    /// All active circle members can see this entry
    case circle = "CIRCLE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .private: return "Just me"
        case .circle: return "Share with circle"
        }
    }

    var description: String {
        switch self {
        case .private:
            return "Only you can see this entry"
        case .circle:
            return "Everyone in your care circle can see this"
        }
    }

    var icon: String {
        switch self {
        case .private: return "lock.fill"
        case .circle: return "person.2.fill"
        }
    }
}
