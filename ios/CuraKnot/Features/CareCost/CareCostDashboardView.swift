import SwiftUI

// MARK: - Care Cost Dashboard View

struct CareCostDashboardView: View {
    @StateObject private var viewModel: CareCostDashboardViewModel
    @EnvironmentObject private var container: DependencyContainer
    @State private var showingPaywall = false

    let circleId: String
    let patientId: String
    private let careCostService: CareCostService

    init(circleId: String, patientId: String, careCostService: CareCostService) {
        self.circleId = circleId
        self.patientId = patientId
        self.careCostService = careCostService
        _viewModel = StateObject(wrappedValue: CareCostDashboardViewModel(
            careCostService: careCostService,
            circleId: circleId,
            patientId: patientId
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasExpenseAccess {
                    upgradeView
                } else {
                    switch viewModel.state {
                    case .idle, .loading:
                        ProgressView("Loading costs...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .error:
                        errorView
                    case .loaded:
                        if viewModel.expenseCount == 0 {
                            emptyView
                        } else {
                            loadedView
                        }
                    }
                }
            }
            .navigationTitle("Care Costs")
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.load() }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Loaded Content

    private var loadedView: some View {
        ScrollView {
            VStack(spacing: 16) {
                MonthlyCostCard(
                    total: viewModel.currentMonthlyTotal,
                    breakdown: viewModel.costBreakdown
                )
                .padding(.horizontal)

                CoverageStatusCard(
                    totalAmount: viewModel.currentMonthlyTotal,
                    insuranceCovered: viewModel.insuranceCoveredTotal,
                    outOfPocket: viewModel.outOfPocketTotal
                )
                .padding(.horizontal)

                quickActionsSection
                    .padding(.horizontal)

                FinancialDisclaimerView()
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            NavigationLink {
                ExpenseTrackerView(
                    circleId: circleId,
                    patientId: patientId,
                    careCostService: careCostService
                )
            } label: {
                quickActionRow(
                    icon: "list.bullet.rectangle",
                    title: "Track Spending",
                    subtitle: "\(viewModel.expenseCount) expenses this month",
                    color: .blue
                )
            }
            .accessibilityLabel("Track spending, \(viewModel.expenseCount) expenses this month")

            if viewModel.hasProjectionAccess {
                NavigationLink {
                    CostProjectionsView(
                        circleId: circleId,
                        patientId: patientId,
                        careCostService: careCostService
                    )
                } label: {
                    quickActionRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Cost Projections",
                        subtitle: "Compare care scenarios",
                        color: .purple
                    )
                }
                .accessibilityLabel("Cost projections, compare care scenarios")
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    quickActionRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Cost Projections",
                        subtitle: "Upgrade to access",
                        color: .secondary
                    )
                }
                .accessibilityLabel("Cost projections, requires upgrade")
            }

            NavigationLink {
                FinancialResourcesView(careCostService: careCostService)
            } label: {
                quickActionRow(
                    icon: "book.closed",
                    title: "Financial Resources",
                    subtitle: "Guides and assistance programs",
                    color: .teal
                )
            }
            .accessibilityLabel("Financial resources, guides and assistance programs")
        }
    }

    private func quickActionRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        EmptyStateView(
            icon: "dollarsign.circle",
            title: "No Expenses Tracked",
            message: "Start tracking care expenses to see cost breakdowns, coverage, and projections.",
            actionTitle: "Start Tracking"
        ) {
            // Navigate to expense tracker to add first expense
        }
    }

    // MARK: - Error State

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Unable to Load Costs")
                .font(.headline)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Upgrade View

    private var upgradeView: some View {
        UpgradePromptView(
            feature: .careCostTracking,
            onUpgrade: { showingPaywall = true },
            onDismiss: {}
        )
    }
}

// MARK: - Preview

#Preview {
    CareCostDashboardView(
        circleId: "preview-circle",
        patientId: "preview-patient",
        careCostService: CareCostService.preview
    )
    .environmentObject(DependencyContainer())
}
