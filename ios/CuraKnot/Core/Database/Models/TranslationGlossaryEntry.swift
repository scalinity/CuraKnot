import Foundation
import GRDB

// MARK: - Translation Glossary Entry Model (GRDB local cache)

struct TranslationGlossaryLocal: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String?
    let sourceLanguage: String
    let targetLanguage: String
    let sourceTerm: String
    let translatedTerm: String
    let context: String?
    let category: String?
    let createdBy: String
    let createdAt: Date
}

// MARK: - GRDB Conformance

extension TranslationGlossaryLocal: FetchableRecord, PersistableRecord {
    static let databaseTableName = "translationGlossary"
}
