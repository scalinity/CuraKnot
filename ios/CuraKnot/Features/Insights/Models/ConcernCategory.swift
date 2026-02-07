import Foundation
import SwiftUI

/// Symptom concern categories for pattern detection
enum ConcernCategory: String, Codable, CaseIterable, Identifiable {
    case tiredness = "TIREDNESS"
    case appetite = "APPETITE"
    case sleep = "SLEEP"
    case pain = "PAIN"
    case mood = "MOOD"
    case mobility = "MOBILITY"
    case cognition = "COGNITION"
    case digestion = "DIGESTION"
    case breathing = "BREATHING"
    case skin = "SKIN"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiredness: return "Tiredness"
        case .appetite: return "Appetite"
        case .sleep: return "Sleep"
        case .pain: return "Pain"
        case .mood: return "Mood"
        case .mobility: return "Mobility"
        case .cognition: return "Cognition"
        case .digestion: return "Digestion"
        case .breathing: return "Breathing"
        case .skin: return "Skin"
        }
    }

    var icon: String {
        switch self {
        case .tiredness: return "😴"
        case .appetite: return "🍽️"
        case .sleep: return "🌙"
        case .pain: return "😣"
        case .mood: return "😊"
        case .mobility: return "🚶"
        case .cognition: return "🧠"
        case .digestion: return "🫄"
        case .breathing: return "💨"
        case .skin: return "🩹"
        }
    }

    var color: Color {
        switch self {
        case .tiredness: return .purple
        case .appetite: return .orange
        case .sleep: return .indigo
        case .pain: return .red
        case .mood: return .yellow
        case .mobility: return .green
        case .cognition: return .blue
        case .digestion: return .brown
        case .breathing: return .cyan
        case .skin: return .pink
        }
    }
}
