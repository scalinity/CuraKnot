import Foundation
import GRDB

/// A single mention of a concern within a handoff
struct PatternMention: Codable, Identifiable, Equatable {
    let id: UUID
    let patternId: UUID
    let handoffId: UUID
    let matchedText: String
    let normalizedTerm: String
    let mentionedAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patternId = "pattern_id"
        case handoffId = "handoff_id"
        case matchedText = "matched_text"
        case normalizedTerm = "normalized_term"
        case mentionedAt = "mentioned_at"
        case createdAt = "created_at"
    }
}

// MARK: - GRDB Conformance

extension PatternMention: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "pattern_mentions_cache" }

    init(row: Row) throws {
        id = row["id"]
        patternId = row["pattern_id"]
        handoffId = row["handoff_id"]
        matchedText = row["matched_text"]
        normalizedTerm = row["normalized_term"]
        mentionedAt = row["mentioned_at"]
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["pattern_id"] = patternId
        container["handoff_id"] = handoffId
        container["matched_text"] = matchedText
        container["normalized_term"] = normalizedTerm
        container["mentioned_at"] = mentionedAt
        container["created_at"] = createdAt
    }
}
