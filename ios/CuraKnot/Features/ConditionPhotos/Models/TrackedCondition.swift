import Foundation

// MARK: - Tracked Condition

struct TrackedCondition: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let createdBy: String
    var conditionType: ConditionType
    var bodyLocation: String
    var description: String?
    var startDate: Date
    var status: ConditionStatus
    var resolvedDate: Date?
    var resolutionNotes: String?
    let requireBiometric: Bool
    let blurThumbnails: Bool
    let createdAt: Date
    var updatedAt: Date

    /// Transient: photo count from join query
    var photoCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case conditionType = "condition_type"
        case bodyLocation = "body_location"
        case description
        case startDate = "start_date"
        case status
        case resolvedDate = "resolved_date"
        case resolutionNotes = "resolution_notes"
        case requireBiometric = "require_biometric"
        case blurThumbnails = "blur_thumbnails"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case photoCount = "photo_count"
    }

    var isActive: Bool { status == .active }
    var daysSinceStart: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }
}

// MARK: - Condition Type

enum ConditionType: String, Codable, CaseIterable, Identifiable {
    case wound = "WOUND"
    case rash = "RASH"
    case swelling = "SWELLING"
    case bruise = "BRUISE"
    case surgical = "SURGICAL"
    case other = "OTHER"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wound: return "Wound/Incision"
        case .rash: return "Rash"
        case .swelling: return "Swelling"
        case .bruise: return "Bruise"
        case .surgical: return "Surgical Site"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .wound: return "bandage"
        case .rash: return "allergens"
        case .swelling: return "circle.dashed"
        case .bruise: return "circle.hexagongrid"
        case .surgical: return "cross.case"
        case .other: return "questionmark.circle"
        }
    }
}

// MARK: - Condition Status

enum ConditionStatus: String, Codable, CaseIterable {
    case active = "ACTIVE"
    case resolved = "RESOLVED"
    case archived = "ARCHIVED"

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .resolved: return "Resolved"
        case .archived: return "Archived"
        }
    }

    var color: String {
        switch self {
        case .active: return "blue"
        case .resolved: return "green"
        case .archived: return "gray"
        }
    }
}
