import Foundation
import GRDB

// MARK: - iCal Feed Token Model

/// Secret token for read-only iCal subscription feeds
struct ICalFeedToken: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let createdBy: String

    // Token
    let token: String

    // Display name
    var feedName: String?

    // Feed configuration
    var includeTasks: Bool
    var includeShifts: Bool
    var includeAppointments: Bool
    var includeHandoffFollowups: Bool

    // Patient filtering
    var patientIds: [String]?

    // Privacy
    var showMinimalDetails: Bool

    // Lookahead window
    var lookaheadDays: Int

    // Access control
    var expiresAt: Date?
    var revokedAt: Date?

    // Analytics
    var accessCount: Int
    var lastAccessedAt: Date?

    // Timestamps
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var isActive: Bool {
        guard revokedAt == nil else { return false }
        if let expiry = expiresAt {
            return expiry > Date()
        }
        return true
    }

    var isExpired: Bool {
        guard let expiry = expiresAt else { return false }
        return expiry < Date()
    }

    var isRevoked: Bool {
        revokedAt != nil
    }

    var feedURL: URL? {
        // Use Configuration for base URL - supports local dev and production
        let baseURLString = Configuration.supabaseURL.absoluteString
        let feedEndpoint = "\(baseURLString)/functions/v1/ical-feed/\(token)"
        return URL(string: feedEndpoint)
    }

    var displayName: String {
        feedName ?? "iCal Feed"
    }

    var statusText: String {
        if isRevoked {
            return "Revoked"
        } else if isExpired {
            return "Expired"
        } else {
            return "Active"
        }
    }

    var accessCountFormatted: String {
        if accessCount == 0 {
            return "Never accessed"
        } else if accessCount == 1 {
            return "Accessed once"
        } else {
            return "Accessed \(accessCount) times"
        }
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        circleId: String,
        createdBy: String,
        token: String = ICalFeedToken.generateToken(),
        feedName: String? = nil,
        includeTasks: Bool = true,
        includeShifts: Bool = true,
        includeAppointments: Bool = true,
        includeHandoffFollowups: Bool = false,
        patientIds: [String]? = nil,
        showMinimalDetails: Bool = false,
        lookaheadDays: Int = 90,
        expiresAt: Date? = nil,
        revokedAt: Date? = nil,
        accessCount: Int = 0,
        lastAccessedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.circleId = circleId
        self.createdBy = createdBy
        self.token = token
        self.feedName = feedName
        self.includeTasks = includeTasks
        self.includeShifts = includeShifts
        self.includeAppointments = includeAppointments
        self.includeHandoffFollowups = includeHandoffFollowups
        self.patientIds = patientIds
        self.showMinimalDetails = showMinimalDetails
        self.lookaheadDays = lookaheadDays
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.accessCount = accessCount
        self.lastAccessedAt = lastAccessedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Token Generation

    /// Generates a cryptographically secure token (32 bytes, base64url encoded)
    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - GRDB Conformance

extension ICalFeedToken: FetchableRecord, PersistableRecord {
    static let databaseTableName = "ical_feed_tokens"

    // CodingKeys for snake_case database column mapping
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case createdBy = "created_by"
        case token
        case feedName = "feed_name"
        case includeTasks = "include_tasks"
        case includeShifts = "include_shifts"
        case includeAppointments = "include_appointments"
        case includeHandoffFollowups = "include_handoff_followups"
        case patientIds = "patient_ids"
        case showMinimalDetails = "show_minimal_details"
        case lookaheadDays = "lookahead_days"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
        case accessCount = "access_count"
        case lastAccessedAt = "last_accessed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Column references for GRDB queries
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let circleId = Column(CodingKeys.circleId)
        static let createdBy = Column(CodingKeys.createdBy)
        static let token = Column(CodingKeys.token)
        static let feedName = Column(CodingKeys.feedName)
        static let includeTasks = Column(CodingKeys.includeTasks)
        static let includeShifts = Column(CodingKeys.includeShifts)
        static let includeAppointments = Column(CodingKeys.includeAppointments)
        static let includeHandoffFollowups = Column(CodingKeys.includeHandoffFollowups)
        static let patientIds = Column(CodingKeys.patientIds)
        static let showMinimalDetails = Column(CodingKeys.showMinimalDetails)
        static let lookaheadDays = Column(CodingKeys.lookaheadDays)
        static let expiresAt = Column(CodingKeys.expiresAt)
        static let revokedAt = Column(CodingKeys.revokedAt)
        static let accessCount = Column(CodingKeys.accessCount)
        static let lastAccessedAt = Column(CodingKeys.lastAccessedAt)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Supabase Encoding

extension ICalFeedToken {
    /// Patient IDs stored as JSON string in local DB
    var patientIdsJson: String? {
        guard let patientIds = patientIds else { return nil }
        return try? String(data: JSONEncoder().encode(patientIds), encoding: .utf8)
    }

    /// Creates a dictionary for Supabase insert
    func toSupabasePayload() -> [String: Any?] {
        [
            "id": id,
            "circle_id": circleId,
            "created_by": createdBy,
            "token": token,
            "feed_name": feedName,
            "include_tasks": includeTasks,
            "include_shifts": includeShifts,
            "include_appointments": includeAppointments,
            "include_handoff_followups": includeHandoffFollowups,
            "patient_ids": patientIds,
            "show_minimal_details": showMinimalDetails,
            "lookahead_days": lookaheadDays,
            "expires_at": expiresAt?.ISO8601Format(),
        ]
    }
}
