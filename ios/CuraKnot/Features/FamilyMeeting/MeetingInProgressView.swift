import SwiftUI

// MARK: - Meeting In Progress View

struct MeetingInProgressView: View {
    @StateObject private var viewModel: FamilyMeetingViewModel
    @State private var showingEndConfirmation = false

    init(meeting: FamilyMeeting, service: FamilyMeetingService, subscriptionManager: SubscriptionManager) {
        _viewModel = StateObject(wrappedValue: FamilyMeetingViewModel(
            meeting: meeting,
            service: service,
            subscriptionManager: subscriptionManager
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress Bar
            ProgressView(value: viewModel.progress)
                .tint(.green)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityLabel("Meeting progress")
                .accessibilityValue("\(Int(viewModel.progress * 100)) percent complete")

            HStack {
                Text("\(Int(viewModel.progress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.completedItemCount)/\(viewModel.agendaItems.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            if viewModel.allItemsProcessed {
                // All items done
                allItemsCompleteView
            } else if let currentItem = viewModel.currentAgendaItem {
                // Current agenda item
                ScrollView {
                    VStack(spacing: 20) {
                        currentItemHeader(currentItem)
                        notesSection
                        decisionSection
                        actionItemsSection
                        navigationButtons
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No More Items", systemImage: "checkmark.circle", description: Text("All agenda items have been processed."))
            }
        }
        .navigationTitle(viewModel.meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("End") {
                    showingEndConfirmation = true
                }
                .foregroundStyle(.red)
                .accessibilityLabel("End meeting")
                .accessibilityHint("Ends the meeting and generates a summary")
            }
        }
        .task {
            await viewModel.loadMeetingData()
        }
        .sheet(isPresented: $viewModel.showAddActionItem) {
            AddActionItemSheet { description, assignedTo, dueDate in
                Task {
                    await viewModel.addActionItem(
                        description: description,
                        assignedTo: assignedTo,
                        dueDate: dueDate
                    )
                }
            }
        }
        .confirmationDialog("End Meeting?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End Meeting", role: .destructive) {
                Task { await viewModel.endMeeting() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let pendingCount = viewModel.pendingItemCount
            if pendingCount > 0 {
                Text("\(pendingCount) item(s) will be skipped. The current item's notes and decision will be saved.")
            } else {
                Text("This will finalize the meeting and mark all attendees as present.")
            }
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

    // MARK: - Current Item Header

    private func currentItemHeader(_ item: MeetingAgendaItem) -> some View {
        VStack(spacing: 8) {
            Text("Now Discussing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(item.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            if let desc = item.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now discussing: \(item.title)")
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)

            TextEditor(text: $viewModel.currentNotes)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
                .accessibilityLabel("Meeting notes")
                .accessibilityHint("Enter notes for this agenda item")
        }
    }

    // MARK: - Decision Section

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Decision", systemImage: "checkmark.seal")
                .font(.headline)

            TextField("What was decided?", text: $viewModel.currentDecision, axis: .vertical)
                .lineLimit(2...4)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
                .accessibilityLabel("Decision")
                .accessibilityHint("Enter what was decided for this agenda item")
        }
    }

    // MARK: - Action Items Section

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Action Items", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.showAddActionItem = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add action item")
            }

            if viewModel.currentActionItems.isEmpty {
                Text("No action items yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.currentActionItems) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.description)
                            .font(.subheadline)
                        Spacer()
                        if let dueDate = item.dueDate {
                            Text(dueDate, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            Button {
                Task { await viewModel.skipItem() }
            } label: {
                Label("Skip", systemImage: "forward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Skip this agenda item and move to the next one")

            Button {
                Task { await viewModel.completeItem() }
            } label: {
                Label("Complete", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Mark this agenda item as completed and save notes")
        }
    }

    // MARK: - All Items Complete

    private var allItemsCompleteView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("All Items Discussed")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You've covered all agenda items. End the meeting to generate a summary.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingEndConfirmation = true
            } label: {
                Text("End Meeting")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .accessibilityHint("Ends the meeting and allows you to generate a summary")

            Spacer()
        }
    }
}
