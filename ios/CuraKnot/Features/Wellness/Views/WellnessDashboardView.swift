import SwiftUI

// MARK: - Wellness Dashboard View

/// Dashboard showing wellness history and trends
struct WellnessDashboardView: View {
    @StateObject private var viewModel: WellnessDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    init(wellnessService: WellnessService) {
        _viewModel = StateObject(wrappedValue: WellnessDashboardViewModel(wellnessService: wellnessService))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading history...")
                } else if !viewModel.hasData {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("Wellness History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadHistory()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No History Yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Complete your first weekly check-in to start tracking your wellness over time.")
        }
    }

    // MARK: - History List

    private var historyList: some View {
        List {
            // Trend section
            if let trend = viewModel.trendData {
                Section {
                    TrendCard(trend: trend)
                }
            }

            // History section
            Section("Check-In History") {
                ForEach(viewModel.weekSummaries) { summary in
                    WeekSummaryRow(
                        summary: summary,
                        scoreColor: viewModel.scoreColor(for: summary.totalScore)
                    )
                }
            }
        }
    }
}

// MARK: - Trend Card

private struct TrendCard: View {
    let trend: WellnessDashboardViewModel.TrendData

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall Trend")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: trend.trend.iconName)
                            .foregroundStyle(trend.trend.color)

                        Text(trend.trend.description)
                            .font(.headline)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Avg Score")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(Int(trend.averageScore))")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }

            HStack {
                Text("\(trend.weeksTracked) weeks tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Week Summary Row

private struct WeekSummaryRow: View {
    let summary: WellnessDashboardViewModel.WeekSummary
    let scoreColor: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.formattedWeekRange)
                    .font(.subheadline)

                HStack(spacing: 8) {
                    Text(stressEmoji(for: summary.stressLevel))
                    Text(sleepEmoji(for: summary.sleepQuality))
                    Text(capacityEmoji(for: summary.capacityLevel))
                }
                .font(.caption)
            }

            Spacer()

            if summary.skipped {
                Text("Skipped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            } else if let score = summary.totalScore {
                VStack(alignment: .trailing) {
                    Text("\(score)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(scoreColor)

                    Text(summary.riskLevel.displayText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stressEmoji(for level: Int) -> String {
        switch level {
        case 1: return "😌"
        case 2: return "😐"
        case 3: return "😟"
        case 4: return "😰"
        case 5: return "😫"
        default: return "❓"
        }
    }

    private func sleepEmoji(for quality: Int) -> String {
        switch quality {
        case 1: return "💀"
        case 2: return "😵"
        case 3: return "😶"
        case 4: return "🥱"
        case 5: return "😴"
        default: return "❓"
        }
    }

    private func capacityEmoji(for level: Int) -> String {
        switch level {
        case 1: return "🫠"
        case 2: return "🤏"
        case 3: return "✋"
        case 4: return "💪"
        default: return "❓"
        }
    }
}
