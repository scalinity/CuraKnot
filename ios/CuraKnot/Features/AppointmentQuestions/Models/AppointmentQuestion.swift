import Foundation
import GRDB
import SwiftUI

// MARK: - Appointment Question Model

struct AppointmentQuestion: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    var appointmentPackId: String?

    // Content
    var questionText: String
    var reasoning: String?
    var category: QuestionCategory

    // Source tracking
    let source: QuestionSource
    var sourceHandoffIds: [String]
    var sourceMedicationIds: [String]
    let createdBy: String

    // Priority
    var priority: QuestionPriority
    var priorityScore: Int

    // Status
    var status: QuestionStatus
    var sortOrder: Int

    // Post-appointment
    var responseNotes: String?
    var discussedAt: Date?
    var discussedBy: String?
    var followUpTaskId: String?

    // Timestamps
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var isHighPriority: Bool { priority == .high }
    var isAIGenerated: Bool { source == .aiGenerated }
    var isPending: Bool { status == .pending }
    var isDiscussed: Bool { status == .discussed }
    
    var hasResponseNotes: Bool {
        responseNotes?.isEmpty == false  // Fixed: Use optional chaining
    }
}

// MARK: - GRDB Conformance

extension AppointmentQuestion: FetchableRecord, PersistableRecord {
    static let databaseTableName = "appointmentQuestions"

    enum Columns: String, ColumnExpression {
        case id, circleId, patientId, appointmentPackId
        case questionText, reasoning, category
        case source, sourceHandoffIds, sourceMedicationIds, createdBy
        case priority, priorityScore, status, sortOrder
        case responseNotes, discussedAt, discussedBy, followUpTaskId
        case createdAt, updatedAt
    }
}

// MARK: - Question Category

enum QuestionCategory: String, Codable, CaseIterable {
    case symptom = "SYMPTOM"
    case medication = "MEDICATION"
    case test = "TEST"
    case carePlan = "CARE_PLAN"
    case prognosis = "PROGNOSIS"
    case sideEffect = "SIDE_EFFECT"
    case general = "GENERAL"

    var displayName: String {
        switch self {
        case .symptom: return "Symptom"
        case .medication: return "Medication"
        case .test: return "Test Results"
        case .carePlan: return "Care Plan"
        case .prognosis: return "Prognosis"
        case .sideEffect: return "Side Effect"
        case .general: return "General"
        }
    }

    var icon: String {
        switch self {
        case .symptom: return "heart.text.square"
        case .medication: return "pills"
        case .test: return "chart.bar.doc.horizontal"
        case .carePlan: return "list.clipboard"
        case .prognosis: return "calendar.badge.clock"
        case .sideEffect: return "exclamationmark.triangle"
        case .general: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .symptom: return .red
        case .medication: return .blue
        case .test: return .purple
        case .carePlan: return .green
        case .prognosis: return .orange
        case .sideEffect: return .yellow
        case .general: return .gray
        }
    }
}

// MARK: - Question Source

enum QuestionSource: String, Codable {
    case aiGenerated = "AI_GENERATED"
    case userAdded = "USER_ADDED"
    case template = "TEMPLATE"

    var displayName: String {
        switch self {
        case .aiGenerated: return "AI Suggested"
        case .userAdded: return "Added by you"
        case .template: return "Template"
        }
    }

    var icon: String {
        switch self {
        case .aiGenerated: return "sparkles"
        case .userAdded: return "person.fill"
        case .template: return "doc.text"
        }
    }

    var color: Color {
        switch self {
        case .aiGenerated: return .purple
        case .userAdded: return .blue
        case .template: return .gray
        }
    }
}

// MARK: - Question Priority

enum QuestionPriority: String, Codable, CaseIterable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    var icon: String {
        switch self {
        case .high: return "exclamationmark.3"
        case .medium: return "exclamationmark.2"
        case .low: return "exclamationmark"
        }
    }
}

// MARK: - Question Status

enum QuestionStatus: String, Codable, CaseIterable {
    case pending = "PENDING"
    case discussed = "DISCUSSED"
    case notDiscussed = "NOT_DISCUSSED"
    case deferred = "DEFERRED"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .discussed: return "Discussed"
        case .notDiscussed: return "Not Discussed"
        case .deferred: return "Deferred"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .discussed: return "checkmark.circle.fill"
        case .notDiscussed: return "xmark.circle"
        case .deferred: return "arrow.clockwise"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .gray
        case .discussed: return .green
        case .notDiscussed: return .red
        case .deferred: return .orange
        }
    }
}

// MARK: - API Response Types

struct GenerateQuestionsResponse: Decodable {
    let success: Bool
    let questions: [GeneratedQuestionDTO]
    let analysisContext: AnalysisContext
    let subscriptionStatus: SubscriptionStatus

    enum CodingKeys: String, CodingKey {
        case success, questions
        case analysisContext = "analysis_context"
        case subscriptionStatus = "subscription_status"
    }
}

struct GeneratedQuestionDTO: Decodable {
    let id: String
    let questionText: String
    let reasoning: String
    let category: String
    let source: String
    let sourceHandoffIds: [String]
    let sourceMedicationIds: [String]
    let priority: String
    let priorityScore: Int

    enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case reasoning
        case category
        case source
        case sourceHandoffIds = "source_handoff_ids"
        case sourceMedicationIds = "source_medication_ids"
        case priority
        case priorityScore = "priority_score"
    }

    func toAppointmentQuestion(
        circleId: String,
        patientId: String,
        createdBy: String,
        appointmentPackId: String?
    ) -> AppointmentQuestion {
        AppointmentQuestion(
            id: id,
            circleId: circleId,
            patientId: patientId,
            appointmentPackId: appointmentPackId,
            questionText: questionText,
            reasoning: reasoning,
            category: QuestionCategory(rawValue: category) ?? .general,
            source: QuestionSource(rawValue: source) ?? .template,
            sourceHandoffIds: sourceHandoffIds,
            sourceMedicationIds: sourceMedicationIds,
            createdBy: createdBy,
            priority: QuestionPriority(rawValue: priority) ?? .medium,
            priorityScore: priorityScore,
            status: .pending,
            sortOrder: 0,
            responseNotes: nil,
            discussedAt: nil,
            discussedBy: nil,
            followUpTaskId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

struct AnalysisContext: Decodable {
    let handoffsAnalyzed: Int
    let dateRange: DateRange
    let patternsDetected: PatternsDetected
    let templateQuestionsAdded: Int

    enum CodingKeys: String, CodingKey {
        case handoffsAnalyzed = "handoffs_analyzed"
        case dateRange = "date_range"
        case patternsDetected = "patterns_detected"
        case templateQuestionsAdded = "template_questions_added"
    }
}

struct DateRange: Decodable {
    let start: String
    let end: String
}

struct PatternsDetected: Decodable {
    let repeatedSymptoms: [RepeatedSymptom]
    let medicationChanges: [MedicationChange]
    let potentialSideEffects: [PotentialSideEffect]

    enum CodingKeys: String, CodingKey {
        case repeatedSymptoms = "repeated_symptoms"
        case medicationChanges = "medication_changes"
        case potentialSideEffects = "potential_side_effects"
    }
}

struct RepeatedSymptom: Decodable {
    let symptom: String
    let count: Int
    let lastMentioned: String

    enum CodingKeys: String, CodingKey {
        case symptom, count
        case lastMentioned = "last_mentioned"
    }
}

struct MedicationChange: Decodable {
    let medicationId: String
    let medicationName: String
    let changeType: String
    let changedAt: String

    enum CodingKeys: String, CodingKey {
        case medicationId = "medication_id"
        case medicationName = "medication_name"
        case changeType = "change_type"
        case changedAt = "changed_at"
    }
}

struct PotentialSideEffect: Decodable {
    let medicationId: String
    let medicationName: String
    let symptom: String
    let correlationScore: Double

    enum CodingKeys: String, CodingKey {
        case medicationId = "medication_id"
        case medicationName = "medication_name"
        case symptom
        case correlationScore = "correlation_score"
    }
}

struct SubscriptionStatus: Decodable {
    let plan: String
    let hasAccess: Bool
    let previewOnly: Bool

    enum CodingKeys: String, CodingKey {
        case plan
        case hasAccess = "has_access"
        case previewOnly = "preview_only"
    }
}

// MARK: - Request Types

struct GenerateQuestionsRequest: Encodable {
    let patientId: String
    let circleId: String
    let appointmentPackId: String?
    let appointmentDate: String?
    let rangeDays: Int
    let maxQuestions: Int

    enum CodingKeys: String, CodingKey {
        case patientId = "patient_id"
        case circleId = "circle_id"
        case appointmentPackId = "appointment_pack_id"
        case appointmentDate = "appointment_date"
        case rangeDays = "range_days"
        case maxQuestions = "max_questions"
    }
}
