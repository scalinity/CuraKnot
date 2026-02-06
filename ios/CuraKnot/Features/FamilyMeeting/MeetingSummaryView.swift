import SwiftUI

// MARK: - Meeting Summary View

struct MeetingSummaryView: View {
    @StateObject private var viewModel: FamilyMeetingViewModel
    @State private var showingTaskCreation = false
    @State private var summaryGenerated = false
    @State private var generatedHandoffId: UUID?
    @State private var tasksCreatedCount = 0

    init(meeting: FamilyMeeting, service: FamilyMeetingService, subscriptionManager: SubscriptionManager) {
        _viewModel = StateObject(wrappedValue: FamilyMeetingViewModel(
            meeting: meeting,
            service: service,
            subscriptionManager: subscriptionManager
        ))
    }

    var body: some View {
        List {
            overviewSection
            decisionsSection
            actionItemsSection
            agendaItemsSection
            summaryActionsSection
        }
        .navigationTitle(viewModel.meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMeetingData()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Overview Section

    @ViewBuilder
    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                overviewHeader
                overviewStartTime
            }
        }
    }

    private var overviewHeader: some View {
        HStack {
            let isCompleted = viewModel.meeting.status == .completed
            Label(
                viewModel.meeting.status.displayName,
                systemImage: isCompleted ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundStyle(viewModel.meeting.status.color)
            .font(.subheadline)

            Spacer()

            if let minutes = viewModel.meeting.durationMinutes {
                Text("\(minutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var overviewStartTime: some View {
        if let start = viewModel.meeting.startedAt {
            HStack {
                Text(start, style: .date)
                Text("at")
                    .foregroundStyle(.secondary)
                Text(start, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Decisions Section

    @ViewBuilder
    private var decisionsSection: some View {
        if !viewModel.decisions.isEmpty {
            Section("Decisions Made") {
                ForEach(viewModel.decisions, id: \.id) { item in
                    decisionRow(item)
                }
            }
        }
    }

    private func decisionRow(_ item: MeetingAgendaItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline)
                .fontWeight(.medium)
            if let decision = item.decision {
                Text(decision)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Decision for \(item.title): \(item.decision ?? "No decision")")
    }

    // MARK: - Action Items Section

    @ViewBuilder
    private var actionItemsSection: some View {
        if !viewModel.actionItems.isEmpty {
            Section("Action Items (\(viewModel.actionItems.count))") {
                ForEach(viewModel.actionItems, id: \.id) { item in
                    actionItemRow(item)
                }
            }
        }
    }

    private func actionItemRow(_ item: MeetingActionItem) -> some View {
        HStack(spacing: 8) {
            let hasTask = item.hasTask
            Image(systemName: hasTask ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(hasTask ? .green : .secondary)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.description)
                    .font(.subheadline)

                HStack(spacing: 8) {
                    if let dueDate = item.dueDate {
                        Text(dueDate, format: .dateTime.month().day())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if hasTask {
                        Text("Task created")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.description)\(item.hasTask ? ", task created" : "")")
    }

    // MARK: - Agenda Items Section

    private var agendaItemsSection: some View {
        Section("Agenda Items") {
            ForEach(viewModel.agendaItems, id: \.id) { item in
                agendaItemRow(item)
            }
        }
    }

    private func agendaItemRow(_ item: MeetingAgendaItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.status.icon)
                .foregroundStyle(item.status.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.status.displayName)")
    }

    // MARK: - Summary Actions Section

    @ViewBuilder
    private var summaryActionsSection: some View {
        if viewModel.meeting.status == .completed {
            Section {
                summaryActionsContent
            }
        }
    }

    @ViewBuilder
    private var summaryActionsContent: some View {
        if viewModel.meeting.summaryHandoffId != nil || summaryGenerated {
            Label("Summary Published", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            if tasksCreatedCount > 0 {
                Label("\(tasksCreatedCount) tasks created", systemImage: "checklist")
                    .foregroundStyle(.secondary)
            }
        } else {
            publishSummaryButton
            publishWithTasksButton
        }
    }

    private var publishSummaryButton: some View {
        Button {
            generateSummary(createTasks: false)
        } label: {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label("Publish Summary as Handoff", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(viewModel.isLoading)
        .accessibilityHint("Publishes the meeting summary as a handoff to the care circle timeline")
    }

    @ViewBuilder
    private var publishWithTasksButton: some View {
        if viewModel.canCreateTasksAutomatically && !viewModel.actionItems.isEmpty {
            Button {
                generateSummary(createTasks: true)
            } label: {
                Label("Publish + Create Tasks", systemImage: "checklist.checked")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isLoading)
            .accessibilityHint("Publishes summary and creates tasks from action items")
        }
    }

    // MARK: - Helpers

    private var errorMessage: String {
        guard let error = viewModel.error else {
            return "An unexpected error occurred. Please try again."
        }
        let nsError = error as NSError
        if nsError.domain.hasPrefix("FamilyMeeting") {
            return error.localizedDescription
        }
        return "An unexpected error occurred. Please try again."
    }

    private func generateSummary(createTasks: Bool) {
        Task {
            if let result = await viewModel.generateSummary(createTasks: createTasks) {
                generatedHandoffId = result.handoffId
                tasksCreatedCount = result.tasksCreated.count
                summaryGenerated = true
            }
        }
    }
}
