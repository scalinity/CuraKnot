import Foundation
import GRDB

/// A detected symptom pattern from handoff analysis
struct DetectedPattern: Codable, Identifiable, Equatable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let concernCategory: ConcernCategory
    let concernKeywords: [String]
    let patternType: PatternType
    let patternHash: String
    let mentionCount: Int
    let firstMentionAt: Date
    let lastMentionAt: Date
    let trend: TrendDirection?
    let correlatedEvents: [CorrelatedEvent]?
    var status: PatternStatus
    let dismissedBy: UUID?
    let dismissedAt: Date?
    let sourceHandoffIds: [UUID]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case concernCategory = "concern_category"
        case concernKeywords = "concern_keywords"
        case patternType = "pattern_type"
        case patternHash = "pattern_hash"
        case mentionCount = "mention_count"
        case firstMentionAt = "first_mention_at"
        case lastMentionAt = "last_mention_at"
        case trend
        case correlatedEvents = "correlated_events"
        case status
        case dismissedBy = "dismissed_by"
        case dismissedAt = "dismissed_at"
        case sourceHandoffIds = "source_handoff_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    /// Icon for the concern category
    var icon: String {
        concernCategory.icon
    }

    /// Display name based on category
    var displayName: String {
        concernCategory.displayName
    }

    /// Human-readable summary text
    var summaryText: String {
        let daySpan = Calendar.current.dateComponents([.day], from: firstMentionAt, to: Date()).day ?? 0

        switch patternType {
        case .frequency:
            return "Mentioned \(mentionCount) times in \(daySpan) days"
        case .trend:
            let direction = trend?.displayName.lowercased() ?? "changing"
            return "Observations have been \(direction) over \(daySpan) days"
        case .correlation:
            if let event = correlatedEvents?.first {
                return "Started around when \(event.eventDescription.lowercased())"
            }
            return "Started near a recent change"
        case .new:
            return "First noted \(daySpan) days ago"
        case .absence:
            return "Not mentioned recently (was frequent before)"
        }
    }

    /// Primary correlated event (if any)
    var primaryCorrelation: CorrelatedEvent? {
        correlatedEvents?.first
    }

    /// Whether this pattern has a strong correlation
    var hasStrongCorrelation: Bool {
        correlatedEvents?.contains { $0.strength == .strong } ?? false
    }
}

// MARK: - GRDB Conformance

extension DetectedPattern: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "detected_patterns_cache" }

    init(row: Row) throws {
        id = row["id"]
        circleId = row["circle_id"]
        patientId = row["patient_id"]
        concernCategory = ConcernCategory(rawValue: row["concern_category"]) ?? .tiredness
        concernKeywords = (try? JSONDecoder().decode([String].self, from: row["concern_keywords"] as Data)) ?? []
        patternType = PatternType(rawValue: row["pattern_type"]) ?? .frequency
        patternHash = row["pattern_hash"]
        mentionCount = row["mention_count"]
        firstMentionAt = row["first_mention_at"]
        lastMentionAt = row["last_mention_at"]
        trend = (row["trend"] as String?).flatMap { TrendDirection(rawValue: $0) }
        correlatedEvents = (row["correlated_events"] as Data?).flatMap { try? JSONDecoder().decode([CorrelatedEvent].self, from: $0) }
        status = PatternStatus(rawValue: row["status"]) ?? .active
        dismissedBy = row["dismissed_by"]
        dismissedAt = row["dismissed_at"]
        sourceHandoffIds = (try? JSONDecoder().decode([UUID].self, from: row["source_handoff_ids"] as Data)) ?? []
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["circle_id"] = circleId
        container["patient_id"] = patientId
        container["concern_category"] = concernCategory.rawValue
        container["concern_keywords"] = try JSONEncoder().encode(concernKeywords)
        container["pattern_type"] = patternType.rawValue
        container["pattern_hash"] = patternHash
        container["mention_count"] = mentionCount
        container["first_mention_at"] = firstMentionAt
        container["last_mention_at"] = lastMentionAt
        container["trend"] = trend?.rawValue
        container["correlated_events"] = correlatedEvents.flatMap { try? JSONEncoder().encode($0) }
        container["status"] = status.rawValue
        container["dismissed_by"] = dismissedBy
        container["dismissed_at"] = dismissedAt
        container["source_handoff_ids"] = try JSONEncoder().encode(sourceHandoffIds)
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }
}

// MARK: - Correlated Event

struct CorrelatedEvent: Codable, Equatable, Identifiable {
    let eventType: EventType
    let eventId: String
    let eventDescription: String
    let eventDate: Date
    let daysDifference: Int
    let strength: CorrelationStrength

    var id: String { eventId }

    enum EventType: String, Codable {
        case medication = "MEDICATION"
        case facilityChange = "FACILITY_CHANGE"

        var icon: String {
            switch self {
            case .medication: return "pills"
            case .facilityChange: return "building.2"
            }
        }
    }

    enum CorrelationStrength: String, Codable {
        case strong = "STRONG"
        case possible = "POSSIBLE"

        var displayName: String {
            switch self {
            case .strong: return "Likely related"
            case .possible: return "Possibly related"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case eventType
        case eventId
        case eventDescription
        case eventDate
        case daysDifference
        case strength
    }
}
