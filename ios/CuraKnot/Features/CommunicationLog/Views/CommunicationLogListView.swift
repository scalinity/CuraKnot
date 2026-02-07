import SwiftUI

// MARK: - Communication Log List View

struct CommunicationLogListView: View {
    @StateObject private var viewModel: CommunicationLogListViewModel
    @State private var showingPaywall = false

    private let service: CommunicationLogService
    private let circleId: String
    private let patientId: String?

    init(
        service: CommunicationLogService,
        circleId: String,
        patientId: String? = nil
    ) {
        self.service = service
        self.circleId = circleId
        self.patientId = patientId
        _viewModel = StateObject(wrappedValue: CommunicationLogListViewModel(
            service: service,
            circleId: circleId,
            patientId: patientId
        ))
    }

    var body: some View {
        Group {
            if viewModel.hasFeatureAccess {
                contentView
            } else {
                lockedView
            }
        }
        .navigationTitle("Facility Calls")
        .toolbar {
            if viewModel.hasFeatureAccess {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showingNewLog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log new call")
                }

                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(CommunicationLogListViewModel.LogFilter.allCases, id: \.rawValue) { filter in
                            Button {
                                viewModel.selectedFilter = filter
                            } label: {
                                if viewModel.selectedFilter == filter {
                                    Label(filter.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(filter.rawValue)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter logs")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingNewLog) {
            // New log sheet placeholder
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .task {
            if viewModel.hasFeatureAccess {
                await viewModel.loadLogs()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading && viewModel.groupedLogs.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredLogs.isEmpty {
            emptyStateView
        } else {
            logList
        }
    }

    // MARK: - Log List

    private var logList: some View {
        List {
            if viewModel.overdueFollowUpsCount > 0 {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.overdueFollowUpsCount) overdue follow-up\(viewModel.overdueFollowUpsCount == 1 ? "" : "s")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Tap to view")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedFilter = .overdue
                    }
                }
            }

            ForEach(viewModel.filteredLogs) { group in
                Section(group.dateHeader) {
                    ForEach(group.logs) { log in
                        NavigationLink {
                            CommunicationLogDetailView(
                                viewModel: CommunicationLogDetailViewModel(
                                    log: log,
                                    service: service
                                )
                            )
                        } label: {
                            CommunicationLogRow(log: log)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteLog(log)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            if log.followUpStatus == .pending {
                                Button {
                                    Task {
                                        await viewModel.markFollowUpComplete(log)
                                    }
                                } label: {
                                    Label("Complete", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $viewModel.searchText, prompt: "Search calls")
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Calls Logged", systemImage: "phone.badge.plus")
        } description: {
            if viewModel.selectedFilter != .all {
                Text("No calls match the current filter.")
            } else {
                Text("Log your facility calls to keep track of conversations and follow-ups.")
            }
        } actions: {
            if viewModel.selectedFilter != .all {
                Button("Show All") {
                    viewModel.selectedFilter = .all
                }
            } else {
                Button {
                    viewModel.showingNewLog = true
                } label: {
                    Label("Log a Call", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Locked View (FREE tier)

    private var lockedView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                SwiftUI.Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.2), Color.blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "phone.badge.checkmark")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.teal, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Facility Communication Log")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Track facility calls, manage follow-ups, and never forget who said what.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeaturePoint(icon: "phone.fill", text: "One-tap call logging")
                FeaturePoint(icon: "clock.badge.checkmark", text: "Follow-up reminders")
                FeaturePoint(icon: "magnifyingglass", text: "Searchable history")
                FeaturePoint(icon: "sparkles", text: "AI task suggestions (Family)")
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)

            Spacer()

            Button {
                showingPaywall = true
            } label: {
                Text("Upgrade to Plus")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.teal, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal)
            .padding(.bottom)
            .accessibilityLabel("Upgrade to Plus subscription")
        }
    }
}

// MARK: - Feature Point

private struct FeaturePoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Communication Log Row

struct CommunicationLogRow: View {
    let log: CommunicationLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: log.communicationType.icon)
                    .foregroundStyle(.secondary)
                Text(log.facilityName)
                    .font(.headline)
                Spacer()
                Text(log.formattedCallDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text("Spoke with:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(log.contactName)
                    .font(.subheadline)
            }

            Text(log.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if log.hasFollowUp, let followUpDate = log.followUpDate {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundStyle(log.isFollowUpOverdue ? .red : (log.isFollowUpToday ? .orange : .secondary))
                    Text("Follow-up: \(followUpDate, style: .date)")
                        .font(.caption)
                        .foregroundStyle(log.isFollowUpOverdue ? .red : (log.isFollowUpToday ? .orange : .secondary))
                }
            }

            if log.resolutionStatus != .open {
                HStack {
                    Text(log.resolutionStatus.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(log.resolutionStatus == .resolved ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .foregroundStyle(log.resolutionStatus == .resolved ? .green : .red)
                        .cornerRadius(4)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(log.communicationType.displayName) with \(log.facilityName), \(log.contactName), \(log.callType.displayName)")
    }
}
