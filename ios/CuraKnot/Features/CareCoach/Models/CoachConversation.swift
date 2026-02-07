import Foundation
import GRDB

// MARK: - Coach Conversation

struct CoachConversation: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let userId: String
    var patientId: String?
    var title: String?
    var status: Status
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Status

    enum Status: String, Codable {
        case active = "ACTIVE"
        case archived = "ARCHIVED"
    }

    // MARK: - Computed Properties

    var isActive: Bool {
        status == .active
    }

    var displayTitle: String {
        title ?? "New Conversation"
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case patientId = "patient_id"
        case title
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - GRDB Conformance

extension CoachConversation: FetchableRecord, PersistableRecord {
    static let databaseTableName = "coach_conversations"
}

// MARK: - Coach Message

struct CoachMessage: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let role: Role
    let content: String
    var contextHandoffIds: [String]?
    var contextBinderIds: [String]?
    var contextSnapshotJson: String?
    var actionsJson: String?
    var isBookmarked: Bool
    var feedback: Feedback?
    var tokensUsed: Int?
    var latencyMs: Int?
    var modelVersion: String?
    let createdAt: Date

    // MARK: - Role

    enum Role: String, Codable {
        case user = "USER"
        case assistant = "ASSISTANT"
        case system = "SYSTEM"
    }

    // MARK: - Feedback

    enum Feedback: String, Codable {
        case helpful = "HELPFUL"
        case notHelpful = "NOT_HELPFUL"
    }

    // MARK: - Computed Properties

    var isFromUser: Bool {
        role == .user
    }

    var isFromAssistant: Bool {
        role == .assistant
    }

    var actions: [CoachAction] {
        guard let json = actionsJson,
              let data = json.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([CoachAction].self, from: data)) ?? []
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role
        case content
        case contextHandoffIds = "context_handoff_ids"
        case contextBinderIds = "context_binder_ids"
        case contextSnapshotJson = "context_snapshot_json"
        case actionsJson = "actions_json"
        case isBookmarked = "is_bookmarked"
        case feedback
        case tokensUsed = "tokens_used"
        case latencyMs = "latency_ms"
        case modelVersion = "model_version"
        case createdAt = "created_at"
    }
}

// MARK: - GRDB Conformance

extension CoachMessage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "coach_messages"
}

// MARK: - Coach Action

struct CoachAction: Codable, Equatable, Identifiable {
    var id: String { "\(type.rawValue)-\(label)" }
    let type: ActionType
    let label: String
    let prefillData: [String: String]?

    enum ActionType: String, Codable {
        case createTask = "CREATE_TASK"
        case addQuestion = "ADD_QUESTION"
        case updateBinder = "UPDATE_BINDER"
        case callContact = "CALL_CONTACT"

        var icon: String {
            switch self {
            case .createTask: return "checkmark.circle"
            case .addQuestion: return "questionmark.circle"
            case .updateBinder: return "folder.badge.plus"
            case .callContact: return "phone"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case label
        case prefillData = "prefill_data"
    }
}

// MARK: - Coach Usage Info

struct CoachUsageInfo: Codable, Equatable {
    let plan: String
    let allowed: Bool
    let used: Int
    let limit: Int?
    let unlimited: Bool
    let remaining: Int?

    var displayRemaining: String {
        if unlimited {
            return "Unlimited"
        }
        guard let remaining = remaining, let limit = limit else {
            return "No access"
        }
        return "\(remaining) of \(limit) remaining"
    }

    var percentUsed: Double {
        guard let limit = limit, limit > 0 else {
            return 0
        }
        return Double(used) / Double(limit)
    }
}

// MARK: - Coach Suggestion

struct CoachSuggestion: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    var patientId: String?
    let userId: String
    let suggestionType: SuggestionType
    let title: String
    let content: String
    var contextJson: String?
    var status: Status
    var actionedAt: Date?
    var dismissedAt: Date?
    var expiresAt: Date?
    let createdAt: Date

    enum SuggestionType: String, Codable, CaseIterable {
        case trendAlert = "TREND_ALERT"
        case appointmentPrep = "APPOINTMENT_PREP"
        case wellnessCheck = "WELLNESS_CHECK"
        case followup = "FOLLOWUP"

        var icon: String {
            switch self {
            case .trendAlert: return "chart.line.uptrend.xyaxis"
            case .appointmentPrep: return "calendar.badge.clock"
            case .wellnessCheck: return "heart.text.square"
            case .followup: return "arrow.uturn.forward"
            }
        }

        var displayName: String {
            switch self {
            case .trendAlert: return "Trend Alert"
            case .appointmentPrep: return "Appointment Prep"
            case .wellnessCheck: return "Wellness Check"
            case .followup: return "Follow Up"
            }
        }
    }

    enum Status: String, Codable {
        case pending = "PENDING"
        case viewed = "VIEWED"
        case dismissed = "DISMISSED"
        case actioned = "ACTIONED"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case userId = "user_id"
        case suggestionType = "suggestion_type"
        case title
        case content
        case contextJson = "context_json"
        case status
        case actionedAt = "actioned_at"
        case dismissedAt = "dismissed_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

// MARK: - Chat Response

struct CoachChatResponse: Codable {
    let success: Bool
    let conversationId: String?
    let messageId: String?
    let content: String?
    let actions: [CoachAction]?
    let disclaimer: String?
    let suggestedFollowups: [String]?
    let usageInfo: CoachUsageInfo?
    let contextReferences: [String]?
    let error: CoachError?

    struct CoachError: Codable {
        let code: String
        let message: String
    }

    enum CodingKeys: String, CodingKey {
        case success
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case content
        case actions
        case disclaimer
        case suggestedFollowups = "suggested_followups"
        case usageInfo = "usage_info"
        case contextReferences = "context_references"
        case error
    }
}

// MARK: - Chat Request

struct CoachChatRequest: Codable {
    let conversationId: String?
    let message: String
    let patientId: String?
    let circleId: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case message
        case patientId = "patient_id"
        case circleId = "circle_id"
    }
}
