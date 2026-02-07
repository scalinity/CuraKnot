import Foundation
import GRDB

// MARK: - Handoff Translation Model

struct HandoffTranslation: Codable, Identifiable, Equatable {
    let id: String
    let handoffId: String
    let revisionId: String?
    let sourceLanguage: String
    let targetLanguage: String
    var translatedTitle: String?
    var translatedSummary: String?
    var translatedContentJson: String?
    let translationEngine: String
    var confidenceScore: Double?
    let sourceHash: String
    var isStale: Bool
    let createdAt: Date
}

// MARK: - GRDB Conformance

extension HandoffTranslation: FetchableRecord, PersistableRecord {
    static let databaseTableName = "handoffTranslations"
}
