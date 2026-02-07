import Foundation
import GRDB

// MARK: - Translation Cache Entry Model (local cache)

struct TranslationCacheEntry: Codable, Identifiable, Equatable {
    let id: String
    let sourceTextHash: String
    let sourceLanguage: String
    let targetLanguage: String
    let translatedText: String
    var confidenceScore: Double?
    var containsMedicalTerms: Bool
    let createdAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - GRDB Conformance

extension TranslationCacheEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "translationCache"
}
