import SwiftUI

// MARK: - Agenda Builder View

struct AgendaBuilderView: View {
    @StateObject private var viewModel: FamilyMeetingViewModel
    @State private var showingAddItem = false
    @State private var showingStartConfirmation = false

    init(meeting: FamilyMeeting, service: FamilyMeetingService, subscriptionManager: SubscriptionManager) {
        _viewModel = StateObject(wrappedValue: FamilyMeetingViewModel(
            meeting: meeting,
            service: service,
            subscriptionManager: subscriptionManager
        ))
    }

    var body: some View {
        List {
            // Meeting Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(viewModel.meeting.format.displayName, systemImage: viewModel.meeting.format.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        Text(viewModel.meeting.scheduledAt, style: .date)
                        Text("at")
                            .foregroundStyle(.secondary)
                        Text(viewModel.meeting.scheduledAt, style: .time)
                    }
                    .font(.subheadline)

                    if let link = viewModel.meeting.meetingLink, !link.isEmpty,
                       let linkURL = URL(string: link),
                       let scheme = linkURL.scheme?.lowercased(),
                       scheme == "http" || scheme == "https" {
                        Link(destination: linkURL) {
                            Label("Join Meeting", systemImage: "video")
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }

            // Agenda Items
            Section {
                if viewModel.agendaItems.isEmpty {
                    Text("No agenda items yet. Add topics to discuss.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(viewModel.agendaItems) { item in
                        AgendaItemRow(item: item)
                    }
                    .onMove { source, destination in
                        viewModel.reorderItems(from: source, to: destination)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let item = viewModel.agendaItems[index]
                            Task { await viewModel.deleteItem(item) }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Agenda")
                    Spacer()
                    Button {
                        showingAddItem = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Add agenda item")
                }
            }

            // Suggested Topics
            if !viewModel.suggestedTopics.isEmpty {
                Section("Suggested Topics") {
                    ForEach(viewModel.suggestedTopics) { topic in
                        Button {
                            Task { await viewModel.addSuggestedTopic(topic) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: topic.type.icon)
                                    .foregroundStyle(topic.type.color)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(topic.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text(topic.topicDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .accessibilityLabel("Add \(topic.title) to agenda")
                        .accessibilityHint("Double tap to add this suggested topic")
                    }
                }
            }

            // Attendees
            if !viewModel.attendees.isEmpty {
                Section("Attendees (\(viewModel.attendees.count))") {
                    ForEach(viewModel.attendees) { attendee in
                        HStack {
                            SwiftUI.Circle()
                                .fill(attendee.status.color)
                                .frame(width: 8, height: 8)
                            Text(attendee.displayName)
                                .font(.subheadline)
                            Spacer()
                            Text(attendee.status.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Actions
            Section {
                if viewModel.canSendCalendarInvites {
                    Button {
                        Task {
                            let count = await viewModel.sendInvites()
                            if count > 0 {
                                // Invites sent successfully
                            }
                        }
                    } label: {
                        Label("Send Invites", systemImage: "envelope")
                    }
                    .accessibilityHint("Send meeting invitations to all attendees")
                }

                Button {
                    showingStartConfirmation = true
                } label: {
                    Label("Start Meeting", systemImage: "play.fill")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .listRowBackground(Color.green)
                .disabled(viewModel.agendaItems.isEmpty)
                .accessibilityHint("Begin the meeting and start discussing agenda items")
            }
        }
        .navigationTitle(viewModel.meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMeetingData()
        }
        .sheet(isPresented: $showingAddItem) {
            AddAgendaItemSheet { title, description in
                Task { await viewModel.addItem(title: title, description: description) }
            }
        }
        .confirmationDialog("Start Meeting?", isPresented: $showingStartConfirmation, titleVisibility: .visible) {
            Button("Start Now") {
                Task { await viewModel.startMeeting() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will begin the meeting and notify attendees. \(viewModel.agendaItems.count) agenda items to discuss.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
        } message: {
            if let error = viewModel.error as NSError? {
                Text(error.domain.hasPrefix("FamilyMeeting") ? error.localizedDescription : "An unexpected error occurred. Please try again.")
            } else if viewModel.error != nil {
                Text("An unexpected error occurred. Please try again.")
            }
        }
    }
}

// MARK: - Agenda Item Row

struct AgendaItemRow: View {
    let item: MeetingAgendaItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.status.icon)
                .foregroundStyle(item.status.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                if let desc = item.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(item.status.displayName)
                .font(.caption2)
                .foregroundStyle(item.status.color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.status.displayName)")
    }
}
