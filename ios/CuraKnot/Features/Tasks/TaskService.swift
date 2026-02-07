import Foundation
import GRDB

// MARK: - Task Service (Full Implementation)

extension TaskService {
    // MARK: - CRUD Operations
    
    func createTask(
        circleId: String,
        patientId: String? = nil,
        handoffId: String? = nil,
        title: String,
        description: String? = nil,
        dueAt: Date? = nil,
        priority: CareTask.Priority = .med,
        assigneeId: String,
        reminder: TaskReminder? = nil
    ) async throws -> CareTask {
        guard let currentUserId = await getCurrentUserId() else {
            throw TaskError.notAuthenticated
        }
        
        let task = CareTask(
            id: UUID().uuidString,
            circleId: circleId,
            patientId: patientId,
            handoffId: handoffId,
            createdBy: currentUserId,
            ownerUserId: assigneeId,
            title: title,
            description: description,
            dueAt: dueAt,
            priority: priority,
            status: .open,
            completedAt: nil,
            completedBy: nil,
            completionNote: nil,
            reminderJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save locally
        try databaseManager.write { db in
            try task.save(db)
        }
        
        // Enqueue for sync
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "INSERT",
            entityType: "tasks",
            entityId: task.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(task), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
        
        // Schedule reminder if enabled
        if let reminder = reminder, reminder.enabled, let dueAt = dueAt {
            var updatedTask = task
            let notificationId = try await scheduleReminder(for: updatedTask, offsetMinutes: reminder.offsetMinutes)
            updatedTask.reminder = TaskReminder(
                enabled: true,
                offsetMinutes: reminder.offsetMinutes,
                notificationId: notificationId
            )
            try databaseManager.write { db in
                try updatedTask.update(db)
            }
            return updatedTask
        }
        
        return task
    }
    
    func updateTask(_ task: CareTask) async throws {
        try databaseManager.write { db in
            try task.update(db)
        }
        
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPDATE",
            entityType: "tasks",
            entityId: task.id,
            payloadJson: try String(data: JSONEncoder.supabase.encode(task), encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }
    
    func completeTask(
        _ task: CareTask,
        completionNote: String? = nil
    ) async throws -> CareTask {
        guard let currentUserId = await getCurrentUserId() else {
            throw TaskError.notAuthenticated
        }
        
        var updatedTask = task
        updatedTask.status = .done
        updatedTask.completedAt = Date()
        updatedTask.completedBy = currentUserId
        updatedTask.completionNote = completionNote
        updatedTask.updatedAt = Date()
        
        try databaseManager.write { db in
            try updatedTask.update(db)
        }
        
        // Call RPC for server-side completion
        struct CompleteRequest: Encodable {
            let taskId: String
            let completionNote: String?
        }
        
        let _: EmptyResponse = try await supabaseClient
            .functions("rpc/complete_task")
            .invoke(body: CompleteRequest(
                taskId: task.id,
                completionNote: completionNote
            ))
        
        // Cancel any scheduled reminders
        if let notificationId = task.reminder?.notificationId {
            await NotificationManager().cancelTaskReminder(notificationId: notificationId)
        }
        
        return updatedTask
    }
    
    func deleteTask(_ task: CareTask) async throws {
        try databaseManager.write { db in
            try task.delete(db)
        }
        
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "DELETE",
            entityType: "tasks",
            entityId: task.id,
            payloadJson: "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
        
        // Cancel any scheduled reminders
        if let notificationId = task.reminder?.notificationId {
            await NotificationManager().cancelTaskReminder(notificationId: notificationId)
        }
    }
    
    // MARK: - Query Methods
    
    func fetchTasks(
        circleId: String,
        filter: TaskFilter = .all
    ) async throws -> [CareTask] {
        try await syncCoordinator.fetchLocalTasks(
            circleId: circleId,
            status: filter.status
        )
    }
    
    func fetchMyTasks(circleId: String) async throws -> [CareTask] {
        guard let userId = await getCurrentUserId() else { return [] }
        
        return try databaseManager.read { db in
            try CareTask
                .filter(Column("circleId") == circleId)
                .filter(Column("ownerUserId") == userId)
                .filter(Column("status") == CareTask.Status.open.rawValue)
                .order(Column("dueAt"))
                .fetchAll(db)
        }
    }
    
    func fetchOverdueTasks(circleId: String) async throws -> [CareTask] {
        try databaseManager.read { db in
            try CareTask
                .filter(Column("circleId") == circleId)
                .filter(Column("status") == CareTask.Status.open.rawValue)
                .filter(Column("dueAt") < Date())
                .order(Column("dueAt"))
                .fetchAll(db)
        }
    }
    
    // MARK: - Reminders
    
    private func scheduleReminder(
        for task: CareTask,
        offsetMinutes: Int
    ) async throws -> String {
        let notificationManager = await MainActor.run { NotificationManager() }
        return try await notificationManager.scheduleTaskReminder(
            task: task,
            offsetMinutes: offsetMinutes
        )
    }
    
    // MARK: - Helpers
    
    private func getCurrentUserId() async -> String? {
        // TODO: Get from auth manager
        return nil
    }
}

// MARK: - Task Filter

enum TaskFilter {
    case all
    case mine
    case overdue
    case done
    
    var status: CareTask.Status? {
        switch self {
        case .all, .mine, .overdue:
            return .open
        case .done:
            return .done
        }
    }
}

// MARK: - Task Error

enum TaskError: Error, LocalizedError {
    case notAuthenticated
    case notFound
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in"
        case .notFound:
            return "Task not found"
        case .permissionDenied:
            return "You don't have permission to modify this task"
        }
    }
}

// MARK: - Empty Response

struct EmptyResponse: Decodable {}
