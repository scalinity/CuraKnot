import Foundation

// MARK: - Watch Transfer Models
// Lightweight Codable models for WatchConnectivity transfer between iPhone and Watch

// MARK: - Watch Handoff

struct WatchHandoff: Codable, Identifiable, Equatable {
    let id: String
    let patientId: String
    let title: String
    let summary: String?
    let type: String
    let publishedAt: Date?
    let createdByName: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case title
        case summary
        case type
        case publishedAt = "published_at"
        case createdByName = "created_by_name"
        case createdAt = "created_at"
    }
}

// MARK: - Watch Task

struct WatchTask: Codable, Identifiable, Equatable {
    let id: String
    let patientId: String?
    let title: String
    let description: String?
    let dueAt: Date?
    let priority: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case title
        case description
        case dueAt = "due_at"
        case priority
        case status
    }

    var isOpen: Bool {
        status == "OPEN"
    }

    var isOverdue: Bool {
        guard let dueAt = dueAt, isOpen else { return false }
        return Date() > dueAt
    }

    var isDueSoon: Bool {
        guard let dueAt = dueAt, isOpen else { return false }
        let now = Date()
        let twentyFourHours: TimeInterval = 24 * 60 * 60
        // Include tasks due right now (>= instead of >) - CA1 fix
        return dueAt >= now && dueAt.timeIntervalSince(now) <= twentyFourHours
    }

    var priorityIcon: String {
        switch priority {
        case "HIGH": return "exclamationmark.circle.fill"
        case "MED": return "minus.circle.fill"
        default: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Watch Emergency Card

struct WatchEmergencyCard: Codable, Equatable {
    let patientId: String
    let patientName: String
    let initials: String?
    let dateOfBirth: Date?
    let bloodType: String?
    let allergies: [String]
    let conditions: [String]
    let medications: [WatchMedication]
    let emergencyContacts: [WatchContact]
    let physician: WatchContact?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case patientId = "patient_id"
        case patientName = "patient_name"
        case initials
        case dateOfBirth = "date_of_birth"
        case bloodType = "blood_type"
        case allergies
        case conditions
        case medications
        case emergencyContacts = "emergency_contacts"
        case physician
        case notes
    }

    var displayInitials: String {
        if let initials = initials, !initials.isEmpty {
            return initials
        }
        let components = patientName.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        let fallback = String(patientName.prefix(2)).uppercased()
        return fallback.isEmpty ? "??" : fallback  // Provide fallback for empty names (CA1 fix)
    }
}

// MARK: - Watch Medication

struct WatchMedication: Codable, Equatable, Identifiable {
    // Stable ID combining all fields to avoid collisions (rule-011)
    var id: String { "\(name)-\(dose ?? "")-\(schedule ?? "")" }
    let name: String
    let dose: String?
    let schedule: String?

    var displayText: String {
        var text = name
        if let dose = dose, !dose.isEmpty {
            text += " \(dose)"
        }
        if let schedule = schedule, !schedule.isEmpty {
            text += " - \(schedule)"
        }
        return text
    }
}

// MARK: - Watch Contact

struct WatchContact: Codable, Identifiable, Equatable {
    // Stable ID including role to avoid collisions (rule-011)
    var id: String { "\(name)-\(role ?? "")-\(phone ?? "")" }
    let name: String
    let role: String?
    let phone: String?

    var canCall: Bool {
        guard let phone = phone else { return false }
        return !phone.isEmpty
    }

    var phoneURL: URL? {
        guard let phone = phone, !phone.isEmpty else { return nil }
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)

        // Validate: must have digits, reasonable length, + only at start if present (rule-015)
        guard !cleaned.isEmpty,
              cleaned.count >= 3,
              cleaned.count <= 20,
              cleaned.contains(where: { $0.isNumber }),
              (cleaned.first != "+" || cleaned.dropFirst().allSatisfy { $0.isNumber }) else {
            return nil
        }

        return URL(string: "tel:\(cleaned)")
    }
}

// MARK: - Watch Patient

struct WatchPatient: Codable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let initials: String?

    var displayInitials: String {
        if let initials = initials, !initials.isEmpty {
            return initials
        }
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        let fallback = String(displayName.prefix(2)).uppercased()
        return fallback.isEmpty ? "??" : fallback  // Provide fallback for empty names (CA1 fix)
    }
}

// MARK: - Watch Cache Data

struct WatchCacheData: Codable {
    let subscriptionPlan: String
    let currentPatientId: String?
    let patients: [WatchPatient]
    let emergencyCard: WatchEmergencyCard?
    let todayTasks: [WatchTask]
    let recentHandoffs: [WatchHandoff]
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case subscriptionPlan = "subscription_plan"
        case currentPatientId = "current_patient_id"
        case patients
        case emergencyCard = "emergency_card"
        case todayTasks = "today_tasks"
        case recentHandoffs = "recent_handoffs"
        case timestamp
    }

    var hasWatchAccess: Bool {
        subscriptionPlan == "PLUS" || subscriptionPlan == "FAMILY"
    }
}

// MARK: - Watch Draft Metadata

struct WatchDraftMetadata: Codable {
    let patientId: String
    let circleId: String
    let createdAt: Date
    let duration: TimeInterval

    enum CodingKeys: String, CodingKey {
        case patientId = "patient_id"
        case circleId = "circle_id"
        case createdAt = "created_at"
        case duration
    }

    var dictionary: [String: Any] {
        [
            "patient_id": patientId,
            "circle_id": circleId,
            "created_at": createdAt.timeIntervalSince1970,
            "duration": duration
        ]
    }

    init(patientId: String, circleId: String, createdAt: Date, duration: TimeInterval) {
        self.patientId = patientId
        self.circleId = circleId
        self.createdAt = createdAt
        self.duration = duration
    }

    init?(from dictionary: [String: Any]) {
        guard let patientId = dictionary["patient_id"] as? String,
              let circleId = dictionary["circle_id"] as? String,
              let createdAtTimestamp = dictionary["created_at"] as? TimeInterval,
              let duration = dictionary["duration"] as? TimeInterval else {
            return nil
        }
        self.patientId = patientId
        self.circleId = circleId
        self.createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
        self.duration = duration
    }
}

// MARK: - Task Completion Request

struct WatchTaskCompletion: Codable {
    let taskId: String
    let completedAt: Date
    let completionNote: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case completedAt = "completed_at"
        case completionNote = "completion_note"
    }
}

// MARK: - Watch Message Types

enum WatchMessageType: String, Codable {
    case subscriptionUpdate = "subscription_update"
    case cacheUpdate = "cache_update"
    case taskCompleted = "task_completed"
    case voiceDraftReceived = "voice_draft_received"
    case syncRequest = "sync_request"
}

// MARK: - Watch Message

struct WatchMessage: Codable {
    let type: WatchMessageType
    let payload: Data?
    let timestamp: Date

    init(type: WatchMessageType, payload: Data? = nil) {
        self.type = type
        self.payload = payload
        self.timestamp = Date()
    }

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = payload else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
