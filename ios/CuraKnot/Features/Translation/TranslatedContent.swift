import Foundation

// MARK: - Translated Content (from Edge Function)

struct TranslatedContent: Codable, Equatable {
    let translatedText: String
    let confidenceScore: Double
    let medicalTermsFound: [String]
    let disclaimer: Bool
}

// MARK: - Translated Handoff

struct TranslatedHandoff: Codable, Equatable, Identifiable {
    let id: String
    let handoffId: String
    let targetLanguage: String
    let translatedTitle: String?
    let translatedSummary: String?
    let translatedContent: [String: AnyCodable]?
    let translationEngine: String
    let confidenceScore: Double?
    let sourceHash: String
    let isStale: Bool
    let createdAt: Date
    /// Whether the source text contained medical terms (populated from translation response disclaimer)
    let hasMedicalTerms: Bool

    var containsMedicalTerms: Bool {
        hasMedicalTerms
    }

    var medicalDisclaimer: String? {
        guard let lang = SupportedLanguage(rawValue: targetLanguage) else { return nil }
        return lang.medicalDisclaimer
    }
}

// MARK: - Detected Language

struct DetectedLanguage: Codable, Equatable {
    let detectedLanguage: String
    let confidence: Double
    let alternatives: [LanguageAlternative]

    struct LanguageAlternative: Codable, Equatable {
        let language: String
        let confidence: Double
    }

    var asSupportedLanguage: SupportedLanguage? {
        SupportedLanguage(rawValue: detectedLanguage)
    }
}

// MARK: - Glossary Entry

struct GlossaryEntry: Codable, Identifiable, Equatable {
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

    var isSystemEntry: Bool {
        circleId == nil
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        if let l = lhs.value as? String, let r = rhs.value as? String { return l == r }
        if let l = lhs.value as? Int, let r = rhs.value as? Int { return l == r }
        if let l = lhs.value as? Double, let r = rhs.value as? Double { return l == r }
        if let l = lhs.value as? Bool, let r = rhs.value as? Bool { return l == r }
        if lhs.value is NSNull, rhs.value is NSNull { return true }
        if let l = lhs.value as? [Any], let r = rhs.value as? [Any] {
            guard l.count == r.count else { return false }
            return zip(l.map { AnyCodable($0) }, r.map { AnyCodable($0) }).allSatisfy { $0 == $1 }
        }
        if let l = lhs.value as? [String: Any], let r = rhs.value as? [String: Any] {
            guard l.count == r.count else { return false }
            return l.allSatisfy { key, val in
                guard let rVal = r[key] else { return false }
                return AnyCodable(val) == AnyCodable(rVal)
            }
        }
        return false
    }
}
