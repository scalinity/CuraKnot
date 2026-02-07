import SwiftUI

// MARK: - Condition List View

struct ConditionListView: View {
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @StateObject private var viewModel: ConditionListViewModel
    let circleId: UUID
    let patientId: UUID

    init(circleId: UUID, patientId: UUID) {
        self.circleId = circleId
        self.patientId = patientId
        _viewModel = StateObject(wrappedValue: ConditionListViewModel(
            circleId: circleId,
            patientId: patientId
        ))
    }

    var body: some View {
        List {
            statusFilterSection

            if viewModel.conditionLimit != nil {
                limitIndicatorSection
            }

            if viewModel.isLoading && viewModel.conditions.isEmpty {
                loadingSection
            } else if viewModel.conditions.isEmpty {
                emptyStateSection
            } else {
                conditionsSection
            }
        }
        .navigationTitle("Condition Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.canCreate {
                    Button {
                        viewModel.showingNewCondition = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showingNewCondition) {
            NewConditionView(
                circleId: circleId,
                patientId: patientId
            ) { type, location, description, startDate in
                await viewModel.createCondition(
                    type: type,
                    bodyLocation: location,
                    description: description,
                    startDate: startDate
                )
            }
        }
        .refreshable {
            await viewModel.loadConditions()
        }
        .task {
            viewModel.configure(
                conditionPhotoService: dependencyContainer.conditionPhotoService,
                subscriptionManager: dependencyContainer.subscriptionManager
            )
            await viewModel.loadConditions()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Sections

    private var statusFilterSection: some View {
        Section {
            Picker("Status", selection: $viewModel.statusFilter) {
                Text("Active").tag(ConditionStatus?.some(.active))
                Text("Resolved").tag(ConditionStatus?.some(.resolved))
                Text("Archived").tag(ConditionStatus?.some(.archived))
                Text("All").tag(ConditionStatus?.none)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.statusFilter) { _, _ in
                Task { await viewModel.loadConditions() }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private var limitIndicatorSection: some View {
        Section {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .foregroundStyle(.blue)
                Text(viewModel.limitLabel)
                    .font(.subheadline)
                Spacer()
                if viewModel.isAtLimit {
                    Text("Upgrade")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.blue)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("No Tracked Conditions")
                    .font(.headline)

                Text("Track wounds, rashes, and other conditions with photos to document progression over time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if viewModel.canCreate {
                    Button("Track a Condition") {
                        viewModel.showingNewCondition = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private var conditionsSection: some View {
        Section {
            ForEach(viewModel.conditions) { condition in
                NavigationLink {
                    ConditionDetailView(condition: condition)
                } label: {
                    ConditionRowView(condition: condition)
                }
            }
        }
    }
}

// MARK: - Condition Row

struct ConditionRowView: View {
    let condition: TrackedCondition

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: condition.conditionType.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(condition.conditionType.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text(condition.bodyLocation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(condition.status.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.1))
                        .clipShape(Capsule())

                    Text("\(condition.daysSinceStart) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch condition.status {
        case .active: return .blue
        case .resolved: return .green
        case .archived: return .gray
        }
    }
}
