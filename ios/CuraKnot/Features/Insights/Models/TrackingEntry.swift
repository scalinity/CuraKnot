import Foundation
import GRDB

/// A daily tracking entry for a monitored concern
struct TrackingEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let concernId: UUID
    let recordedBy: UUID
    let rating: Int? // 1-5 scale: 1=much better, 5=much worse
    let notes: String?
    let handoffId: UUID?
    let recordedAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case concernId = "concern_id"
        case recordedBy = "recorded_by"
        case rating
        case notes
        case handoffId = "handoff_id"
        case recordedAt = "recorded_at"
        case createdAt = "created_at"
    }

    /// User-friendly rating description
    var ratingDescription: String? {
        guard let rating else { return nil }
        switch rating {
        case 1: return "Much better"
        case 2: return "Better"
        case 3: return "About the same"
        case 4: return "Worse"
        case 5: return "Much worse"
        default: return nil
        }
    }

    /// Rating color for UI
    var ratingColor: Color {
        guard let rating else { return .gray }
        switch rating {
        case 1, 2: return .green
        case 3: return .yellow
        case 4, 5: return .red
        default: return .gray
        }
    }
}

// MARK: - GRDB Conformance

extension TrackingEntry: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "tracking_entries_cache" }

    init(row: Row) throws {
        id = row["id"]
        concernId = row["concern_id"]
        recordedBy = row["recorded_by"]
        rating = row["rating"]
        notes = row["notes"]
        handoffId = row["handoff_id"]
        recordedAt = row["recorded_at"]
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["concern_id"] = concernId
        container["recorded_by"] = recordedBy
        container["rating"] = rating
        container["notes"] = notes
        container["handoff_id"] = handoffId
        container["recorded_at"] = recordedAt
        container["created_at"] = createdAt
    }
}

import SwiftUI
