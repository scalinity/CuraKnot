import Foundation
import GRDB

// MARK: - Wellness Preferences Model

/// User preferences for wellness feature (USER-PRIVATE)
struct WellnessPreferences: Codable, Identifiable, Equatable {
    let userId: String  // Primary key in database

    // Notification preferences
    var enableBurnoutAlerts: Bool
    var enableWeeklyReminders: Bool
    var reminderDayOfWeek: Int?  // 0-6 (0=Sunday)
    var reminderTime: String?    // "HH:MM:SS" format

    // Privacy settings
    var shareCapacityWithCircle: Bool

    // Metadata
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var id: String { userId }  // For Identifiable conformance

    var formattedReminderTime: String {
        guard let time = reminderTime else { return "9:00 AM" }
        // Parse "HH:MM:SS" format
        let components = time.split(separator: ":")
        guard let hour = Int(components.first ?? "9") else { return "9:00 AM" }
        let hour12 = hour % 12
        let displayHour = hour12 == 0 ? 12 : hour12
        let period = hour < 12 ? "AM" : "PM"
        return "\(displayHour):00 \(period)"
    }

    var reminderDayName: String {
        guard let dayOfWeek = reminderDayOfWeek else { return "Sunday" }
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[min(dayOfWeek, 6)]
    }

    var reminderDescription: String {
        if !enableWeeklyReminders {
            return "Reminders disabled"
        }
        return "\(reminderDayName) at \(formattedReminderTime)"
    }

    // MARK: - Initialization

    init(
        userId: String,
        enableBurnoutAlerts: Bool = true,
        enableWeeklyReminders: Bool = true,
        reminderDayOfWeek: Int? = 0,  // Sunday
        reminderTime: String? = "09:00:00",
        shareCapacityWithCircle: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.enableBurnoutAlerts = enableBurnoutAlerts
        self.enableWeeklyReminders = enableWeeklyReminders
        self.reminderDayOfWeek = reminderDayOfWeek
        self.reminderTime = reminderTime
        self.shareCapacityWithCircle = shareCapacityWithCircle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Default Preferences

    static func defaultPreferences(for userId: String) -> WellnessPreferences {
        WellnessPreferences(userId: userId)
    }
}

// MARK: - GRDB Conformance

extension WellnessPreferences: FetchableRecord, PersistableRecord {
    static let databaseTableName = "wellness_preferences"

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case enableBurnoutAlerts = "enable_burnout_alerts"
        case enableWeeklyReminders = "enable_weekly_reminders"
        case reminderDayOfWeek = "reminder_day_of_week"
        case reminderTime = "reminder_time"
        case shareCapacityWithCircle = "share_capacity_with_circle"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let userId = Column(CodingKeys.userId)
        static let enableBurnoutAlerts = Column(CodingKeys.enableBurnoutAlerts)
        static let enableWeeklyReminders = Column(CodingKeys.enableWeeklyReminders)
    }
}
