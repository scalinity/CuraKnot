import Foundation
import GRDB
import os

// MARK: - Offline Queue Manager

actor OfflineQueueManager {
    // MARK: - Properties
    
    private let databaseManager: DatabaseManager
    private var isProcessing = false
    private var maxRetries = 5
    private var retryBackoffSeconds: [Int] = [1, 5, 15, 60, 300]
    
    // MARK: - Initialization
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - Queue Management
    
    func enqueue(_ operation: OfflineOperation) throws {
        try databaseManager.write { db in
            try operation.insert(db)
        }
    }
    
    func dequeue() throws -> OfflineOperation? {
        try databaseManager.read { db in
            try OfflineOperation
                .filter(Column("attempts") < maxRetries)
                .order(Column("createdAt").asc)
                .fetchOne(db)
        }
    }
    
    func markCompleted(_ operation: OfflineOperation) throws {
        guard let id = operation.id else { return }
        
        try databaseManager.write { db in
            try OfflineOperation
                .filter(Column("id") == id)
                .deleteAll(db)
        }
    }
    
    func markFailed(_ operation: OfflineOperation) throws {
        guard let id = operation.id else { return }
        
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    UPDATE offlineQueue 
                    SET attempts = attempts + 1, lastAttemptAt = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), id]
            )
        }
    }
    
    func getQueueCount() throws -> Int {
        try databaseManager.read { db in
            try OfflineOperation.fetchCount(db)
        }
    }
    
    func getPendingCount() throws -> Int {
        try databaseManager.read { db in
            try OfflineOperation
                .filter(Column("attempts") < maxRetries)
                .fetchCount(db)
        }
    }
    
    func clearCompleted() throws {
        try databaseManager.write { db in
            try OfflineOperation
                .filter(Column("attempts") >= maxRetries)
                .deleteAll(db)
        }
    }
    
    func clearAll() throws {
        try databaseManager.write { db in
            try OfflineOperation.deleteAll(db)
        }
    }
    
    // MARK: - Processing
    
    func processQueue(
        handler: @escaping (OfflineOperation) async throws -> Void
    ) async throws {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        while let operation = try dequeue() {
            do {
                try await handler(operation)
                try markCompleted(operation)
            } catch {
                try markFailed(operation)
                
                // Check if we should continue or back off
                if operation.attempts + 1 >= maxRetries {
                    #if DEBUG
                    Logger(subsystem: "com.curaknot.app", category: "OfflineQueue").warning("Operation \(operation.id ?? 0) exceeded max retries")
                    #endif
                    continue
                }
                
                // Exponential backoff
                let backoffIndex = min(operation.attempts, retryBackoffSeconds.count - 1)
                let backoffSeconds = retryBackoffSeconds[backoffIndex]
                try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            }
        }
    }
}

// MARK: - Draft Manager

actor DraftManager {
    // MARK: - Properties
    
    private let databaseManager: DatabaseManager
    
    // MARK: - Initialization
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - Draft Operations
    
    func saveDraft(_ handoff: Handoff) throws {
        try databaseManager.write { db in
            try handoff.save(db)
        }
    }
    
    func getDrafts(circleId: String) throws -> [Handoff] {
        try databaseManager.read { db in
            try Handoff
                .filter(Column("circleId") == circleId)
                .filter(Column("status") == Handoff.Status.draft.rawValue)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }
    
    func getDraft(id: String) throws -> Handoff? {
        try databaseManager.read { db in
            try Handoff.fetchOne(db, key: id)
        }
    }
    
    func deleteDraft(id: String) throws {
        try databaseManager.write { db in
            try Handoff.deleteOne(db, key: id)
        }
    }
    
    func autosave(_ handoff: Handoff) throws {
        try saveDraft(handoff)
    }
}

// MARK: - Attachment Queue

actor AttachmentQueue {
    // MARK: - Types
    
    struct PendingAttachment: Codable, Identifiable {
        let id: String
        let localPath: String
        let circleId: String
        let handoffId: String?
        let binderItemId: String?
        let mimeType: String
        var attempts: Int
        let createdAt: Date
    }
    
    // MARK: - Properties
    
    private var queue: [PendingAttachment] = []
    private var isProcessing = false
    private let uploadManager: UploadManager
    
    // MARK: - Initialization
    
    init(uploadManager: UploadManager) {
        self.uploadManager = uploadManager
    }
    
    // MARK: - Queue Management
    
    func enqueue(
        localPath: String,
        circleId: String,
        handoffId: String? = nil,
        binderItemId: String? = nil,
        mimeType: String
    ) {
        let attachment = PendingAttachment(
            id: UUID().uuidString,
            localPath: localPath,
            circleId: circleId,
            handoffId: handoffId,
            binderItemId: binderItemId,
            mimeType: mimeType,
            attempts: 0,
            createdAt: Date()
        )
        queue.append(attachment)
    }
    
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        while !queue.isEmpty {
            let attachment = queue.removeFirst()
            
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: attachment.localPath))
                let filename = URL(fileURLWithPath: attachment.localPath).lastPathComponent
                
                _ = try await uploadManager.uploadAttachment(
                    circleId: attachment.circleId,
                    data: data,
                    filename: filename,
                    mimeType: attachment.mimeType
                )
                
                // Clean up local file
                try? FileManager.default.removeItem(atPath: attachment.localPath)
                
            } catch {
                // Re-queue with incremented attempts
                if attachment.attempts < 5 {
                    var updated = attachment
                    updated.attempts += 1
                    queue.append(updated)
                }
            }
        }
    }
    
    func getPendingCount() -> Int {
        queue.count
    }
}
