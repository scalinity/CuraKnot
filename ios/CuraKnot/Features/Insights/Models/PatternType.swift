import Foundation
import SwiftUI

/// Types of detected symptom patterns
enum PatternType: String, Codable, CaseIterable, Identifiable {
    case frequency = "FREQUENCY"  // 3+ mentions in 30 days
    case trend = "TREND"           // Increasing or decreasing
    case correlation = "CORRELATION" // Near medication/facility change
    case new = "NEW"               // First mention in last 7 days
    case absence = "ABSENCE"       // Was frequent, now stopped

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frequency: return "Frequent"
        case .trend: return "Trending"
        case .correlation: return "Related Event"
        case .new: return "New"
        case .absence: return "Stopped"
        }
    }

    var description: String {
        switch self {
        case .frequency: return "Mentioned multiple times recently"
        case .trend: return "Changing over time"
        case .correlation: return "Started near a medication or care change"
        case .new: return "First mentioned recently"
        case .absence: return "Not mentioned lately (was frequent before)"
        }
    }

    var icon: String {
        switch self {
        case .frequency: return "chart.bar"
        case .trend: return "chart.line.uptrend.xyaxis"
        case .correlation: return "link"
        case .new: return "sparkle"
        case .absence: return "clock.badge.questionmark"
        }
    }

    var color: Color {
        switch self {
        case .frequency: return .blue
        case .trend: return .orange
        case .correlation: return .purple
        case .new: return .green
        case .absence: return .gray
        }
    }
}

/// Trend direction for pattern changes
enum TrendDirection: String, Codable {
    case increasing = "INCREASING"
    case decreasing = "DECREASING"
    case stable = "STABLE"

    var displayName: String {
        switch self {
        case .increasing: return "Increasing"
        case .decreasing: return "Decreasing"
        case .stable: return "Stable"
        }
    }

    var icon: String {
        switch self {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .stable: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .increasing: return .red
        case .decreasing: return .green
        case .stable: return .gray
        }
    }
}

/// Pattern status for user management
enum PatternStatus: String, Codable {
    case active = "ACTIVE"
    case dismissed = "DISMISSED"
    case tracking = "TRACKING"
}
