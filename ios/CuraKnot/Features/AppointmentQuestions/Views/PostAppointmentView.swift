import SwiftUI

// MARK: - Post Appointment View

struct PostAppointmentView: View {
    @StateObject private var viewModel: PostAppointmentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateTaskSheet = false
    @State private var selectedQuestion: AppointmentQuestion?

    init(
        questionService: AppointmentQuestionService,
        taskService: TaskService,
        patient: Patient
    ) {
        _viewModel = StateObject(wrappedValue: PostAppointmentViewModel(
            questionService: questionService,
            taskService: taskService,
            patient: patient
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading questions...")
                } else if viewModel.questions.isEmpty {
                    noQuestionsView
                } else {
                    questionsList
                }
            }
            .navigationTitle("After Visit")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.allReviewed {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $selectedQuestion) { question in
                CreateFollowUpTaskSheet(
                    question: question,
                    onCreate: { dueDate in
                        Task {
                            await viewModel.createFollowUpTask(from: question, dueDate: dueDate)
                        }
                    }
                )
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
            // Progress header
            Section {
                HStack {
                    Text("Progress")
                    Spacer()
                    Text("\(viewModel.reviewedCount) of \(viewModel.totalCount) reviewed")
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: Double(viewModel.reviewedCount), total: Double(viewModel.totalCount))
                    .tint(viewModel.allReviewed ? .green : .blue)
            }

            // Questions
            Section("Questions") {
                ForEach(viewModel.questions) { question in
                    PostAppointmentQuestionRow(
                        question: question,
                        onStatusChange: { q, status, notes in
                            Task {
                                await viewModel.markDiscussed(q, status: status, notes: notes)
                            }
                        }
                    )

                    if question.status == .deferred && question.followUpTaskId == nil {
                        Button {
                            selectedQuestion = question
                        } label: {
                            Label("Create Follow-up Task", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
            }

            // Summary
            if viewModel.allReviewed {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("All questions reviewed!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.headline)

                        Text("Consider creating a handoff to document the appointment outcome and any follow-up actions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            // TODO: Navigate to create handoff
                            dismiss()
                        } label: {
                            Label("Create After-Visit Handoff", systemImage: "doc.text")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - No Questions View

    private var noQuestionsView: some View {
        ContentUnavailableView {
            Label("No Questions", systemImage: "checkmark.circle")
        } description: {
            Text("There are no questions to review for this appointment.")
        } actions: {
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Create Follow-Up Task Sheet

struct CreateFollowUpTaskSheet: View {
    let question: AppointmentQuestion
    let onCreate: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    Text(question.questionText)
                        .font(.body)
                }

                if let notes = question.responseNotes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Due Date") {
                    DatePicker(
                        "Due Date",
                        selection: $dueDate,
                        in: Date()...,
                        displayedComponents: [.date]
                    )
                }
            }
            .navigationTitle("Create Follow-up Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(dueDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Identifiable Extension for Sheet

extension AppointmentQuestion {
    // Already Identifiable via protocol
}
