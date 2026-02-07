import Foundation
import GRDB

// MARK: - Task Model

struct CareTask: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    var patientId: String?
    var handoffId: String?
    let createdBy: String
    var ownerUserId: String
    var title: String
    var description: String?
    var dueAt: Date?
    var priority: Priority
    var status: Status
    var completedAt: Date?
    var completedBy: String?
    var completionNote: String?
    var reminderJson: String?
    let createdAt: Date
    var updatedAt: Date
    
    // MARK: - Priority
    
    enum Priority: String, Codable, CaseIterable {
        case low = "LOW"
        case med = "MED"
        case high = "HIGH"
        
        var displayName: String {
            switch self {
            case .low: return "Low"
            case .med: return "Medium"
            case .high: return "High"
            }
        }
        
        var color: String {
            switch self {
            case .low: return "green"
            case .med: return "orange"
            case .high: return "red"
            }
        }
    }
    
    // MARK: - Status
    
    enum Status: String, Codable {
        case open = "OPEN"
        case done = "DONE"
        case canceled = "CANCELED"
    }
    
    // MARK: - Computed Properties
    
    var isComplete: Bool {
        status == .done
    }
    
    var isOverdue: Bool {
        guard let dueAt = dueAt, status == .open else { return false }
        return Date() > dueAt
    }
    
    var isDueSoon: Bool {
        guard let dueAt = dueAt, status == .open else { return false }
        let now = Date()
        let twentyFourHours: TimeInterval = 24 * 60 * 60
        return dueAt > now && dueAt.timeIntervalSince(now) < twentyFourHours
    }
    
    var reminder: TaskReminder? {
        get {
            guard let json = reminderJson,
                  let data = json.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(TaskReminder.self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                reminderJson = json
            } else {
                reminderJson = nil
            }
        }
    }
    
    var formattedDueDate: String? {
        guard let dueAt = dueAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: dueAt, relativeTo: Date())
    }
}

// MARK: - GRDB Conformance

extension CareTask: FetchableRecord, PersistableRecord {
    static let databaseTableName = "tasks"
}

// MARK: - Task Reminder

struct TaskReminder: Codable, Equatable {
    var enabled: Bool
    var offsetMinutes: Int  // Minutes before due date
    var notificationId: String?
    
    static let defaultReminders: [Int] = [
        15,      // 15 minutes
        60,      // 1 hour
        1440,    // 1 day
    ]
}
