import SwiftUI

// MARK: - Cost Projections View

struct CostProjectionsView: View {
    @StateObject private var viewModel: CostProjectionsViewModel
    @State private var showingZipEntry = false

    let circleId: String
    let patientId: String

    init(circleId: String, patientId: String, careCostService: CareCostService) {
        self.circleId = circleId
        self.patientId = patientId
        _viewModel = StateObject(wrappedValue: CostProjectionsViewModel(
            careCostService: careCostService,
            circleId: circleId,
            patientId: patientId
        ))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Calculating projections...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error:
                errorView
            case .loaded:
                loadedView
            }
        }
        .navigationTitle("Cost Projections")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.loadProjections() }
        .alert("Enter ZIP Code", isPresented: $showingZipEntry) {
            TextField("ZIP Code", text: $viewModel.zipCode)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Update") {
                Task { await viewModel.reloadWithZipCode() }
            }
        } message: {
            Text("Enter your ZIP code to get localized care cost estimates.")
        }
    }

    // MARK: - Loaded Content

    private var loadedView: some View {
        Group {
            if viewModel.needsZipCode {
                zipCodeEntryView
            } else {
                projectionsListView
            }
        }
    }

    private var zipCodeEntryView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Enter Your ZIP Code")
                    .font(.headline)

                Text("We use your location to provide accurate, regional care cost estimates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            TextField("ZIP Code", text: $viewModel.zipCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
                .multilineTextAlignment(.center)
                .font(.title3)

            Button("Get Projections") {
                Task { await viewModel.reloadWithZipCode() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.zipCode.count != 5)

            Spacer()

            FinancialDisclaimerView()
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .padding()
    }

    private var projectionsListView: some View {
        List {
            infoSection

            if let current = viewModel.currentScenario {
                Section("Current Care Level") {
                    ScenarioCard(
                        estimate: current,
                        currentMonthly: nil,
                        isCurrent: true
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }

            if !viewModel.projectedScenarios.isEmpty {
                Section("If Care Needs Increase") {
                    ForEach(viewModel.projectedScenarios) { scenario in
                        ScenarioCard(
                            estimate: scenario,
                            currentMonthly: viewModel.currentScenario?.totalMonthly,
                            isCurrent: false
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
            }

            Section {
                Button {
                    showingZipEntry = true
                } label: {
                    Label("Change ZIP Code", systemImage: "mappin.and.ellipse")
                }
                .accessibilityLabel("Enter different ZIP code for local cost estimates")
            }

            Section {
                dataSourceInfo
                    .listRowBackground(Color.clear)

                FinancialDisclaimerView()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Based on current care needs and local costs")
                        .font(.subheadline)
                    if !viewModel.areaName.isEmpty {
                        Text("in \(viewModel.areaName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Data Source Info

    private var dataSourceInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !viewModel.dataSource.isEmpty {
                Text("Based on \(viewModel.dataSource)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !viewModel.areaName.isEmpty && viewModel.dataYear > 0 {
                Text("for \(viewModel.areaName), \(String(viewModel.dataYear))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Unable to Load Projections")
                .font(.headline)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Try Again") {
                Task { await viewModel.loadProjections() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CostProjectionsView(
            circleId: "preview-circle",
            patientId: "preview-patient",
            careCostService: CareCostService.preview
        )
    }
}
