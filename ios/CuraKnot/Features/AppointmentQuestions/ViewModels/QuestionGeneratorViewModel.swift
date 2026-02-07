import Foundation
import SwiftUI
import Combine

// MARK: - Question Generator ViewModel

@MainActor
final class QuestionGeneratorViewModel: ObservableObject {
    // MARK: - Published State

    @Published var questions: [AppointmentQuestion] = [] {
        didSet {
            recomputeFilteredQuestions()
        }
    }
    @Published var analysisContext: AnalysisContext?
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var showAddQuestionSheet = false
    @Published var showUpgradePaywall = false
    @Published var error: Error?

    // Cached filtered questions
    @Published private(set) var aiGeneratedQuestions: [AppointmentQuestion] = []
    @Published private(set) var userAddedQuestions: [AppointmentQuestion] = []
    @Published private(set) var highPriorityQuestions: [AppointmentQuestion] = []

    // MARK: - Dependencies

    private let questionService: AppointmentQuestionService
    private let subscriptionManager: SubscriptionManager
    private let patient: Patient
    private let circleId: String
    private var appointmentPackId: String?

    // MARK: - Computed Properties

    var hasQuestions: Bool {
        !questions.isEmpty
    }

    var pendingQuestions: [AppointmentQuestion] {
        questions.filter { $0.status == .pending }
    }

    // MARK: - Private Methods
    
    private func recomputeFilteredQuestions() {
        aiGeneratedQuestions = questions
            .filter { $0.source == .aiGenerated || $0.source == .template }
            .sorted { $0.priorityScore > $1.priorityScore }
        
        userAddedQuestions = questions
            .filter { $0.source == .userAdded }
            .sorted { $0.sortOrder < $1.sortOrder }
        
        highPriorityQuestions = questions.filter { $0.priority == .high }
    }

    // MARK: - Initialization

    init(
        questionService: AppointmentQuestionService,
        subscriptionManager: SubscriptionManager,
        patient: Patient,
        circleId: String,
        appointmentPackId: String? = nil
    ) {
        self.questionService = questionService
        self.subscriptionManager = subscriptionManager
        self.patient = patient
        self.circleId = circleId
        self.appointmentPackId = appointmentPackId
    }

    // MARK: - Actions

    func loadQuestions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            questions = try await questionService.fetchQuestions(
                patientId: patient.id,
                status: .pending
            )
        } catch {
            self.error = error
        }
    }

    func generateQuestions() async {
        // Check subscription first
        let hasAccess = await subscriptionManager.hasFeature(.aiQuestionGeneration)
        guard hasAccess else {
            showUpgradePaywall = true
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let result = try await questionService.generateQuestions(
                patientId: patient.id,
                circleId: circleId,
                appointmentPackId: appointmentPackId,
                rangeDays: 30
            )

            if result.requiresUpgrade {
                questions = result.questions
                analysisContext = result.analysisContext
                showUpgradePaywall = true
            } else {
                questions = result.questions
                analysisContext = result.analysisContext
            }
        } catch {
            self.error = error
        }
    }

    func addQuestion(
        text: String,
        category: QuestionCategory,
        priority: QuestionPriority
    ) async {
        do {
            let newQuestion = try await questionService.addQuestion(
                circleId: circleId,
                patientId: patient.id,
                questionText: text,
                category: category,
                priority: priority,
                appointmentPackId: appointmentPackId
            )

            questions.append(newQuestion)
            showAddQuestionSheet = false
        } catch {
            self.error = error
        }
    }

    func deleteQuestion(_ question: AppointmentQuestion) async {
        do {
            try await questionService.deleteQuestion(question.id)
            questions.removeAll { $0.id == question.id }
        } catch {
            self.error = error
        }
    }

    func reorderQuestions(_ reorderedQuestions: [AppointmentQuestion]) async {
        // Store original for rollback
        let originalQuestions = self.questions
        
        // Optimistic update
        self.questions = reorderedQuestions
        
        do {
            try await questionService.reorderQuestions(reorderedQuestions)
        } catch {
            // Rollback on failure
            self.questions = originalQuestions
            self.error = error
        }
    }

    func updateQuestionPriority(_ question: AppointmentQuestion, priority: QuestionPriority) async {
        var updated = question
        updated.priority = priority
        updated.priorityScore = priority.defaultScore  // Use extension

        do {
            try await questionService.updateQuestion(updated)
            // Thread-safe update
            if let index = questions.firstIndex(where: { $0.id == question.id }) {
                questions[index] = updated
            }
        } catch {
            self.error = error
        }
    }
}

// MARK: - Post-Appointment ViewModel

@MainActor
final class PostAppointmentViewModel: ObservableObject {
    // MARK: - Published State

    @Published var questions: [AppointmentQuestion] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: Error?

    // MARK: - Dependencies

    private let questionService: AppointmentQuestionService
    private let taskService: TaskService
    private let patient: Patient

    // MARK: - Computed Properties

    var reviewedCount: Int {
        questions.filter { $0.status != .pending }.count
    }

    var totalCount: Int {
        questions.count
    }

    var allReviewed: Bool {
        reviewedCount == totalCount && totalCount > 0
    }

    // MARK: - Initialization

    init(
        questionService: AppointmentQuestionService,
        taskService: TaskService,
        patient: Patient
    ) {
        self.questionService = questionService
        self.taskService = taskService
        self.patient = patient
    }

    // MARK: - Actions

    func loadQuestions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            questions = try await questionService.fetchQuestions(patientId: patient.id)
        } catch {
            self.error = error
        }
    }

    func markDiscussed(
        _ question: AppointmentQuestion,
        status: QuestionStatus,
        notes: String?
    ) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await questionService.markDiscussed(
                questionId: question.id,
                status: status,
                responseNotes: notes
            )

            if let index = questions.firstIndex(where: { $0.id == question.id }) {
                var updated = questions[index]
                updated.status = status
                updated.responseNotes = notes
                updated.discussedAt = Date()
                questions[index] = updated
            }
        } catch {
            self.error = error
        }
    }

    func createFollowUpTask(
        from question: AppointmentQuestion,
        dueDate: Date
    ) async {
        do {
            let task = try await questionService.createFollowUpTask(
                from: question,
                dueDate: dueDate,
                taskService: taskService
            )

            if let index = questions.firstIndex(where: { $0.id == question.id }) {
                var updated = questions[index]
                updated.followUpTaskId = task.id
                questions[index] = updated
            }
        } catch {
            self.error = error
        }
    }
}
