import Foundation
import UserNotifications
import os

// MARK: - Notification Manager

private let logger = Logger(subsystem: "com.curaknot.app", category: "NotificationManager")

@MainActor
final class NotificationManager: ObservableObject {
    // MARK: - Properties
    
    @Published var isAuthorized = false
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            isAuthorized = granted
            return granted
        } catch {
            logger.error("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }
    
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    // MARK: - Task Reminders
    
    func scheduleTaskReminder(
        task: CareTask,
        offsetMinutes: Int
    ) async throws -> String {
        guard let dueAt = task.dueAt else {
            throw NotificationError.noDueDate
        }
        
        let reminderDate = dueAt.addingTimeInterval(-Double(offsetMinutes * 60))
        
        // Don't schedule if in the past
        guard reminderDate > Date() else {
            throw NotificationError.dateInPast
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = task.title
        content.sound = .default
        content.categoryIdentifier = "TASK_REMINDER"
        content.userInfo = [
            "taskId": task.id,
            "circleId": task.circleId
        ]
        
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        
        let notificationId = "task-\(task.id)-\(offsetMinutes)"
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )
        
        try await notificationCenter.add(request)
        return notificationId
    }
    
    func cancelTaskReminder(notificationId: String) {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [notificationId]
        )
    }
    
    func cancelAllTaskReminders(taskId: String) async {
        let requests = await notificationCenter.pendingNotificationRequests()
        let taskNotifications = requests
            .filter { $0.identifier.starts(with: "task-\(taskId)") }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: taskNotifications
        )
    }
    
    // MARK: - Notification Categories
    
    func registerCategories() {
        // Task reminder actions
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_TASK",
            title: "Mark Done",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_TASK",
            title: "Snooze 1 Hour",
            options: []
        )
        
        let taskCategory = UNNotificationCategory(
            identifier: "TASK_REMINDER",
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Handoff published actions
        let viewAction = UNNotificationAction(
            identifier: "VIEW_HANDOFF",
            title: "View",
            options: [.foreground]
        )
        
        let handoffCategory = UNNotificationCategory(
            identifier: "HANDOFF_PUBLISHED",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Siri draft actions
        let reviewAction = UNNotificationAction(
            identifier: "REVIEW_SIRI_DRAFT",
            title: "Review & Publish",
            options: [.foreground]
        )
        
        let discardAction = UNNotificationAction(
            identifier: "DISCARD_SIRI_DRAFT",
            title: "Discard",
            options: [.destructive]
        )
        
        let siriDraftCategory = UNNotificationCategory(
            identifier: "SIRI_DRAFT",
            actions: [reviewAction, discardAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            taskCategory,
            handoffCategory,
            siriDraftCategory
        ])
    }
    
    // MARK: - Badge Management
    
    func updateBadge(count: Int) async {
        do {
            try await notificationCenter.setBadgeCount(count)
        } catch {
            logger.error("Failed to update badge: \(error.localizedDescription)")
        }
    }
    
    func clearBadge() async {
        await updateBadge(count: 0)
    }
}

// MARK: - Notification Error

enum NotificationError: Error, LocalizedError {
    case noDueDate
    case dateInPast
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .noDueDate:
            return "Task has no due date"
        case .dateInPast:
            return "Reminder date is in the past"
        case .notAuthorized:
            return "Notification permission not granted"
        }
    }
}
