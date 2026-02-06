import SwiftUI

// MARK: - Meeting List View

struct MeetingListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @StateObject private var viewModel: MeetingListViewModel

    @State private var showingCreateMeeting = false
    @State private var showError = false

    init(circleId: UUID, service: FamilyMeetingService, subscriptionManager: SubscriptionManager) {
        _viewModel = StateObject(wrappedValue: MeetingListViewModel(
            circleId: circleId,
            service: service,
            subscriptionManager: subscriptionManager
        ))
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.meetings.isEmpty {
                Section {
                    ProgressView("Loading meetings...")
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            } else if viewModel.meetings.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Meetings", systemImage: "person.3")
                    } description: {
                        Text("Schedule a family meeting to coordinate care decisions together.")
                    } actions: {
                        Button("Schedule Meeting") {
                            showingCreateMeeting = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                if !viewModel.upcomingMeetings.isEmpty {
                    Section("Upcoming") {
                        ForEach(viewModel.upcomingMeetings) { meeting in
                            NavigationLink {
                                MeetingDetailRouter(
                                    meeting: meeting,
                                    service: viewModel.service,
                                    subscriptionManager: viewModel.subscriptionManager
                                )
                            } label: {
                                MeetingRow(meeting: meeting)
                            }
                        }
                    }
                }

                if !viewModel.pastMeetings.isEmpty {
                    Section("Past") {
                        ForEach(viewModel.pastMeetings) { meeting in
                            NavigationLink {
                                MeetingDetailRouter(
                                    meeting: meeting,
                                    service: viewModel.service,
                                    subscriptionManager: viewModel.subscriptionManager
                                )
                            } label: {
                                MeetingRow(meeting: meeting)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Family Meetings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateMeeting = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Schedule new meeting")
            }
        }
        .refreshable {
            await viewModel.loadMeetings()
        }
        .task {
            await viewModel.loadMeetings()
        }
        .sheet(isPresented: $showingCreateMeeting) {
            CreateMeetingView(
                service: viewModel.service,
                subscriptionManager: viewModel.subscriptionManager
            ) {
                Task { await viewModel.loadMeetings() }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error as NSError? {
                Text(error.domain.hasPrefix("FamilyMeeting") ? error.localizedDescription : "An unexpected error occurred. Please try again.")
            } else if viewModel.error != nil {
                Text("An unexpected error occurred. Please try again.")
            }
        }
        .onChange(of: viewModel.error != nil) { _, hasError in
            showError = hasError
        }
    }
}

// MARK: - Meeting Row

struct MeetingRow: View {
    let meeting: FamilyMeeting

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: meeting.format.icon)
                .font(.title3)
                .foregroundStyle(meeting.status.color)
                .frame(width: 36, height: 36)
                .background(meeting.status.color.opacity(0.12), in: SwiftUI.Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(meeting.scheduledAt, style: .date)
                    Text("at")
                        .foregroundStyle(.secondary)
                    Text(meeting.scheduledAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(meeting.status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(meeting.status.color.opacity(0.12), in: Capsule())
                .foregroundStyle(meeting.status.color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meeting.title), \(meeting.format.displayName), \(meeting.status.displayName)")
    }
}

// MARK: - Meeting Detail Router

struct MeetingDetailRouter: View {
    let meeting: FamilyMeeting
    let service: FamilyMeetingService
    let subscriptionManager: SubscriptionManager

    var body: some View {
        switch meeting.status {
        case .scheduled:
            AgendaBuilderView(meeting: meeting, service: service, subscriptionManager: subscriptionManager)
        case .inProgress:
            MeetingInProgressView(meeting: meeting, service: service, subscriptionManager: subscriptionManager)
        case .completed:
            MeetingSummaryView(meeting: meeting, service: service, subscriptionManager: subscriptionManager)
        case .cancelled:
            MeetingSummaryView(meeting: meeting, service: service, subscriptionManager: subscriptionManager)
        }
    }
}
