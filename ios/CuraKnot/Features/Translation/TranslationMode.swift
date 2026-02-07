import Foundation

// MARK: - Translation Mode

enum TranslationMode: String, Codable, CaseIterable, Identifiable {
    case auto = "AUTO"
    case onDemand = "ON_DEMAND"
    case off = "OFF"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-translate"
        case .onDemand: return "Show original, offer translation"
        case .off: return "Always show original"
        }
    }

    var description: String {
        switch self {
        case .auto:
            return "Automatically translate content to your preferred language"
        case .onDemand:
            return "Show original text with a button to translate"
        case .off:
            return "Always show content in its original language"
        }
    }
}

// MARK: - Language Preferences

struct LanguagePreferences: Codable, Equatable {
    var preferredLanguage: String = "en"
    var translationMode: TranslationMode = .auto
    var showOriginal: Bool = false

    /// The preferred language as a SupportedLanguage enum
    var preferredSupportedLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: preferredLanguage) ?? .english
    }
}
