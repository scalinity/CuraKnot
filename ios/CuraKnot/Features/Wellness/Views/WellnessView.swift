import SwiftUI

// MARK: - Wellness View

/// Main wellness feature view showing current status, alerts, and check-in prompt
struct WellnessView: View {
    @StateObject private var viewModel: WellnessViewModel

    init(wellnessService: WellnessService) {
        _viewModel = StateObject(wrappedValue: WellnessViewModel(wellnessService: wellnessService))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.viewState {
                case .loading:
                    loadingView

                case .needsSubscription:
                    WellnessPreviewView()

                case .needsCheckIn:
                    needsCheckInView

                case .hasCheckIn(let checkIn):
                    dashboardView(checkIn: checkIn)

                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Wellness")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.openHistory()
                        } label: {
                            Label("History", systemImage: "chart.line.uptrend.xyaxis")
                        }

                        Button {
                            viewModel.openSettings()
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }

                        NavigationLink {
                            RespiteFinderTabView()
                        } label: {
                            Label("Respite Care", systemImage: "heart.text.clipboard")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCheckInSheet) {
                CheckInView(
                    wellnessService: viewModel.wellnessService,
                    onComplete: { checkIn in
                        viewModel.checkInCompleted(checkIn)
                    }
                )
            }
            .sheet(isPresented: $viewModel.showHistorySheet) {
                WellnessDashboardView(wellnessService: viewModel.wellnessService)
            }
            .sheet(isPresented: $viewModel.showSettingsSheet) {
                WellnessSettingsView(wellnessService: viewModel.wellnessService)
            }
            .task {
                await viewModel.loadData()
            }
            .refreshable {
                await viewModel.refreshData()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading wellness data...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Needs Check-In View

    private var needsCheckInView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Alert banner if present
                if let alert = viewModel.highestSeverityAlert {
                    AlertBannerView(alert: alert) {
                        Task {
                            await viewModel.dismissAlert(alert)
                        }
                    }
                    .padding(.horizontal)
                }

                // Check-in prompt
                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text("Weekly Check-In")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Take 30 seconds to log how you're doing this week.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        viewModel.startCheckIn()
                    } label: {
                        Text("Start Check-In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Dashboard View

    private func dashboardView(checkIn: WellnessCheckIn) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Alert banner if present
                if let alert = viewModel.highestSeverityAlert {
                    AlertBannerView(alert: alert) {
                        Task {
                            await viewModel.dismissAlert(alert)
                        }
                    }
                    .padding(.horizontal)
                }

                // Current score card
                WellnessScoreCard(checkIn: checkIn)
                    .padding(.horizontal)

                // Quick stats
                HStack(spacing: 12) {
                    WellnessStatCard(
                        title: "Stress",
                        value: checkIn.stressEmoji,
                        subtitle: stressDescription(for: checkIn.stressLevel)
                    )

                    WellnessStatCard(
                        title: "Sleep",
                        value: checkIn.sleepEmoji,
                        subtitle: sleepDescription(for: checkIn.sleepQuality)
                    )

                    WellnessStatCard(
                        title: "Capacity",
                        value: checkIn.capacityEmoji,
                        subtitle: capacityDescription(for: checkIn.capacityLevel)
                    )
                }
                .padding(.horizontal)

                // Week info
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(checkIn.formattedWeekRange)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Completed")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
                .font(.subheadline)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await viewModel.loadData()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func stressDescription(for level: Int) -> String {
        switch level {
        case 1: return "Calm"
        case 2: return "Slight"
        case 3: return "Moderate"
        case 4: return "High"
        case 5: return "Extreme"
        default: return ""
        }
    }

    private func sleepDescription(for quality: Int) -> String {
        switch quality {
        case 1: return "Very poor"
        case 2: return "Poor"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    private func capacityDescription(for level: Int) -> String {
        switch level {
        case 1: return "Empty"
        case 2: return "Limited"
        case 3: return "Some room"
        case 4: return "Full"
        default: return ""
        }
    }
}

// MARK: - Stat Card

private struct WellnessStatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
