import SwiftUI
import Charts

// MARK: - Ride Analytics View (FAMILY only)

struct RideAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject var service: TransportationService

    @State private var errorMessage: String?

    // Cached analytics to avoid recomputation on every render
    @State private var cachedTotalGiven: Int = 0
    @State private var cachedTotalScheduled: Int = 0
    @State private var cachedTotalCancelled: Int = 0
    @State private var cachedCoverageRate: Double = 0
    @State private var cachedSortedStats: [RideStatistic] = []
    @State private var cachedFairnessSuggestion: String?

    private func updateCachedAnalytics() {
        let stats = service.statistics
        cachedTotalGiven = stats.reduce(0) { $0 + $1.ridesGiven }
        cachedTotalScheduled = stats.reduce(0) { $0 + $1.ridesScheduled }
        cachedTotalCancelled = stats.reduce(0) { $0 + $1.ridesCancelled }
        cachedCoverageRate = cachedTotalScheduled > 0
            ? Double(cachedTotalGiven) / Double(cachedTotalScheduled) * 100
            : 0
        cachedSortedStats = stats.sorted { $0.ridesGiven > $1.ridesGiven }
        cachedFairnessSuggestion = computeFairnessSuggestion(stats: stats)
    }

    private func computeFairnessSuggestion(stats: [RideStatistic]) -> String? {
        guard stats.count > 1 else { return nil }
        let rides = stats.map { $0.ridesGiven }
        guard !rides.isEmpty else { return nil }
        let maxRides = rides.max() ?? 0
        guard maxRides > 0 else { return nil }

        let sorted = rides.sorted()
        let median: Int
        if sorted.count == 1 {
            median = sorted[0]
        } else if sorted.count % 2 == 0 {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }

        if Double(maxRides) > Double(median) * 2.0 && median > 0 {
            if let topDriver = stats.max(by: { $0.ridesGiven < $1.ridesGiven }) {
                return "\(topDriver.userName ?? "One member") has driven \(topDriver.ridesGiven) times — consider asking others to help."
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if !service.hasAnalyticsAccess {
                    analyticsUpgradeView
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            errorMessage = nil
                            Task { await loadAnalytics() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    analyticsContent
                }
            }
            .navigationTitle("Ride Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: service.statistics) { _, _ in
                updateCachedAnalytics()
            }
            .task {
                guard !Task.isCancelled else { return }
                updateCachedAnalytics()
                await loadAnalytics()
            }
        }
    }

    // MARK: - Analytics Content

    private var analyticsContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Cards
                HStack(spacing: 12) {
                    StatCard(title: "Rides Given", value: "\(cachedTotalGiven)", icon: "car.fill", color: .blue)
                    StatCard(title: "Scheduled", value: "\(cachedTotalScheduled)", icon: "calendar", color: .purple)
                }

                HStack(spacing: 12) {
                    StatCard(title: "Cancelled", value: "\(cachedTotalCancelled)", icon: "xmark.circle", color: .red)
                    StatCard(title: "Coverage", value: String(format: "%.0f%%", cachedCoverageRate), icon: "checkmark.shield", color: .green)
                }

                // Rides by Member Chart
                if !cachedSortedStats.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rides by Member")
                            .font(.headline)

                        Chart {
                            ForEach(cachedSortedStats) { stat in
                                BarMark(
                                    x: .value("Rides", stat.ridesGiven),
                                    y: .value("Member", stat.userName ?? "Unknown")
                                )
                                .foregroundStyle(.blue.gradient)
                            }
                        }
                        .frame(height: CGFloat(max(cachedSortedStats.count * 40, 120)))
                        .chartXAxisLabel("Rides Given")
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Fairness Suggestion
                if let suggestion = cachedFairnessSuggestion {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fair Distribution")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(suggestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Empty State
                if service.statistics.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Ride Data Yet")
                            .font(.headline)
                        Text("Analytics will appear after rides are completed this month.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                }
            }
            .padding()
        }
    }

    // MARK: - Upgrade View

    private var analyticsUpgradeView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Ride Analytics")
                .font(.title2)
                .fontWeight(.bold)

            Text("Track ride distribution fairness, coverage rates, and member contributions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Text("Available on Family plan")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Load

    private func loadAnalytics() async {
        guard let circleId = appState.currentCircle?.id else { return }
        do {
            try await service.fetchStatistics(circleId: circleId)
            guard !Task.isCancelled else { return }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
