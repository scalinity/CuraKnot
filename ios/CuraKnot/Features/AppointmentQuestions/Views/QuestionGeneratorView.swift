import SwiftUI

// MARK: - Question Generator View

struct QuestionGeneratorView: View {
    @StateObject private var viewModel: QuestionGeneratorViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        questionService: AppointmentQuestionService,
        subscriptionManager: SubscriptionManager,
        patient: Patient,
        circleId: String,
        appointmentPackId: String? = nil
    ) {
        _viewModel = StateObject(wrappedValue: QuestionGeneratorViewModel(
            questionService: questionService,
            subscriptionManager: subscriptionManager,
            patient: patient,
            circleId: circleId,
            appointmentPackId: appointmentPackId
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading questions...")
                } else if viewModel.hasQuestions {
                    questionsList
                } else {
                    emptyState
                }
            }
            .navigationTitle("Appointment Questions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                await viewModel.generateQuestions()
                            }
                        } label: {
                            Label("Generate with AI", systemImage: "sparkles")
                        }
                        .disabled(viewModel.isGenerating)

                        Button {
                            viewModel.showAddQuestionSheet = true
                        } label: {
                            Label("Add Manually", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if viewModel.isGenerating {
                    GeneratingQuestionsOverlay()
                }
            }
            .sheet(isPresented: $viewModel.showAddQuestionSheet) {
                AddQuestionSheet { text, priority, category in
                    Task {
                        await viewModel.addQuestion(
                            text: text,
                            category: category,
                            priority: priority
                        )
                    }
                }
            }
            .sheet(isPresented: $viewModel.showUpgradePaywall) {
                UpgradePaywallView(feature: "AI Question Generation")
            }
            .alert(
                "Error",
                isPresented: .init(
                    get: { viewModel.error != nil },
                    set: { if !$0 { viewModel.error = nil } }
                ),
                presenting: viewModel.error
            ) { _ in
                Button("OK") { viewModel.error = nil }
            } message: { error in
                Text(error.localizedDescription)
            }
            .task {
                await viewModel.loadQuestions()
            }
        }
    }

    // MARK: - Questions List

    private var questionsList: some View {
        List {
            // Analysis context
            if let context = viewModel.analysisContext {
                Section {
                    AnalysisContextView(context: context)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            // AI Generated Questions
            if !viewModel.aiGeneratedQuestions.isEmpty {
                Section {
                    ForEach(viewModel.aiGeneratedQuestions) { question in
                        QuestionRow(question: question)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteQuestion(question)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Label("AI Suggested Questions", systemImage: "sparkles")
                        Spacer()
                        Text("\(viewModel.aiGeneratedQuestions.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // User Added Questions
            Section {
                ForEach(viewModel.userAddedQuestions) { question in
                    QuestionRow(question: question)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteQuestion(question)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove { from, to in
                    var reordered = viewModel.userAddedQuestions
                    reordered.move(fromOffsets: from, toOffset: to)
                    Task {
                        await viewModel.reorderQuestions(reordered)
                    }
                }

                Button {
                    viewModel.showAddQuestionSheet = true
                } label: {
                    Label("Add Question", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.plain)
            } header: {
                HStack {
                    Label("Your Questions", systemImage: "person.fill.questionmark")
                    Spacer()
                    Text("\(viewModel.userAddedQuestions.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Questions Yet", systemImage: "questionmark.bubble")
        } description: {
            Text("Generate personalized questions based on recent handoffs, or add your own.")
        } actions: {
            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.generateQuestions()
                    }
                } label: {
                    Label("Generate with AI", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.showAddQuestionSheet = true
                } label: {
                    Label("Add Manually", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Add Question Sheet

struct AddQuestionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (String, QuestionPriority, QuestionCategory) -> Void

    @State private var questionText = ""
    @State private var priority: QuestionPriority = .medium
    @State private var category: QuestionCategory = .general

    @FocusState private var isTextFieldFocused: Bool

    private var isValid: Bool {
        questionText.count >= 10 && questionText.count <= 500
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Question", text: $questionText, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isTextFieldFocused)
                } header: {
                    Text("Question")
                } footer: {
                    HStack {
                        Text("\(questionText.count)/500 characters")
                        Spacer()
                        if questionText.count < 10 {
                            Text("Minimum 10 characters")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(QuestionPriority.allCases, id: \.self) { p in
                            HStack {
                                Image(systemName: p.icon)
                                    .foregroundStyle(p.color)
                                Text(p.displayName)
                            }
                            .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(QuestionCategory.allCases, id: \.self) { c in
                            Label(c.displayName, systemImage: c.icon)
                                .tag(c)
                        }
                    }
                }
            }
            .navigationTitle("Add Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(questionText, priority, category)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Upgrade Paywall View (Placeholder)

struct UpgradePaywallView: View {
    let feature: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(.purple)

                Text("Upgrade to Plus")
                    .font(.title)
                    .fontWeight(.bold)

                Text("\(feature) is a premium feature. Upgrade to Plus for full access to personalized AI-generated questions.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button {
                        // TODO: Trigger upgrade flow
                        dismiss()
                    } label: {
                        Text("Upgrade Now")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Maybe Later") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.top)
            }
            .padding(32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Empty Questions View

struct EmptyQuestionsView: View {
    let onGenerate: () -> Void
    let onAddManual: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Questions Yet", systemImage: "questionmark.bubble")
        } description: {
            Text("Generate personalized questions based on recent handoffs, or add your own questions manually.")
        } actions: {
            VStack(spacing: 12) {
                Button {
                    onGenerate()
                } label: {
                    Label("Generate with AI", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onAddManual()
                } label: {
                    Label("Add Manually", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
