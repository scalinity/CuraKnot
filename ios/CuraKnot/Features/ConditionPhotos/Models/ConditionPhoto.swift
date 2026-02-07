import Foundation

// MARK: - Condition Photo

struct ConditionPhoto: Identifiable, Codable {
    let id: UUID
    let conditionId: UUID
    let circleId: UUID
    let patientId: UUID
    let createdBy: String
    let storageKey: String
    let thumbnailKey: String
    var capturedAt: Date
    var notes: String?
    var annotationsJson: [PhotoAnnotation]?
    var lightingQuality: LightingQuality?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conditionId = "condition_id"
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case storageKey = "storage_key"
        case thumbnailKey = "thumbnail_key"
        case capturedAt = "captured_at"
        case notes
        case annotationsJson = "annotations_json"
        case lightingQuality = "lighting_quality"
        case createdAt = "created_at"
    }
}

// MARK: - Lighting Quality

enum LightingQuality: String, Codable, CaseIterable {
    case good = "GOOD"
    case fair = "FAIR"
    case poor = "POOR"

    var displayName: String {
        switch self {
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    var icon: String {
        switch self {
        case .good: return "sun.max"
        case .fair: return "sun.haze"
        case .poor: return "moon"
        }
    }
}

// MARK: - Photo Annotation

struct PhotoAnnotation: Codable, Identifiable {
    let id: UUID
    let type: AnnotationType
    let points: [CGFloat]
    let color: String

    enum AnnotationType: String, Codable {
        case arrow
        case circle
    }

    init(id: UUID = UUID(), type: AnnotationType, points: [CGFloat], color: String = "red") {
        self.id = id
        self.type = type
        self.points = points
        self.color = color
    }
}
