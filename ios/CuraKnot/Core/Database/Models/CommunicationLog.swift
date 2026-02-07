import Foundation
import GRDB

// MARK: - Communication Log Model

struct CommunicationLog: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String

    // Contact info
    var facilityName: String
    var facilityId: String?
    var contactName: String
    var contactRole: [ContactRole]
    var contactPhone: String?
    var contactEmail: String?

    // Call details
    var communicationType: CommunicationType
    var callType: CallType
    var callDate: Date
    var durationMinutes: Int?
    var summary: String

    // Follow-up
    var followUpDate: Date?
    var followUpReason: String?
    var followUpStatus: FollowUpStatus
    var followUpCompletedAt: Date?
    var followUpTaskId: String?

    // Linked entities
    var linkedHandoffId: String?

    // AI suggestions (FAMILY tier)
    var aiSuggestedTasks: [SuggestedTask]?
    var aiSuggestionsAccepted: Bool

    // Status
    var resolutionStatus: ResolutionStatus

    let createdAt: Date
    var updatedAt: Date

    // MARK: - Communication Type

    enum CommunicationType: String, Codable, CaseIterable {
        case call = "CALL"
        case message = "MESSAGE"
        case email = "EMAIL"
        case inPerson = "IN_PERSON"

        var displayName: String {
            switch self {
            case .call: return "Phone Call"
            case .message: return "Message"
            case .email: return "Email"
            case .inPerson: return "In Person"
            }
        }

        var icon: String {
            switch self {
            case .call: return "phone.fill"
            case .message: return "message.fill"
            case .email: return "envelope.fill"
            case .inPerson: return "person.fill"
            }
        }
    }

    // MARK: - Call Type

    enum CallType: String, Codable, CaseIterable {
        case statusUpdate = "STATUS_UPDATE"
        case question = "QUESTION"
        case complaint = "COMPLAINT"
        case scheduling = "SCHEDULING"
        case billing = "BILLING"
        case discharge = "DISCHARGE"
        case other = "OTHER"

        var displayName: String {
            switch self {
            case .statusUpdate: return "Status Update"
            case .question: return "Question"
            case .complaint: return "Complaint"
            case .scheduling: return "Scheduling"
            case .billing: return "Billing"
            case .discharge: return "Discharge Planning"
            case .other: return "Other"
            }
        }

        var icon: String {
            switch self {
            case .statusUpdate: return "info.circle"
            case .question: return "questionmark.circle"
            case .complaint: return "exclamationmark.triangle"
            case .scheduling: return "calendar"
            case .billing: return "dollarsign.circle"
            case .discharge: return "house"
            case .other: return "ellipsis.circle"
            }
        }

        var promptText: String {
            switch self {
            case .statusUpdate: return "What was discussed? Any changes to care?"
            case .question: return "What did you ask? What was the answer?"
            case .complaint: return "What was the issue? What was their response?"
            case .scheduling: return "What was scheduled? Confirmed date/time?"
            case .billing: return "Claim/account number? Amount? Resolution?"
            case .discharge: return "Discharge date? Requirements? Next steps?"
            case .other: return "Describe the communication."
            }
        }

        var defaultFollowUpDays: Int? {
            switch self {
            case .statusUpdate: return nil
            case .question: return 3
            case .complaint: return 2
            case .scheduling: return nil
            case .billing: return 7
            case .discharge: return 1
            case .other: return nil
            }
        }
    }

    // MARK: - Contact Role

    enum ContactRole: String, Codable, CaseIterable {
        case nurse = "NURSE"
        case doctor = "DOCTOR"
        case socialWorker = "SOCIAL_WORKER"
        case admin = "ADMIN"
        case billing = "BILLING"
        case receptionist = "RECEPTIONIST"
        case therapist = "THERAPIST"
        case other = "OTHER"

        var displayName: String {
            switch self {
            case .nurse: return "Nurse"
            case .doctor: return "Doctor"
            case .socialWorker: return "Social Worker"
            case .admin: return "Administrator"
            case .billing: return "Billing"
            case .receptionist: return "Receptionist"
            case .therapist: return "Therapist"
            case .other: return "Other"
            }
        }

        var icon: String {
            switch self {
            case .nurse: return "heart.text.square"
            case .doctor: return "stethoscope"
            case .socialWorker: return "person.2"
            case .admin: return "building.2"
            case .billing: return "dollarsign.circle"
            case .receptionist: return "phone"
            case .therapist: return "figure.walk"
            case .other: return "person.crop.circle"
            }
        }
    }

    // MARK: - Follow-Up Status

    enum FollowUpStatus: String, Codable {
        case none = "NONE"
        case pending = "PENDING"
        case complete = "COMPLETE"
        case cancelled = "CANCELLED"

        var displayName: String {
            switch self {
            case .none: return "None"
            case .pending: return "Pending"
            case .complete: return "Complete"
            case .cancelled: return "Cancelled"
            }
        }
    }

    // MARK: - Resolution Status

    enum ResolutionStatus: String, Codable {
        case open = "OPEN"
        case resolved = "RESOLVED"
        case escalated = "ESCALATED"

        var displayName: String {
            switch self {
            case .open: return "Open"
            case .resolved: return "Resolved"
            case .escalated: return "Escalated"
            }
        }
    }

    // MARK: - Computed Properties

    var hasFollowUp: Bool {
        followUpDate != nil && followUpStatus == .pending
    }

    var isFollowUpOverdue: Bool {
        guard let followUpDate = followUpDate, followUpStatus == .pending else { return false }
        return Self.calendar.startOfDay(for: Date()) > Self.calendar.startOfDay(for: followUpDate)
    }

    var isFollowUpToday: Bool {
        guard let followUpDate = followUpDate, followUpStatus == .pending else { return false }
        return Self.calendar.isDateInToday(followUpDate)
    }

    // MARK: - Cached Calendar (thread-safe)

    private static let calendar = Calendar.current

    var formattedCallDate: String {
        Self.relativeDateFormatter.localizedString(for: callDate, relativeTo: Date())
    }

    var formattedDuration: String? {
        guard let minutes = durationMinutes else { return nil }
        if minutes < 60 {
            return "~\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "~\(hours) hr"
            } else {
                return "~\(hours) hr \(remainingMinutes) min"
            }
        }
    }

    var contactRolesDisplay: String {
        contactRole.map { $0.displayName }.joined(separator: ", ")
    }

    // MARK: - Cached Formatters (thread-safe)

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        circleId: String,
        patientId: String,
        createdBy: String,
        facilityName: String,
        facilityId: String? = nil,
        contactName: String,
        contactRole: [ContactRole] = [],
        contactPhone: String? = nil,
        contactEmail: String? = nil,
        communicationType: CommunicationType = .call,
        callType: CallType,
        callDate: Date = Date(),
        durationMinutes: Int? = nil,
        summary: String,
        followUpDate: Date? = nil,
        followUpReason: String? = nil,
        followUpStatus: FollowUpStatus = .none,
        followUpCompletedAt: Date? = nil,
        followUpTaskId: String? = nil,
        linkedHandoffId: String? = nil,
        aiSuggestedTasks: [SuggestedTask]? = nil,
        aiSuggestionsAccepted: Bool = false,
        resolutionStatus: ResolutionStatus = .open,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.circleId = circleId
        self.patientId = patientId
        self.createdBy = createdBy
        self.facilityName = facilityName
        self.facilityId = facilityId
        self.contactName = contactName
        self.contactRole = contactRole
        self.contactPhone = contactPhone
        self.contactEmail = contactEmail
        self.communicationType = communicationType
        self.callType = callType
        self.callDate = callDate
        self.durationMinutes = durationMinutes
        self.summary = summary
        self.followUpDate = followUpDate
        self.followUpReason = followUpReason
        self.followUpStatus = followUpStatus
        self.followUpCompletedAt = followUpCompletedAt
        self.followUpTaskId = followUpTaskId
        self.linkedHandoffId = linkedHandoffId
        self.aiSuggestedTasks = aiSuggestedTasks
        self.aiSuggestionsAccepted = aiSuggestionsAccepted
        self.resolutionStatus = resolutionStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Conformance

extension CommunicationLog: FetchableRecord, PersistableRecord {
    static let databaseTableName = "communication_logs"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let circleId = Column(CodingKeys.circleId)
        static let patientId = Column(CodingKeys.patientId)
        static let createdBy = Column(CodingKeys.createdBy)
        static let facilityName = Column(CodingKeys.facilityName)
        static let facilityId = Column(CodingKeys.facilityId)
        static let contactName = Column(CodingKeys.contactName)
        static let contactRole = Column(CodingKeys.contactRole)
        static let contactPhone = Column(CodingKeys.contactPhone)
        static let contactEmail = Column(CodingKeys.contactEmail)
        static let communicationType = Column(CodingKeys.communicationType)
        static let callType = Column(CodingKeys.callType)
        static let callDate = Column(CodingKeys.callDate)
        static let durationMinutes = Column(CodingKeys.durationMinutes)
        static let summary = Column(CodingKeys.summary)
        static let followUpDate = Column(CodingKeys.followUpDate)
        static let followUpReason = Column(CodingKeys.followUpReason)
        static let followUpStatus = Column(CodingKeys.followUpStatus)
        static let followUpCompletedAt = Column(CodingKeys.followUpCompletedAt)
        static let followUpTaskId = Column(CodingKeys.followUpTaskId)
        static let linkedHandoffId = Column(CodingKeys.linkedHandoffId)
        static let aiSuggestedTasks = Column(CodingKeys.aiSuggestedTasks)
        static let aiSuggestionsAccepted = Column(CodingKeys.aiSuggestionsAccepted)
        static let resolutionStatus = Column(CodingKeys.resolutionStatus)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - URL Helpers (for Quick Actions)

extension CommunicationLog {
    var phoneURL: URL? {
        guard let phone = contactPhone, !phone.isEmpty else { return nil }
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty, cleaned.count >= 7, cleaned.count <= 16 else { return nil }
        // CRITICAL: Ensure at least one digit exists (not just + signs)
        guard cleaned.contains(where: { $0.isNumber }) else { return nil }
        // CRITICAL: Validate + only appears at start (international prefix)
        if cleaned.contains("+") {
            guard cleaned.hasPrefix("+"), cleaned.filter({ $0 == "+" }).count == 1 else {
                return nil
            }
        }
        return URL(string: "tel:\(cleaned)")
    }

    var emailURL: URL? {
        guard let email = contactEmail, !email.isEmpty else { return nil }
        // CRITICAL: Strict RFC 5322 validation to prevent mailto: parameter injection (CWE-74)
        // Reject special characters used in mailto: URL parameters (?&=) and separators (,;)
        let emailPattern = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES[c] %@", emailPattern)
        guard emailPredicate.evaluate(with: email) else { return nil }
        // Encode for URL safety (handles @ and + characters)
        guard let encodedEmail = email.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "?&="))
        ) else { return nil }
        return URL(string: "mailto:\(encodedEmail)")
    }

    var mapsURL: URL? {
        guard !facilityName.isEmpty else { return nil }
        // CRITICAL: Remove URL parameter separators to prevent injection (CWE-74)
        let sanitized = facilityName
            .replacingOccurrences(of: "&", with: " ")
            .replacingOccurrences(of: "?", with: " ")
            .replacingOccurrences(of: "#", with: " ")
        guard !sanitized.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let encoded = sanitized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "maps://?q=\(encoded)")
    }
}

// MARK: - Suggested Task

struct SuggestedTask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var description: String?
    var priority: String
    var dueInDays: Int?
    var isAccepted: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        priority: String = "MED",
        dueInDays: Int? = nil,
        isAccepted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.dueInDays = dueInDays
        self.isAccepted = isAccepted
    }
}

// MARK: - Communication Log Group (for UI)

struct CommunicationLogGroup: Identifiable, Equatable {
    let id: String
    let date: Date
    let logs: [CommunicationLog]

    var dateHeader: String {
        if Self.calendar.isDateInToday(date) {
            return "Today"
        } else if Self.calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if Self.calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }

    // MARK: - Cached Formatter and Calendar

    private static let calendar = Calendar.current

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    // MARK: - Equatable (for efficient SwiftUI diffing)

    static func == (lhs: CommunicationLogGroup, rhs: CommunicationLogGroup) -> Bool {
        lhs.id == rhs.id && lhs.date == rhs.date && lhs.logs == rhs.logs
    }
}
