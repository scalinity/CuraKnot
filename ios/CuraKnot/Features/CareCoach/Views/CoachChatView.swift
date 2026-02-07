import SwiftUI

// MARK: - Coach Chat View

struct CoachChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @StateObject private var viewModel = CoachChatViewModel()

    @State private var showingConversationList = false
    @State private var showingPatientPicker = false
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Patient context header
                if let patientName = viewModel.patientName {
                    PatientContextHeader(
                        patientName: patientName,
                        contextReferences: viewModel.contextReferences,
                        onChangeTap: { showingPatientPicker = true }
                    )
                }

                // Usage info bar (when limited)
                if let usage = viewModel.usageInfo, !usage.unlimited {
                    UsageInfoBar(usage: usage)
                }

                // Chat content
                if viewModel.showUpgradePrompt {
                    CoachUpgradePrompt(
                        plan: viewModel.usageInfo?.plan ?? "FREE",
                        onUpgrade: handleUpgrade
                    )
                } else {
                    chatContent
                }
            }
            .navigationTitle("Care Coach")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingConversationList = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Conversation History")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.startNewConversation()
                        } label: {
                            Label("New Conversation", systemImage: "plus")
                        }

                        if viewModel.currentConversation != nil {
                            Button(role: .destructive) {
                                Task {
                                    if let conv = viewModel.currentConversation {
                                        await viewModel.archiveConversation(conv)
                                    }
                                }
                            } label: {
                                Label("Archive Conversation", systemImage: "archivebox")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Chat Options")
                }
            }
            .sheet(isPresented: $showingConversationList) {
                CoachConversationListView(
                    viewModel: viewModel,
                    onSelect: { conversation in
                        showingConversationList = false
                        Task {
                            await viewModel.selectConversation(conversation)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingPatientPicker) {
                PatientPickerSheet(
                    patients: appState.patients,
                    selectedId: viewModel.patientId,
                    onSelect: { patient in
                        viewModel.patientId = patient?.id
                        viewModel.patientName = patient?.displayName
                        showingPatientPicker = false
                    }
                )
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environmentObject(dependencyContainer)
            }
            .task {
                setupViewModel()
                await viewModel.checkAccess()
                await viewModel.loadConversations()
            }
        }
    }

    @ViewBuilder
    private var chatContent: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty && !viewModel.isLoading {
                            emptyState
                        } else {
                            ForEach(viewModel.messages) { message in
                                CoachMessageBubble(
                                    message: message,
                                    onAction: handleAction,
                                    onBookmark: { Task { await viewModel.toggleBookmark(message) } },
                                    onFeedback: { feedback in
                                        Task { await viewModel.submitFeedback(message, feedback: feedback) }
                                    }
                                )
                                .id(message.id)
                            }
                        }

                        if viewModel.isSending {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isSending) { _, isSending in
                    if isSending {
                        withAnimation {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            // Error message
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) {
                    viewModel.errorMessage = nil
                }
            }

            // Quick actions / follow-ups
            if !viewModel.suggestedFollowups.isEmpty {
                SuggestedFollowupsView(
                    followups: viewModel.suggestedFollowups,
                    onSelect: { followup in
                        Task {
                            await viewModel.sendFollowUp(followup)
                        }
                    }
                )
            }

            // Input area
            CoachInputView(
                text: $viewModel.inputText,
                isLoading: viewModel.isSending,
                onSend: {
                    Task {
                        await viewModel.sendMessage()
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Care Coach")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Ask questions about caregiving, get help preparing for appointments, or just talk through what's on your mind.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                SuggestionButton(
                    icon: "heart.text.square",
                    text: "How do I manage caregiver stress?",
                    action: { viewModel.inputText = "How do I manage caregiver stress?" }
                )

                SuggestionButton(
                    icon: "stethoscope",
                    text: "What should I ask the doctor?",
                    action: { viewModel.inputText = "What questions should I ask at the next doctor's appointment?" }
                )

                SuggestionButton(
                    icon: "pills",
                    text: "Help me understand medications",
                    action: { viewModel.inputText = "Can you help me understand the medications and their side effects?" }
                )
            }
            .padding(.top, 8)
        }
        .padding(32)
    }

    // MARK: - Setup

    private func setupViewModel() {
        viewModel.configure(coachService: dependencyContainer.coachService)
        viewModel.circleId = appState.currentCircle?.id
        viewModel.patientId = appState.patients.first?.id
        viewModel.patientName = appState.patients.first?.displayName
    }

    // MARK: - Actions

    private func handleAction(_ action: CoachAction) {
        switch action.type {
        case .createTask:
            // Navigate to task creation with prefilled data
            // TODO: Implement navigation
            // TODO: Implement navigation to task creation
            _ = action.prefillData
        case .addQuestion:
            // Add to visit pack questions
            // TODO: Implement
            // TODO: Implement adding to visit pack questions
            _ = action.prefillData
        case .updateBinder:
            // Open binder editor
            // TODO: Implement
            // TODO: Implement opening binder editor
            _ = action.prefillData
        case .callContact:
            // Initiate phone call
            if let phone = action.prefillData?["phone"],
               let url = URL(string: "tel://\(phone)") {
                UIApplication.shared.open(url)
            }
        }
    }

    private func handleUpgrade() {
        showingPaywall = true
    }
}

// MARK: - Patient Context Header

struct PatientContextHeader: View {
    let patientName: String
    let contextReferences: [String]
    let onChangeTap: () -> Void

    var body: some View {
        Button(action: onChangeTap) {
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.secondary)

                Text(patientName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !contextReferences.isEmpty {
                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(contextReferences.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change patient context, currently \(patientName)")
        .accessibilityHint("Double tap to select a different patient")
    }
}

// MARK: - Usage Info Bar

struct UsageInfoBar: View {
    let usage: CoachUsageInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.caption)

            Text(usage.displayRemaining)
                .font(.caption)

            if usage.percentUsed >= 0.8 {
                Text("• Upgrade for unlimited")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemBackground))
    }
}

// MARK: - Suggested Followups View

struct SuggestedFollowupsView: View {
    let followups: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(followups, id: \.self) { followup in
                    Button {
                        onSelect(followup)
                    } label: {
                        Text(followup)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Coach Input View

struct CoachInputView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask a question...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .disabled(isLoading)

                Button {
                    onSend()
                    isFocused = false
                } label: {
                    Image(systemName: isLoading ? "ellipsis.circle" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.accentColor : .secondary)
                }
                .disabled(!canSend)
                .accessibilityLabel(isLoading ? "Sending message" : "Send message")
                .accessibilityHint(canSend ? "Double tap to send" : "Enter a message first")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !isLoading && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            SwiftUI.TimelineView(SwiftUI.AnimationTimelineSchedule(minimumInterval: 0.2)) { timeline in
                let phase = Int(timeline.date.timeIntervalSince1970 / 0.2) % 3
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        SwiftUI.Circle()
                            .fill(Color.secondary)
                            .frame(width: 8, height: 8)
                            .offset(y: phase == index ? -4 : 0)
                            .animation(.easeInOut(duration: 0.2), value: phase)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)

            Spacer()
        }
    }
}

// MARK: - Suggestion Button

struct SuggestionButton: View {
    let icon: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

// MARK: - Patient Picker Sheet

struct PatientPickerSheet: View {
    let patients: [Patient]
    let selectedId: String?
    let onSelect: (Patient?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                } label: {
                    HStack {
                        Text("General (No specific patient)")
                        Spacer()
                        if selectedId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                ForEach(patients) { patient in
                    Button {
                        onSelect(patient)
                    } label: {
                        HStack {
                            Text(patient.displayName)
                            Spacer()
                            if selectedId == patient.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CoachChatView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
