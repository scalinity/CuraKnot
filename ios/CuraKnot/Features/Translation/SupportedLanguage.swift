import Foundation
import SwiftUI

// MARK: - Supported Language

enum SupportedLanguage: String, Codable, CaseIterable, Identifiable {
    // Phase 1 - Launch
    case english = "en"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"

    // Phase 2 - Expansion
    case vietnamese = "vi"
    case korean = "ko"
    case tagalog = "tl"
    case french = "fr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .chineseSimplified: return "简体中文"
        case .vietnamese: return "Tiếng Việt"
        case .korean: return "한국어"
        case .tagalog: return "Tagalog"
        case .french: return "Français"
        }
    }

    var englishName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .vietnamese: return "Vietnamese"
        case .korean: return "Korean"
        case .tagalog: return "Tagalog"
        case .french: return "French"
        }
    }

    var nativeDirection: LayoutDirection {
        return .leftToRight
    }

    static var phase1Languages: [SupportedLanguage] {
        [.english, .spanish, .chineseSimplified]
    }

    static var phase2Languages: [SupportedLanguage] {
        [.vietnamese, .korean, .tagalog, .french]
    }

    func isAvailable(for plan: SubscriptionPlan) -> Bool {
        switch plan {
        case .free:
            return self == .english
        case .plus:
            return self == .english || self == .spanish
        case .family:
            return true
        }
    }

    /// Languages available for the given subscription plan
    static func availableLanguages(for plan: SubscriptionPlan) -> [SupportedLanguage] {
        allCases.filter { $0.isAvailable(for: plan) }
    }

    /// Initialize from ISO 639-1 code string
    init?(code: String) {
        self.init(rawValue: code)
    }
}

// MARK: - Medical Disclaimer

extension SupportedLanguage {
    var medicalDisclaimer: String {
        switch self {
        case .english:
            return "Medication names shown in original language for safety."
        case .spanish:
            return "Los nombres de medicamentos se muestran en su idioma original por seguridad."
        case .chineseSimplified:
            return "为安全起见，药物名称以原文显示。"
        case .vietnamese:
            return "Tên thuốc được hiển thị bằng ngôn ngữ gốc để đảm bảo an toàn."
        case .korean:
            return "안전을 위해 약물 이름은 원래 언어로 표시됩니다."
        case .tagalog:
            return "Ang mga pangalan ng gamot ay ipinapakita sa orihinal na wika para sa kaligtasan."
        case .french:
            return "Les noms des médicaments sont affichés dans la langue d'origine par mesure de sécurité."
        }
    }
}
