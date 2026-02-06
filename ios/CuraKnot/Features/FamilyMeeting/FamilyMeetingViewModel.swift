import SwiftUI

// MARK: - Meeting List ViewModel

@MainActor
final class MeetingListViewModel: ObservableObject {
    @Published var meetings: [FamilyMeeting] = []
    @Published var isLoading = false
    @Published var error: Error?

    let circleId: UUID
    let service: FamilyMeetingService
    let subscriptionManager: SubscriptionManager

    init(circleId: UUID, service: FamilyMeetingService, subscriptionManager: SubscriptionManager) {
        self.circleId = circleId
        self.service = service
        self.subscriptionManager = subscriptionManager
    }

    var upcomingMeetings: [FamilyMeeting] {
        meetings.filter { $0.status == .scheduled || $0.status == .inProgress }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var pastMeetings: [FamilyMeeting] {
        meetings.filter { $0.status == .completed || $0.status == .cancelled }
            .sorted { $0.scheduledAt > $1.scheduledAt }
    }

    func loadMeetings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            meetings = try await service.fetchMeetings(circleId: circleId)
        } catch {
            self.error = error
        }
    }
}

// MARK: - Family Meeting ViewModel (for single meeting flow)

@MainActor
final class FamilyMeetingViewModel: ObservableObject {
    @Published var meeting: FamilyMeeting
    @Published var agendaItems: [MeetingAgendaItem] = []
    @Published var actionItems: [MeetingActionItem] = []
    @Published var attendees: [MeetingAttendee] = []
    @Published var suggestedTopics: [SuggestedTopic] = []

    @Published var currentItemIndex = 0
    @Published var currentNotes = ""
    @Published var currentDecision = ""
    @Published var currentActionItems: [MeetingActionItem] = []

    @Published var isLoading = false
    @Published var error: Error?
    @Published var showError = false
    @Published var showAddActionItem = false

    let service: FamilyMeetingService
    let subscriptionManager: SubscriptionManager
    private var activeTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    init(meeting: FamilyMeeting, service: FamilyMeetingService, subscriptionManager: SubscriptionManager) {
        self.meeting = meeting
        self.service = service
        self.subscriptionManager = subscriptionManager
    }

    deinit {
        activeTask?.cancel()
        loadTask?.cancel()
    }

    var currentAgendaItem: MeetingAgendaItem? {
        guard currentItemIndex < agendaItems.count else { return nil }
        return agendaItems[currentItemIndex]
    }

    var progress: Double {
        guard !agendaItems.isEmpty else { return 0 }
        let completedCount = agendaItems.filter { $0.status == .completed || $0.status == .skipped }.count
        return Double(completedCount) / Double(agendaItems.count)
    }

    var allItemsProcessed: Bool {
        !agendaItems.isEmpty && agendaItems.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }

    var canCreateTasksAutomatically: Bool {
        subscriptionManager.currentPlan == .family
    }

    var canUseRecurring: Bool {
        subscriptionManager.currentPlan == .family
    }

    var canSendCalendarInvites: Bool {
        subscriptionManager.currentPlan == .family
    }

    var decisions: [MeetingAgendaItem] {
        agendaItems.filter { $0.status == .completed && $0.decision != nil && !($0.decision?.isEmpty ?? true) }
    }

    var completedItemCount: Int {
        agendaItems.filter { $0.status == .completed || $0.status == .skipped }.count
    }

    var pendingItemCount: Int {
        agendaItems.filter { $0.status == .pending }.count
    }

    // MARK: - Loading

    func loadMeetingData() async {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            defer { isLoading = false }
            do {
                async let agendaTask = service.fetchAgendaItems(meetingId: meeting.id)
                async let actionTask = service.fetchActionItems(meetingId: meeting.id)
                async let attendeeTask = service.fetchAttendees(meetingId: meeting.id)
                async let suggestedTask = service.fetchSuggestedTopics(
                    circleId: meeting.circleId,
                    patientId: meeting.patientId
                )

                let (agenda, actions, att, topics) = try await (agendaTask, actionTask, attendeeTask, suggestedTask)

                guard !Task.isCancelled else { return }

                agendaItems = agenda
                actionItems = actions
                attendees = att
                suggestedTopics = topics

                // Load current item state if meeting is in progress
                if meeting.status == .inProgress {
                    if let idx = agendaItems.firstIndex(where: { $0.status == .inProgress }) {
                        currentItemIndex = idx
                        currentNotes = agendaItems[idx].notes ?? ""
                        currentDecision = agendaItems[idx].decision ?? ""
                        currentActionItems = actionItems.filter { $0.agendaItemId == agendaItems[idx].id }
                    } else if let idx = agendaItems.firstIndex(where: { $0.status == .pending }) {
                        currentItemIndex = idx
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                handleError(error)
            }
        }
        await loadTask?.value
    }

    // MARK: - Agenda Management

    func addItem(title: String, description: String?) async {
        let userId = meeting.createdBy
        do {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, trimmedTitle.count <= 500 else { return }

            let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxOrder = agendaItems.map(\.sortOrder).max() ?? -1
            let nextOrder = maxOrder < Int.max ? maxOrder + 1 : agendaItems.count
            let item = try await service.addAgendaItem(
                meetingId: meeting.id,
                addedBy: userId,
                title: trimmedTitle,
                description: trimmedDescription?.isEmpty == true ? nil : trimmedDescription,
                sortOrder: nextOrder
            )
            agendaItems.append(item)
        } catch {
            handleError(error)
        }
    }

    func addSuggestedTopic(_ topic: SuggestedTopic) async {
        await addItem(title: topic.title, description: topic.topicDescription)
        suggestedTopics.removeAll { $0.id == topic.id }
    }

    func reorderItems(from source: IndexSet, to destination: Int) {
        let previousOrder = agendaItems
        agendaItems.move(fromOffsets: source, toOffset: destination)
        for (index, _) in agendaItems.enumerated() {
            agendaItems[index].sortOrder = index
        }
        let currentItems = agendaItems
        activeTask?.cancel()
        activeTask = Task {
            // Wait briefly for any previous task to settle
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }
            do {
                try await service.reorderAgendaItems(currentItems)
            } catch {
                guard !Task.isCancelled else { return }
                // Rollback on failure
                agendaItems = previousOrder
                handleError(error)
            }
        }
    }

    func deleteItem(_ item: MeetingAgendaItem) async {
        do {
            try await service.deleteAgendaItem(item.id, from: meeting)
            agendaItems.removeAll { $0.id == item.id }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Meeting Flow

    func startMeeting() async {
        guard meeting.status == .scheduled else {
            handleError(NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Meeting can only be started from scheduled status"]))
            return
        }

        let previousMeeting = meeting
        let previousFirstItem = agendaItems.first

        do {
            try await service.startMeeting(meeting.id)
            meeting.status = .inProgress
            meeting.startedAt = Date()

            if !agendaItems.isEmpty {
                agendaItems[0].status = .inProgress
                try await service.updateAgendaItem(agendaItems[0])
            }
        } catch {
            // Rollback all state on failure
            meeting = previousMeeting
            if let savedItem = previousFirstItem, !agendaItems.isEmpty {
                agendaItems[0] = savedItem
            }
            handleError(error)
        }
    }

    func completeItem() async {
        guard currentItemIndex < agendaItems.count else { return }
        guard agendaItems[currentItemIndex].status == .inProgress else {
            handleError(NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Agenda item is no longer in progress"]))
            return
        }

        // Save previous state for rollback
        let previousItem = agendaItems[currentItemIndex]

        agendaItems[currentItemIndex].notes = currentNotes.isEmpty ? nil : currentNotes
        agendaItems[currentItemIndex].decision = currentDecision.isEmpty ? nil : currentDecision
        agendaItems[currentItemIndex].status = .completed

        do {
            try await service.updateAgendaItem(agendaItems[currentItemIndex])
            await advanceToNextItem()
        } catch {
            // Rollback local state on failure
            agendaItems[currentItemIndex] = previousItem
            handleError(error)
        }
    }

    func skipItem() async {
        guard currentItemIndex < agendaItems.count else { return }
        guard agendaItems[currentItemIndex].status == .inProgress else {
            handleError(NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Agenda item is no longer in progress"]))
            return
        }

        // Save previous state for rollback
        let previousItem = agendaItems[currentItemIndex]

        agendaItems[currentItemIndex].status = .skipped

        do {
            try await service.updateAgendaItem(agendaItems[currentItemIndex])
            await advanceToNextItem()
        } catch {
            // Rollback local state on failure
            agendaItems[currentItemIndex] = previousItem
            handleError(error)
        }
    }

    private func advanceToNextItem() async {
        // Save current state in case we need to restore
        let savedNotes = currentNotes
        let savedDecision = currentDecision
        let savedActionItems = currentActionItems

        currentNotes = ""
        currentDecision = ""
        currentActionItems = []

        if let nextIdx = agendaItems.firstIndex(where: { $0.status == .pending }) {
            // Save indices of stale in-progress items for potential rollback
            let staleIndices = agendaItems.enumerated()
                .filter { $0.element.status == .inProgress && $0.offset != nextIdx }
                .map { $0.offset }

            // Mark stale items as completed locally
            for idx in staleIndices {
                agendaItems[idx].status = .completed
            }

            currentItemIndex = nextIdx
            agendaItems[nextIdx].status = .inProgress
            do {
                try await service.updateAgendaItem(agendaItems[nextIdx])
            } catch {
                // Restore all modified state on failure
                for idx in staleIndices {
                    agendaItems[idx].status = .inProgress
                }
                agendaItems[nextIdx].status = .pending
                currentNotes = savedNotes
                currentDecision = savedDecision
                currentActionItems = savedActionItems
                handleError(error)
            }
        }
    }

    func addActionItem(description: String, assignedTo: UUID?, dueDate: Date?) async {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty, trimmedDescription.count <= 1000 else { return }

        do {
            let item = try await service.addActionItem(
                meetingId: meeting.id,
                agendaItemId: currentAgendaItem?.id,
                description: trimmedDescription,
                assignedTo: assignedTo,
                dueDate: dueDate
            )
            currentActionItems.append(item)
            actionItems.append(item)
        } catch {
            handleError(error)
        }
    }

    func endMeeting() async {
        guard meeting.status == .inProgress else {
            handleError(NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Meeting can only be ended while in progress"]))
            return
        }

        // Save previous state for rollback
        let previousAgendaItems = agendaItems
        let previousMeeting = meeting

        do {
            // Prepare updates on local copies
            for (index, item) in agendaItems.enumerated() where item.status == .pending || item.status == .inProgress {
                if item.status == .inProgress {
                    agendaItems[index].notes = currentNotes.isEmpty ? nil : currentNotes
                    agendaItems[index].decision = currentDecision.isEmpty ? nil : currentDecision
                    agendaItems[index].status = .completed
                } else {
                    agendaItems[index].status = .skipped
                }
            }

            // Batch update all modified agenda items
            let itemsToUpdate = agendaItems.filter { $0.status == .completed || $0.status == .skipped }
            try await service.batchUpdateAgendaItems(itemsToUpdate)

            // Mark attendees as attended
            try await service.markAllAttendeesAttended(meetingId: meeting.id)

            // End the meeting
            try await service.endMeeting(meeting.id)
            meeting.status = .completed
            meeting.endedAt = Date()
        } catch {
            // Rollback all local state on failure
            agendaItems = previousAgendaItems
            meeting = previousMeeting
            handleError(error)
        }
    }

    // MARK: - Summary & Tasks

    func generateSummary(createTasks: Bool) async -> (handoffId: UUID, tasksCreated: [UUID])? {
        // Idempotency check - return existing summary if already generated
        if let existingId = meeting.summaryHandoffId {
            return (existingId, [])
        }

        guard meeting.status == .completed else {
            handleError(NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Summary can only be generated for completed meetings"]))
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.generateSummary(
                meetingId: meeting.id,
                createTasks: createTasks
            )
            meeting.summaryHandoffId = result.handoffId
            return result
        } catch {
            handleError(error)
            return nil
        }
    }

    // MARK: - Invites

    func sendInvites() async -> Int {
        do {
            return try await service.sendInvites(meetingId: meeting.id)
        } catch {
            handleError(error)
            return 0
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        self.error = error
        self.showError = true
    }
}
