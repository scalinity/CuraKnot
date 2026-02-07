import Foundation
import GRDB

// MARK: - Wellness Alert Model

/// Burnout alert with delegation suggestions (USER-PRIVATE)
/// Privacy: Suggestions come from CIRCLE MEMBERSHIP, not wellness scores
struct WellnessAlert: Codable, Identifiable, Equatable {
    let id: String
    let userId: String

    // Alert data
    var riskLevel: AlertRiskLevel
    var alertType: AlertType
    var title: String
    var message: String

    // Delegation suggestions (from circle membership, NOT wellness data)
    var delegationSuggestions: [DelegationSuggestion]?

    // Status
    var status: AlertStatus
    var dismissedAt: Date?

    // Metadata
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var isActive: Bool {
        status == .active
    }

    var iconName: String {
        switch riskLevel {
        case .high: return "exclamationmark.triangle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        userId: String,
        riskLevel: AlertRiskLevel,
        alertType: AlertType,
        title: String,
        message: String,
        delegationSuggestions: [DelegationSuggestion]? = nil,
        status: AlertStatus = .active,
        dismissedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.riskLevel = riskLevel
        self.alertType = alertType
        self.title = title
        self.message = message
        self.delegationSuggestions = delegationSuggestions
        self.status = status
        self.dismissedAt = dismissedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Supporting Types

enum AlertRiskLevel: String, Codable {
    case low = "LOW"
    case moderate = "MODERATE"
    case high = "HIGH"

    var color: String {
        switch self {
        case .low: return "green"
        case .moderate: return "yellow"
        case .high: return "red"
        }
    }
}

enum AlertType: String, Codable {
    case burnoutRisk = "BURNOUT_RISK"
    case trendDecline = "TREND_DECLINE"
    case missedCheckIn = "MISSED_CHECKIN"
}

enum AlertStatus: String, Codable {
    case active = "ACTIVE"
    case dismissed = "DISMISSED"
    case resolved = "RESOLVED"
}

/// Delegation suggestion from circle membership
/// Privacy: Names come from circle_members table, NOT from comparing wellness scores
struct DelegationSuggestion: Codable, Identifiable, Equatable {
    let userId: String
    let fullName: String
    var circleName: String?

    var id: String { userId }
}

// MARK: - GRDB Conformance

extension WellnessAlert: FetchableRecord, PersistableRecord {
    static let databaseTableName = "wellness_alerts"

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case riskLevel = "risk_level"
        case alertType = "alert_type"
        case title
        case message
        case delegationSuggestions = "delegation_suggestions"
        case status
        case dismissedAt = "dismissed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let userId = Column(CodingKeys.userId)
        static let status = Column(CodingKeys.status)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
