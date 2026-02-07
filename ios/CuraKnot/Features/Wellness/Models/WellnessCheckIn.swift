import Foundation
import GRDB

// MARK: - Wellness Check-In Model

/// Weekly wellness check-in (USER-PRIVATE)
/// Privacy: Only the user who created it can access this data
struct WellnessCheckIn: Codable, Identifiable, Equatable {
    let id: String
    let userId: String

    // Check-in responses
    var stressLevel: Int          // 1-5 (1=low stress, 5=high stress)
    var sleepQuality: Int         // 1-5 (1=poor, 5=excellent)
    var capacityLevel: Int        // 1-4 (1=empty, 4=full)

    // Encrypted notes (AES-256-GCM)
    var notesEncrypted: String?
    var notesNonce: String?
    var notesTag: String?

    // Calculated scores (0-100)
    var wellnessScore: Int?
    var behavioralScore: Int?
    var totalScore: Int?

    // Metadata
    var weekStart: Date           // Start of the check-in week (Monday)
    var skipped: Bool
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var riskLevel: RiskLevel {
        guard let score = totalScore else { return .unknown }
        if score >= 70 { return .low }
        if score >= 40 { return .moderate }
        return .high
    }

    var stressEmoji: String {
        switch stressLevel {
        case 1: return "😌"
        case 2: return "😐"
        case 3: return "😟"
        case 4: return "😰"
        case 5: return "😫"
        default: return "❓"
        }
    }

    var sleepEmoji: String {
        switch sleepQuality {
        case 1: return "💀"
        case 2: return "😵"
        case 3: return "😶"
        case 4: return "🥱"
        case 5: return "😴"
        default: return "❓"
        }
    }

    var capacityEmoji: String {
        switch capacityLevel {
        case 1: return "🫠"
        case 2: return "🤏"
        case 3: return "✋"
        case 4: return "💪"
        default: return "❓"
        }
    }

    var formattedWeekRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: weekStart)

        guard let endDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) else {
            return "Week of \(startStr)"
        }
        let endStr = formatter.string(from: endDate)
        return "\(startStr) - \(endStr)"
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        userId: String,
        stressLevel: Int,
        sleepQuality: Int,
        capacityLevel: Int,
        notesEncrypted: String? = nil,
        notesNonce: String? = nil,
        notesTag: String? = nil,
        wellnessScore: Int? = nil,
        behavioralScore: Int? = nil,
        totalScore: Int? = nil,
        weekStart: Date = WellnessCheckIn.currentWeekStart(),
        skipped: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.stressLevel = stressLevel
        self.sleepQuality = sleepQuality
        self.capacityLevel = capacityLevel
        self.notesEncrypted = notesEncrypted
        self.notesNonce = notesNonce
        self.notesTag = notesTag
        self.wellnessScore = wellnessScore
        self.behavioralScore = behavioralScore
        self.totalScore = totalScore
        self.weekStart = weekStart
        self.skipped = skipped
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Helper Methods

    /// Get the Monday of the current week
    static func currentWeekStart() -> Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1 = Sunday, 2 = Monday, etc.
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: today)) ?? today
    }
}

// MARK: - Risk Level

enum RiskLevel: String, Codable {
    case low = "LOW"
    case moderate = "MODERATE"
    case high = "HIGH"
    case unknown = "UNKNOWN"

    var color: String {
        switch self {
        case .low: return "green"
        case .moderate: return "yellow"
        case .high: return "red"
        case .unknown: return "gray"
        }
    }

    var displayText: String {
        switch self {
        case .low: return "Good"
        case .moderate: return "Moderate"
        case .high: return "Needs attention"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - GRDB Conformance

extension WellnessCheckIn: FetchableRecord, PersistableRecord {
    static let databaseTableName = "wellness_checkins"

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case stressLevel = "stress_level"
        case sleepQuality = "sleep_quality"
        case capacityLevel = "capacity_level"
        case notesEncrypted = "notes_encrypted"
        case notesNonce = "notes_nonce"
        case notesTag = "notes_tag"
        case wellnessScore = "wellness_score"
        case behavioralScore = "behavioral_score"
        case totalScore = "total_score"
        case weekStart = "week_start"
        case skipped
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let userId = Column(CodingKeys.userId)
        static let stressLevel = Column(CodingKeys.stressLevel)
        static let sleepQuality = Column(CodingKeys.sleepQuality)
        static let capacityLevel = Column(CodingKeys.capacityLevel)
        static let wellnessScore = Column(CodingKeys.wellnessScore)
        static let totalScore = Column(CodingKeys.totalScore)
        static let weekStart = Column(CodingKeys.weekStart)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
