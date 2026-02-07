import SwiftUI

// MARK: - Communication Log Detail View

struct CommunicationLogDetailView: View {
    @StateObject var viewModel: CommunicationLogDetailViewModel
    @State private var showingReschedule = false
    @State private var newFollowUpDate = Date()

    var body: some View {
        List {
            headerSection
            contactSection
            detailsSection

            if viewModel.log.followUpDate != nil || viewModel.log.followUpStatus != .none {
                followUpSection
            }

            if viewModel.hasAISuggestionsAccess && viewModel.hasSuggestions {
                aiSuggestionsSection
            }

            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Call Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.showingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    if viewModel.log.resolutionStatus == .open {
                        Button {
                            Task { await viewModel.markResolved() }
                        } label: {
                            Label("Mark Resolved", systemImage: "checkmark.circle")
                        }

                        Button {
                            Task { await viewModel.escalate() }
                        } label: {
                            Label("Escalate", systemImage: "exclamationmark.triangle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingReschedule) {
            rescheduleSheet
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: viewModel.log.communicationType.icon)
                        .font(.title2)
                        .foregroundStyle(.teal)

                    Text(viewModel.log.facilityName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                HStack {
                    Text(viewModel.log.callDate, style: .date)
                    Text("at")
                        .foregroundStyle(.secondary)
                    Text(viewModel.log.callDate, style: .time)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let duration = viewModel.log.formattedDuration {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Duration: \(duration)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if viewModel.log.resolutionStatus != .open {
                    HStack {
                        Text(viewModel.log.resolutionStatus.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                viewModel.log.resolutionStatus == .resolved
                                    ? Color.green.opacity(0.2)
                                    : Color.red.opacity(0.2)
                            )
                            .foregroundStyle(
                                viewModel.log.resolutionStatus == .resolved
                                    ? .green
                                    : .red
                            )
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        Section("Contact") {
            HStack {
                Label(viewModel.log.contactName, systemImage: "person.fill")
                Spacer()
                if !viewModel.log.contactRole.isEmpty {
                    Text(viewModel.log.contactRolesDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.canCall {
                Button {
                    viewModel.callContact()
                } label: {
                    Label(viewModel.log.contactPhone ?? "", systemImage: "phone.fill")
                }
                .foregroundStyle(.primary)
            }

            if viewModel.canEmail {
                Button {
                    viewModel.emailContact()
                } label: {
                    Label(viewModel.log.contactEmail ?? "", systemImage: "envelope.fill")
                }
                .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        Section("Details") {
            HStack {
                Text("Type")
                Spacer()
                Label(viewModel.log.callType.displayName, systemImage: viewModel.log.callType.icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.log.summary)
                    .font(.body)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Follow-up Section

    private var followUpSection: some View {
        Section("Follow-up") {
            if let followUpDate = viewModel.log.followUpDate {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(
                                    viewModel.log.isFollowUpOverdue ? .red :
                                        (viewModel.log.isFollowUpToday ? .orange : .secondary)
                                )
                            Text(followUpDate, style: .date)
                                .foregroundStyle(
                                    viewModel.log.isFollowUpOverdue ? .red :
                                        (viewModel.log.isFollowUpToday ? .orange : .primary)
                                )
                        }
                        .font(.headline)

                        if let reason = viewModel.log.followUpReason {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.log.isFollowUpOverdue {
                            Text("Overdue")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.red)
                        } else if viewModel.log.isFollowUpToday {
                            Text("Due Today")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer()

                    Text(viewModel.log.followUpStatus.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(followUpStatusColor.opacity(0.2))
                        .foregroundStyle(followUpStatusColor)
                        .cornerRadius(4)
                }
            }

            if viewModel.log.followUpStatus == .pending {
                HStack {
                    Button {
                        Task { await viewModel.markFollowUpComplete() }
                    } label: {
                        Label("Mark Complete", systemImage: "checkmark.circle")
                    }
                    .tint(.green)

                    Spacer()

                    Button {
                        newFollowUpDate = viewModel.log.followUpDate ?? Date()
                        showingReschedule = true
                    } label: {
                        Label("Reschedule", systemImage: "calendar.badge.clock")
                    }
                    .tint(.orange)
                }
                .buttonStyle(.bordered)
            }

            if viewModel.log.followUpTaskId == nil && viewModel.log.followUpDate != nil {
                Button {
                    Task { await viewModel.createFollowUpTask() }
                } label: {
                    Label("Create Task from Follow-up", systemImage: "checklist")
                }
            }
        }
    }

    private var followUpStatusColor: Color {
        switch viewModel.log.followUpStatus {
        case .none: return .gray
        case .pending: return viewModel.log.isFollowUpOverdue ? .red : .blue
        case .complete: return .green
        case .cancelled: return .gray
        }
    }

    // MARK: - AI Suggestions Section

    private var aiSuggestionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("Suggested Tasks")
                        .font(.headline)
                }

                ForEach(viewModel.unacceptedSuggestions) { suggestion in
                    SuggestedTaskRow(
                        task: suggestion,
                        onAccept: {
                            Task { await viewModel.acceptSuggestion(suggestion) }
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("AI Suggestions")
                Spacer()
                Text("FAMILY")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .foregroundStyle(.purple)
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                viewModel.showingCreateHandoff = true
            } label: {
                Label("Create Handoff from This", systemImage: "doc.text")
            }

            Button {
                viewModel.showingCreateTask = true
            } label: {
                Label("Create Task", systemImage: "checklist")
            }

            Button {
                viewModel.openInMaps()
            } label: {
                Label("Get Directions", systemImage: "map")
            }
        }
    }

    // MARK: - Reschedule Sheet

    private var rescheduleSheet: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "New Date",
                    selection: $newFollowUpDate,
                    in: Date()...,
                    displayedComponents: .date
                )
            }
            .navigationTitle("Reschedule Follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingReschedule = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.rescheduleFollowUp(to: newFollowUpDate)
                            showingReschedule = false
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Suggested Task Row

private struct SuggestedTaskRow: View {
    let task: SuggestedTask
    let onAccept: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let description = task.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let days = task.dueInDays {
                    Text("Due in \(days) day\(days == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onAccept()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task: \(task.title)")
        }
        .padding(.vertical, 4)
    }
}
