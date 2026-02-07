import Foundation
import GRDB

/// Status for a tracked concern
enum TrackedConcernStatus: String, Codable {
    case active = "ACTIVE"
    case paused = "PAUSED"
    case resolved = "RESOLVED"
}

/// A concern that the user has chosen to manually track
struct TrackedConcern: Codable, Identifiable, Equatable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let patternId: UUID?
    let createdBy: UUID
    let concernName: String
    let concernCategory: ConcernCategory?
    let trackingPrompt: String?
    var status: TrackedConcernStatus
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case patternId = "pattern_id"
        case createdBy = "created_by"
        case concernName = "concern_name"
        case concernCategory = "concern_category"
        case trackingPrompt = "tracking_prompt"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Default tracking prompt if none provided
    var displayPrompt: String {
        trackingPrompt ?? "How was \(concernName.lowercased()) today?"
    }

    /// Icon for the concern
    var icon: String {
        concernCategory?.icon ?? "chart.line.uptrend.xyaxis"
    }

    /// Color for the concern
    var color: Color {
        concernCategory?.color ?? .blue
    }
}

// MARK: - GRDB Conformance

extension TrackedConcern: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "tracked_concerns_cache" }

    init(row: Row) throws {
        id = row["id"]
        circleId = row["circle_id"]
        patientId = row["patient_id"]
        patternId = row["pattern_id"]
        createdBy = row["created_by"]
        concernName = row["concern_name"]
        concernCategory = (row["concern_category"] as String?).flatMap { ConcernCategory(rawValue: $0) }
        trackingPrompt = row["tracking_prompt"]
        status = TrackedConcernStatus(rawValue: row["status"]) ?? .active
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["circle_id"] = circleId
        container["patient_id"] = patientId
        container["pattern_id"] = patternId
        container["created_by"] = createdBy
        container["concern_name"] = concernName
        container["concern_category"] = concernCategory?.rawValue
        container["tracking_prompt"] = trackingPrompt
        container["status"] = status.rawValue
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }
}

import SwiftUI
