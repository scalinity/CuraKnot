import Foundation
import GRDB
import os

// MARK: - Sync Coordinator

actor SyncCoordinator {
    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient

    private var isSyncing = false

    // MARK: - Constants

    private static let maxRetryAttempts = 3
    private static let retryDelaySeconds: UInt64 = 1_000_000_000 // 1 second in nanoseconds

    // MARK: - Initialization

    init(databaseManager: DatabaseManager, supabaseClient: SupabaseClient) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
    }

    // MARK: - Retry Helper

    /// Executes an async operation with exponential backoff retry
    private func withRetry<T>(
        maxAttempts: Int = maxRetryAttempts,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Don't retry on the last attempt
                if attempt < maxAttempts {
                    // Exponential backoff: 1s, 2s, 4s
                    let delayMultiplier = UInt64(1 << (attempt - 1))
                    try? await Task.sleep(nanoseconds: Self.retryDelaySeconds * delayMultiplier)
                }
            }
        }

        throw lastError ?? SyncError.unknownError
    }
    
    // MARK: - Full Sync
    
    func syncAll(circleId: String) async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        // Process offline queue first
        try await processOfflineQueue()
        
        // Sync each entity type
        try await syncCircles()
        try await syncPatients(circleId: circleId)
        try await syncHandoffs(circleId: circleId)
        try await syncTasks(circleId: circleId)
        try await syncBinderItems(circleId: circleId)
        try await syncCommunicationLogs(circleId: circleId)
    }
    
    // MARK: - Entity Sync Methods
    
    func syncCircles() async throws {
        let cursor = try getCursor(for: "circles")

        let circles: [Circle] = try await withRetry {
            try await self.supabaseClient
                .from("circles")
                .select()
                .gt("updated_at", cursor?.isoString ?? "1970-01-01T00:00:00Z")
                .order("updated_at")
                .limit(100)
                .execute()
        }

        if !circles.isEmpty {
            try databaseManager.write { db in
                for circle in circles {
                    try circle.save(db)
                }
            }

            if let lastCircle = circles.last {
                try updateCursor(for: "circles", date: lastCircle.updatedAt)
            }
        }
    }
    
    func syncPatients(circleId: String) async throws {
        let cursor = try getCursor(for: "patients")

        let patients: [Patient] = try await withRetry {
            try await self.supabaseClient
                .from("patients")
                .select()
                .eq("circle_id", circleId)
                .gt("updated_at", cursor?.isoString ?? "1970-01-01T00:00:00Z")
                .order("updated_at")
                .limit(100)
                .execute()
        }

        if !patients.isEmpty {
            try databaseManager.write { db in
                for patient in patients {
                    try patient.save(db)
                }
            }

            if let lastPatient = patients.last {
                try updateCursor(for: "patients", date: lastPatient.updatedAt)
            }
        }
    }
    
    func syncHandoffs(circleId: String) async throws {
        let cursor = try getCursor(for: "handoffs")

        let handoffs: [Handoff] = try await withRetry {
            try await self.supabaseClient
                .from("handoffs")
                .select()
                .eq("circle_id", circleId)
                .gt("updated_at", cursor?.isoString ?? "1970-01-01T00:00:00Z")
                .order("updated_at")
                .limit(100)
                .execute()
        }

        if !handoffs.isEmpty {
            try databaseManager.write { db in
                for handoff in handoffs {
                    try handoff.save(db)
                }
            }

            if let lastHandoff = handoffs.last {
                try updateCursor(for: "handoffs", date: lastHandoff.updatedAt)
            }
        }
    }
    
    func syncTasks(circleId: String) async throws {
        let cursor = try getCursor(for: "tasks")

        let tasks: [CareTask] = try await withRetry {
            try await self.supabaseClient
                .from("tasks")
                .select()
                .eq("circle_id", circleId)
                .gt("updated_at", cursor?.isoString ?? "1970-01-01T00:00:00Z")
                .order("updated_at")
                .limit(100)
                .execute()
        }

        if !tasks.isEmpty {
            try databaseManager.write { db in
                for task in tasks {
                    try task.save(db)
                }
            }

            if let lastTask = tasks.last {
                try updateCursor(for: "tasks", date: lastTask.updatedAt)
            }
        }
    }
    
    func syncBinderItems(circleId: String) async throws {
        let cursor = try getCursor(for: "binder_items")

        let items: [BinderItem] = try await withRetry {
            try await self.supabaseClient
                .from("binder_items")
                .select()
                .eq("circle_id", circleId)
                .gt("updated_at", cursor?.isoString ?? "1970-01-01T00:00:00Z")
                .order("updated_at")
                .limit(100)
                .execute()
        }

        if !items.isEmpty {
            try databaseManager.write { db in
                for item in items {
                    try item.save(db)
                }
            }

            if let lastItem = items.last {
                try updateCursor(for: "binder_items", date: lastItem.updatedAt)
            }
        }
    }

    func syncCommunicationLogs(circleId: String) async throws {
        let cursor = try getCursor(for: "communication_logs")

        let logs: [CommunicationLog] = try await withRetry {
            try await self.supabaseClient
                .from("communication_logs")
                .select()
                .eq("circle_id", circleId)
                .gt("updated_at", cursor?.isoString ?? "1970-01-01T00:00:00Z")
                .order("updated_at")
                .limit(100)
                .execute()
        }

        if !logs.isEmpty {
            try databaseManager.write { db in
                for log in logs {
                    try log.save(db)
                }
            }

            if let lastLog = logs.last {
                try updateCursor(for: "communication_logs", date: lastLog.updatedAt)
            }
        }
    }
    
    // MARK: - Local Fetch Methods
    
    func fetchLocalCircles() async throws -> [Circle] {
        try databaseManager.read { db in
            try Circle
                .filter(Column("deletedAt") == nil)
                .order(Column("name"))
                .fetchAll(db)
        }
    }
    
    func fetchLocalPatients(circleId: String) async throws -> [Patient] {
        try databaseManager.read { db in
            try Patient
                .filter(Column("circleId") == circleId)
                .filter(Column("archivedAt") == nil)
                .order(Column("displayName"))
                .fetchAll(db)
        }
    }
    
    func fetchLocalHandoffs(circleId: String, limit: Int = 50) async throws -> [Handoff] {
        try databaseManager.read { db in
            try Handoff
                .filter(Column("circleId") == circleId)
                .filter(Column("status") == "PUBLISHED")
                .order(Column("publishedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    func fetchLocalTasks(circleId: String, status: CareTask.Status? = nil) async throws -> [CareTask] {
        try databaseManager.read { db in
            var query = CareTask.filter(Column("circleId") == circleId)
            
            if let status = status {
                query = query.filter(Column("status") == status.rawValue)
            }
            
            return try query.order(Column("dueAt")).fetchAll(db)
        }
    }
    
    func fetchLocalBinderItems(circleId: String, type: BinderItem.ItemType? = nil) async throws -> [BinderItem] {
        try databaseManager.read { db in
            var query = BinderItem
                .filter(Column("circleId") == circleId)
                .filter(Column("isActive") == true)

            if let type = type {
                query = query.filter(Column("type") == type.rawValue)
            }

            return try query.order(Column("title")).fetchAll(db)
        }
    }

    func fetchLocalCommunicationLogs(circleId: String, patientId: String? = nil, limit: Int = 50) async throws -> [CommunicationLog] {
        try databaseManager.read { db in
            var query = CommunicationLog.filter(Column("circleId") == circleId)

            if let patientId = patientId {
                query = query.filter(Column("patientId") == patientId)
            }

            return try query
                .order(Column("callDate").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    // MARK: - Cursor Management
    
    private func getCursor(for entityType: String) throws -> Date? {
        try databaseManager.read { db in
            try SyncCursor
                .filter(Column("entityType") == entityType)
                .fetchOne(db)?
                .cursor
        }
    }
    
    private func updateCursor(for entityType: String, date: Date) throws {
        try databaseManager.write { db in
            let cursor = SyncCursor(
                entityType: entityType,
                cursor: date,
                updatedAt: Date()
            )
            try cursor.save(db)
        }
    }
    
    // MARK: - Offline Queue
    
    func enqueue(operation: OfflineOperation) throws {
        try databaseManager.write { db in
            try operation.insert(db)
        }
    }
    
    private func processOfflineQueue() async throws {
        let operations = try databaseManager.read { db in
            try OfflineOperation
                .order(Column("createdAt"))
                .fetchAll(db)
        }
        
        for operation in operations {
            do {
                try await processOperation(operation)
                
                // Remove from queue on success
                try databaseManager.write { db in
                    try operation.delete(db)
                }
            } catch {
                // Update attempt count
                try databaseManager.write { db in
                    var updated = operation
                    updated.attempts += 1
                    updated.lastAttemptAt = Date()
                    try updated.update(db)
                }
                
                // If too many attempts, log error but continue
                if operation.attempts >= 5 {
                    #if DEBUG
                    Logger(subsystem: "com.curaknot.app", category: "SyncCoordinator").error("Operation failed after 5 attempts: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }
    
    private func processOperation(_ operation: OfflineOperation) async throws {
        // TODO: Implement full offline queue processing
        // This requires proper Supabase Swift SDK API usage for INSERT/UPDATE/DELETE
        // Currently operations are queued but processing is deferred
        // See: https://github.com/supabase-community/supabase-swift
        switch operation.operationType {
        case "INSERT":
            break
        case "UPDATE":
            break
        case "DELETE":
            break
        default:
            break
        }
    }
}

// MARK: - Sync Cursor

struct SyncCursor: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "syncCursors"
    
    let entityType: String
    var cursor: Date
    var updatedAt: Date
}

// MARK: - Offline Operation

struct OfflineOperation: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "offlineQueue"
    
    var id: Int64?
    let operationType: String
    let entityType: String
    let entityId: String
    let payloadJson: String
    var attempts: Int
    var lastAttemptAt: Date?
    let createdAt: Date
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Date Extension

extension Date {
    var isoString: String {
        ISO8601DateFormatter().string(from: self)
    }
}

// MARK: - Sync Error

enum SyncError: Error {
    case unknownError
    case networkUnavailable
    case unauthorized
}
