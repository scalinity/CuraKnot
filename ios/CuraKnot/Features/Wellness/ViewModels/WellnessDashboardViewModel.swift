import Foundation
import SwiftUI

// MARK: - Wellness Dashboard View Model

/// ViewModel for the wellness dashboard showing history and trends
@MainActor
final class WellnessDashboardViewModel: ObservableObject {

    // MARK: - Types

    struct WeekSummary: Identifiable {
        let id: String
        let weekStart: Date
        let totalScore: Int?
        let riskLevel: RiskLevel
        let stressLevel: Int
        let sleepQuality: Int
        let capacityLevel: Int
        let skipped: Bool

        var formattedWeekRange: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: weekStart)

            guard let endDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) else {
                return "Week of \(startStr)"
            }
            let endStr = formatter.string(from: endDate)
            return "\(startStr) - \(endStr)"
        }

        init(from checkIn: WellnessCheckIn) {
            self.id = checkIn.id
            self.weekStart = checkIn.weekStart
            self.totalScore = checkIn.totalScore
            self.riskLevel = checkIn.riskLevel
            self.stressLevel = checkIn.stressLevel
            self.sleepQuality = checkIn.sleepQuality
            self.capacityLevel = checkIn.capacityLevel
            self.skipped = checkIn.skipped
        }
    }

    struct TrendData {
        let averageScore: Double
        let trend: Trend
        let weeksTracked: Int

        enum Trend {
            case improving
            case stable
            case declining
            case insufficient

            var description: String {
                switch self {
                case .improving: return "Improving"
                case .stable: return "Stable"
                case .declining: return "Needs attention"
                case .insufficient: return "More data needed"
                }
            }

            var iconName: String {
                switch self {
                case .improving: return "arrow.up.right"
                case .stable: return "arrow.right"
                case .declining: return "arrow.down.right"
                case .insufficient: return "questionmark"
                }
            }

            var color: Color {
                switch self {
                case .improving: return .green
                case .stable: return .blue
                case .declining: return .orange
                case .insufficient: return .gray
                }
            }
        }
    }

    // MARK: - Properties

    private let wellnessService: WellnessService

    @Published var weekSummaries: [WeekSummary] = []
    @Published var trendData: TrendData?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var hasData: Bool {
        !weekSummaries.isEmpty
    }

    // MARK: - Initialization

    init(wellnessService: WellnessService) {
        self.wellnessService = wellnessService
    }

    // MARK: - Data Loading

    func loadHistory() async {
        isLoading = true
        errorMessage = nil

        do {
            let checkIns = try await wellnessService.getCheckInHistory(weeks: 12)
            weekSummaries = checkIns.map { WeekSummary(from: $0) }
            calculateTrend(from: checkIns)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Trend Calculation

    private func calculateTrend(from checkIns: [WellnessCheckIn]) {
        let validCheckIns = checkIns.filter { !$0.skipped && $0.totalScore != nil }

        guard validCheckIns.count >= 2 else {
            trendData = TrendData(
                averageScore: validCheckIns.first.flatMap { Double($0.totalScore ?? 0) } ?? 0,
                trend: .insufficient,
                weeksTracked: validCheckIns.count
            )
            return
        }

        // Calculate average
        let scores = validCheckIns.compactMap { $0.totalScore }
        let average = Double(scores.reduce(0, +)) / Double(scores.count)

        // Calculate trend (compare last 4 weeks to prior 4 weeks)
        let recent = Array(validCheckIns.prefix(4))
        let prior = Array(validCheckIns.dropFirst(4).prefix(4))

        let trend: TrendData.Trend
        if prior.isEmpty {
            trend = .insufficient
        } else {
            let recentAvg = Double(recent.compactMap { $0.totalScore }.reduce(0, +)) / Double(recent.count)
            let priorAvg = Double(prior.compactMap { $0.totalScore }.reduce(0, +)) / Double(prior.count)

            let difference = recentAvg - priorAvg
            if difference > 5 {
                trend = .improving
            } else if difference < -5 {
                trend = .declining
            } else {
                trend = .stable
            }
        }

        trendData = TrendData(
            averageScore: average,
            trend: trend,
            weeksTracked: validCheckIns.count
        )
    }

    // MARK: - Formatting

    func scoreColor(for score: Int?) -> Color {
        guard let score = score else { return .gray }
        if score >= 70 { return .green }
        if score >= 40 { return .yellow }
        return .red
    }

    func riskColor(for risk: RiskLevel) -> Color {
        switch risk {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .red
        case .unknown: return .gray
        }
    }
}
