import Foundation
import GRDB

// MARK: - Appointment Question Service

class AppointmentQuestionService {
    let databaseManager: DatabaseManager
    let supabaseClient: SupabaseClient
    let syncCoordinator: SyncCoordinator
    let authManager: AuthManager

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        syncCoordinator: SyncCoordinator,
        authManager: AuthManager
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.syncCoordinator = syncCoordinator
        self.authManager = authManager
    }
}

// MARK: - Service Implementation

extension AppointmentQuestionService {
    // MARK: - Generate Questions

    func generateQuestions(
        patientId: String,
        circleId: String,
        appointmentPackId: String? = nil,
        appointmentDate: Date? = nil,
        rangeDays: Int = 30,
        maxQuestions: Int = 10
    ) async throws -> GenerateQuestionsResult {
        guard let userId = await getCurrentUserId() else {
            throw AppointmentQuestionError.notAuthenticated
        }

        let request = GenerateQuestionsRequest(
            patientId: patientId,
            circleId: circleId,
            appointmentPackId: appointmentPackId,
            appointmentDate: appointmentDate?.ISO8601Format(),
            rangeDays: rangeDays,
            maxQuestions: maxQuestions
        )

        let response: GenerateQuestionsResponse = try await supabaseClient
            .functions("generate-appointment-questions")
            .invoke(body: request)

        // Check subscription status
        if response.subscriptionStatus.previewOnly {
            return GenerateQuestionsResult(
                questions: response.questions.map { dto in
                    dto.toAppointmentQuestion(
                        circleId: circleId,
                        patientId: patientId,
                        createdBy: userId,
                        appointmentPackId: appointmentPackId
                    )
                },
                analysisContext: response.analysisContext,
                requiresUpgrade: true
            )
        }

        // Convert DTOs to models
        let questions = response.questions.enumerated().map { index, dto in
            var question = dto.toAppointmentQuestion(
                circleId: circleId,
                patientId: patientId,
                createdBy: userId,
                appointmentPackId: appointmentPackId
            )
            question.sortOrder = index
            return question
        }

        // Save to local database
        try await saveQuestionsLocally(questions)

        return GenerateQuestionsResult(
            questions: questions,
            analysisContext: response.analysisContext,
            requiresUpgrade: false
        )
    }

    // MARK: - CRUD Operations

    func fetchQuestions(
        patientId: String,
        status: QuestionStatus? = nil
    ) async throws -> [AppointmentQuestion] {
        try databaseManager.read { db in
            var query = AppointmentQuestion
                .filter(Column("patientId") == patientId)
                .order(Column("priorityScore").desc)
                .order(Column("sortOrder"))

            if let status = status {
                query = query.filter(Column("status") == status.rawValue)
            }

            return try query.fetchAll(db)
        }
    }

    func fetchQuestionsForPack(appointmentPackId: String) async throws -> [AppointmentQuestion] {
        try databaseManager.read { db in
            try AppointmentQuestion
                .filter(Column("appointmentPackId") == appointmentPackId)
                .order(Column("priorityScore").desc)
                .order(Column("sortOrder"))
                .fetchAll(db)
        }
    }

    // MARK: - Add Question (Fixed: Calculate sortOrder correctly)
    
    func addQuestion(
        circleId: String,
        patientId: String,
        questionText: String,
        category: QuestionCategory,
        priority: QuestionPriority,
        appointmentPackId: String? = nil
    ) async throws -> AppointmentQuestion {
        guard let userId = await getCurrentUserId() else {
            throw AppointmentQuestionError.notAuthenticated
        }
        
        // Validate question length
        let trimmedText = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count >= 10, trimmedText.count <= 500 else {
            throw AppointmentQuestionError.invalidQuestionLength
        }
        
        // Calculate next sort order
        let existingQuestions = try await fetchQuestions(patientId: patientId)
        let maxSortOrder = existingQuestions.max(by: { $0.sortOrder < $1.sortOrder })?.sortOrder ?? -1
        
        let question = AppointmentQuestion(
            id: UUID().uuidString.lowercased(),  // Standardize to lowercase
            circleId: circleId,
            patientId: patientId,
            appointmentPackId: appointmentPackId,
            questionText: trimmedText,
            reasoning: nil,
            category: category,
            source: .userAdded,
            sourceHandoffIds: [],
            sourceMedicationIds: [],
            createdBy: userId,
            priority: priority,
            priorityScore: priority.defaultScore,  // Use extension
            status: .pending,
            sortOrder: maxSortOrder + 1,  // Fixed: Correct sort order
            responseNotes: nil,
            discussedAt: nil,
            discussedBy: nil,
            followUpTaskId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save locally
        try databaseManager.write { db in
            try question.save(db)
        }

        // Enqueue for sync
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "INSERT",
            entityType: "appointment_questions",
            entityId: question.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(question), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))

        return question
    }

    func updateQuestion(_ question: AppointmentQuestion) async throws {
        var updated = question
        updated.updatedAt = Date()

        try databaseManager.write { db in
            try updated.update(db)
        }

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "appointment_questions",
            entityId: question.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(updated), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    func deleteQuestion(_ questionId: String) async throws {
        _ = try databaseManager.write { db in
            try AppointmentQuestion
                .filter(Column("id") == questionId)
                .deleteAll(db)
        }

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "DELETE",
            entityType: "appointment_questions",
            entityId: questionId,
            payloadJson: "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    // MARK: - Reorder Questions (Fixed: Batch writes in single transaction)
    
    func reorderQuestions(_ questions: [AppointmentQuestion]) async throws {
        let now = Date()
        let updates = questions.enumerated().map { index, question -> AppointmentQuestion in
            var updated = question
            updated.sortOrder = index
            updated.updatedAt = now
            return updated
        }
        
        // Single transaction for all updates
        try databaseManager.write { db in
            for updated in updates {
                try updated.update(db)
            }
        }
        
        // Batch sync operation
        struct ReorderPayload: Encodable {
            let id: String
            let sortOrder: Int

            enum CodingKeys: String, CodingKey {
                case id
                case sortOrder = "sort_order"
            }
        }
        let updateData = updates.map { ReorderPayload(id: $0.id, sortOrder: $0.sortOrder) }
        let batchData = try JSONEncoder.supabase.encode(updateData)
        let batchPayload = String(data: batchData, encoding: .utf8) ?? "[]"
        
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "BATCH_UPDATE",
            entityType: "appointment_questions",
            entityId: "reorder_\(UUID().uuidString)",
            payloadJson: batchPayload,
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    // MARK: - Post-Appointment

    func markDiscussed(
        questionId: String,
        status: QuestionStatus,
        responseNotes: String?
    ) async throws {
        guard let userId = await getCurrentUserId() else {
            throw AppointmentQuestionError.notAuthenticated
        }

        guard var question = try await fetchQuestion(questionId) else {
            throw AppointmentQuestionError.notFound
        }

        question.status = status
        question.responseNotes = responseNotes
        question.discussedAt = Date()
        question.discussedBy = userId
        question.updatedAt = Date()

        try databaseManager.write { db in
            try question.update(db)
        }

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "appointment_questions",
            entityId: question.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(question), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    func createFollowUpTask(
        from question: AppointmentQuestion,
        dueDate: Date,
        taskService: TaskService
    ) async throws -> CareTask {
        guard let userId = await getCurrentUserId() else {
            throw AppointmentQuestionError.notAuthenticated
        }

        let taskPriority: CareTask.Priority
        switch question.priority {
        case .high: taskPriority = .high
        case .medium: taskPriority = .med
        case .low: taskPriority = .low
        }

        let task = try await taskService.createTask(
            circleId: question.circleId,
            patientId: question.patientId,
            handoffId: nil,
            title: "Follow up: \(question.questionText.prefix(50))...",
            description: question.responseNotes ?? question.questionText,
            dueAt: dueDate,
            priority: taskPriority,
            assigneeId: userId,
            reminder: nil
        )

        // Link task to question
        var updatedQuestion = question
        updatedQuestion.followUpTaskId = task.id
        try await updateQuestion(updatedQuestion)

        return task
    }

    // MARK: - Private Helpers

    private func saveQuestionsLocally(_ questions: [AppointmentQuestion]) async throws {
        try databaseManager.write { db in
            for question in questions {
                try question.save(db)
            }
        }
    }

    private func fetchQuestion(_ questionId: String) async throws -> AppointmentQuestion? {
        try databaseManager.read { db in
            try AppointmentQuestion
                .filter(Column("id") == questionId)
                .fetchOne(db)
        }
    }

    private func getCurrentUserId() async -> String? {
        await MainActor.run {
            authManager.currentUser?.id
        }
    }
}

// MARK: - Priority Score Extension

extension QuestionPriority {
    /// Default score aligned with Edge Function thresholds
    /// HIGH: 6-10 → score 8
    /// MEDIUM: 3-5 → score 4  
    /// LOW: 0-2 → score 1
    var defaultScore: Int {
        switch self {
        case .high: return 8
        case .medium: return 4
        case .low: return 1
        }
    }
}

// MARK: - Result Types

struct GenerateQuestionsResult {
    let questions: [AppointmentQuestion]
    let analysisContext: AnalysisContext
    let requiresUpgrade: Bool
}

// MARK: - Errors

enum AppointmentQuestionError: Error, LocalizedError {
    case notAuthenticated
    case notFound
    case permissionDenied
    case invalidQuestionLength
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in"
        case .notFound:
            return "Question not found"
        case .permissionDenied:
            return "You don't have permission for this action"
        case .invalidQuestionLength:
            return "Question must be between 10 and 500 characters"
        case .networkError(let message):
            return message
        }
    }
}
