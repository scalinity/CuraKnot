import Foundation
import GRDB
import Security

// MARK: - Database Encryption Key Helper

private enum DatabaseEncryptionKey {
    private static let keychainAccount = "com.curaknot.db-encryption-key"
    
    /// Retrieve or generate the database encryption key from Keychain.
    /// Uses kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so the key
    /// is available after first unlock but never backed up or migrated.
    static func getOrCreateKey() -> String {
        if let existing = loadKey() {
            return existing
        }
        let newKey = generateKey()
        saveKey(newKey)
        return newKey
    }
    
    private static func generateKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            fatalError("Failed to generate random encryption key: \(status)")
        }
        return Data(bytes).base64EncodedString()
    }
    
    private static func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private static func saveKey(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        // Remove any existing key first
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            fatalError("Failed to save encryption key to Keychain: \(status)")
        }
    }
}

// MARK: - Database Manager

final class DatabaseManager {
    // MARK: - Properties
    
    private var dbQueue: DatabaseQueue?
    
    var databaseQueue: DatabaseQueue {
        guard let dbQueue = dbQueue else {
            fatalError("Database not initialized. Call setup() first.")
        }
        return dbQueue
    }
    
    // MARK: - Setup

    func setup() throws {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let databaseURL = appSupportURL.appendingPathComponent("CuraKnot.sqlite")

        // Retrieve or generate encryption key from Keychain
        let encryptionKey = DatabaseEncryptionKey.getOrCreateKey()

        var configuration = GRDB.Configuration()
        configuration.prepareDatabase { db in
            // SECURITY: Enable SQLCipher encryption with Keychain-derived key.
            // Requires SQLCipher to be linked; if using plain SQLite this PRAGMA
            // is a no-op (logs a warning in debug).
            try db.execute(sql: "PRAGMA key = '\(encryptionKey)'")
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)

        try migrator.migrate(dbQueue!)
    }

    /// Set up an in-memory database for testing
    /// Each call creates a fresh, isolated database instance
    func setupInMemory() throws {
        var configuration = GRDB.Configuration()
        configuration.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        // Use in-memory database for isolation between tests
        dbQueue = try DatabaseQueue(configuration: configuration)

        try migrator.migrate(dbQueue!)
    }
    
    // MARK: - Migrations
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // Migration 1: Initial schema
        migrator.registerMigration("v1_initial") { db in
            // Users
            try db.create(table: "users") { t in
                t.column("id", .text).primaryKey()
                t.column("email", .text)
                t.column("appleSub", .text)
                t.column("displayName", .text).notNull()
                t.column("avatarUrl", .text)
                t.column("settingsJson", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // Circles
            try db.create(table: "circles") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("icon", .text)
                t.column("ownerUserId", .text).notNull()
                t.column("plan", .text).notNull()
                t.column("settingsJson", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            
            // Circle Members
            try db.create(table: "circleMembers") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("userId", .text).notNull().references("users", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("status", .text).notNull()
                t.column("invitedBy", .text)
                t.column("invitedAt", .datetime)
                t.column("joinedAt", .datetime)
                t.column("lastActiveAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                
                t.uniqueKey(["circleId", "userId"])
            }
            
            // Patients
            try db.create(table: "patients") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("displayName", .text).notNull()
                t.column("initials", .text)
                t.column("dob", .date)
                t.column("pronouns", .text)
                t.column("notes", .text)
                t.column("archivedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // Handoffs
            try db.create(table: "handoffs") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).notNull().references("patients")
                t.column("createdBy", .text).notNull()
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("summary", .text)
                t.column("keywordsJson", .text)
                t.column("status", .text).notNull()
                t.column("publishedAt", .datetime)
                t.column("currentRevision", .integer).notNull().defaults(to: 1)
                t.column("rawTranscript", .text)
                t.column("audioStorageKey", .text)
                t.column("confidenceJson", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // Handoff Revisions
            try db.create(table: "handoffRevisions") { t in
                t.column("id", .text).primaryKey()
                t.column("handoffId", .text).notNull().references("handoffs", onDelete: .cascade)
                t.column("revision", .integer).notNull()
                t.column("structuredJson", .text).notNull()
                t.column("editedBy", .text).notNull()
                t.column("editedAt", .datetime).notNull()
                t.column("changeNote", .text)
                
                t.uniqueKey(["handoffId", "revision"])
            }
            
            // Read Receipts
            try db.create(table: "readReceipts") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("handoffId", .text).notNull().references("handoffs", onDelete: .cascade)
                t.column("userId", .text).notNull()
                t.column("readAt", .datetime).notNull()
                
                t.uniqueKey(["handoffId", "userId"])
            }
            
            // Tasks
            try db.create(table: "tasks") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).references("patients")
                t.column("handoffId", .text).references("handoffs")
                t.column("createdBy", .text).notNull()
                t.column("ownerUserId", .text).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("dueAt", .datetime)
                t.column("priority", .text).notNull()
                t.column("status", .text).notNull()
                t.column("completedAt", .datetime)
                t.column("completedBy", .text)
                t.column("completionNote", .text)
                t.column("reminderJson", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // Binder Items
            try db.create(table: "binderItems") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).references("patients")
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("contentJson", .text).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdBy", .text).notNull()
                t.column("updatedBy", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // Attachments
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("uploaderUserId", .text).notNull()
                t.column("handoffId", .text).references("handoffs")
                t.column("binderItemId", .text).references("binderItems")
                t.column("kind", .text).notNull()
                t.column("mimeType", .text).notNull()
                t.column("byteSize", .integer).notNull()
                t.column("sha256", .text).notNull()
                t.column("storageKey", .text).notNull()
                t.column("filename", .text)
                t.column("createdAt", .datetime).notNull()
            }
            
            // Sync Cursors
            try db.create(table: "syncCursors") { t in
                t.column("entityType", .text).primaryKey()
                t.column("cursor", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // Offline Queue
            try db.create(table: "offlineQueue") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("operationType", .text).notNull()
                t.column("entityType", .text).notNull()
                t.column("entityId", .text).notNull()
                t.column("payloadJson", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("lastAttemptAt", .datetime)
                t.column("createdAt", .datetime).notNull()
            }
        }
        
        // Migration 2: Siri Shortcuts support
        migrator.registerMigration("v2_siri_shortcuts") { db in
            // Add source column to handoffs (defaults to APP for existing records)
            try db.alter(table: "handoffs") { t in
                t.add(column: "source", .text).notNull().defaults(to: "APP")
            }
            
            // Add siriRawText column to handoffs
            try db.alter(table: "handoffs") { t in
                t.add(column: "siriRawText", .text)
            }
            
            // Create patient aliases table
            try db.create(table: "patientAliases") { t in
                t.column("id", .text).primaryKey()
                t.column("patientId", .text).notNull().references("patients", onDelete: .cascade)
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("alias", .text).notNull()
                t.column("createdBy", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            
            // Index for fast alias lookup
            try db.create(
                index: "idx_patientAliases_lookup",
                on: "patientAliases",
                columns: ["circleId", "alias"]
            )
            
            // Index for Siri drafts pending review
            try db.create(
                index: "idx_handoffs_siri_drafts",
                on: "handoffs",
                columns: ["createdBy", "status", "createdAt"]
            )
        }

        // Migration 3: Calendar sync tables
        migrator.registerMigration("v3_calendar_sync") { db in
            // Calendar Connections
            try db.create(table: "calendarConnections") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text).notNull()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("provider", .text).notNull()
                t.column("status", .text).notNull()
                t.column("statusMessage", .text)
                t.column("appleCalendarId", .text)
                t.column("appleCalendarTitle", .text)
                t.column("calendarId", .text)
                t.column("calendarTitle", .text)
                t.column("syncDirection", .text).notNull()
                t.column("conflictStrategy", .text).notNull()
                t.column("syncIntervalMinutes", .integer).notNull().defaults(to: 15)
                t.column("syncTasks", .boolean).notNull().defaults(to: true)
                t.column("syncShifts", .boolean).notNull().defaults(to: true)
                t.column("syncAppointments", .boolean).notNull().defaults(to: true)
                t.column("syncHandoffFollowups", .boolean).notNull().defaults(to: false)
                t.column("showMinimalDetails", .boolean).notNull().defaults(to: false)
                t.column("lastSyncAt", .datetime)
                t.column("lastSyncStatus", .text)
                t.column("lastSyncError", .text)
                t.column("eventsSyncedCount", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()

                t.uniqueKey(["userId", "circleId", "provider"])
            }

            // Calendar Events
            try db.create(table: "calendarEvents") { t in
                t.column("id", .text).primaryKey()
                t.column("connectionId", .text).notNull().references("calendarConnections", onDelete: .cascade)
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text)
                t.column("sourceType", .text).notNull()
                t.column("sourceTaskId", .text).references("tasks", onDelete: .cascade)
                t.column("sourceShiftId", .text)
                t.column("sourceBinderItemId", .text)
                t.column("sourceHandoffId", .text)
                t.column("externalEventId", .text).notNull()
                t.column("externalCalendarId", .text)
                t.column("externalEtag", .text)
                t.column("externalIcalUid", .text)
                t.column("title", .text).notNull()
                t.column("eventDescription", .text)
                t.column("startAt", .datetime).notNull()
                t.column("endAt", .datetime)
                t.column("allDay", .boolean).notNull().defaults(to: false)
                t.column("location", .text)
                t.column("recurrenceRule", .text)
                t.column("recurrenceId", .text)
                t.column("syncStatus", .text).notNull()
                t.column("syncError", .text)
                t.column("conflictDataJson", .text)
                t.column("conflictDetectedAt", .datetime)
                t.column("conflictResolvedAt", .datetime)
                t.column("conflictResolution", .text)
                t.column("lastSyncedAt", .datetime)
                t.column("localUpdatedAt", .datetime).notNull()
                t.column("externalUpdatedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()

                t.uniqueKey(["connectionId", "externalEventId"])
            }

            // iCal Feed Tokens
            try db.create(table: "icalFeedTokens") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("createdBy", .text).notNull()
                t.column("token", .text).notNull().unique()
                t.column("feedName", .text)
                t.column("includeTasks", .boolean).notNull().defaults(to: true)
                t.column("includeShifts", .boolean).notNull().defaults(to: true)
                t.column("includeAppointments", .boolean).notNull().defaults(to: true)
                t.column("includeHandoffFollowups", .boolean).notNull().defaults(to: false)
                t.column("patientIdsJson", .text)
                t.column("showMinimalDetails", .boolean).notNull().defaults(to: false)
                t.column("lookaheadDays", .integer).notNull().defaults(to: 90)
                t.column("expiresAt", .datetime)
                t.column("revokedAt", .datetime)
                t.column("accessCount", .integer).notNull().defaults(to: 0)
                t.column("lastAccessedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Indexes for calendar tables
            try db.create(
                index: "idx_calendarConnections_user",
                on: "calendarConnections",
                columns: ["userId"]
            )
            try db.create(
                index: "idx_calendarConnections_circle",
                on: "calendarConnections",
                columns: ["circleId"]
            )
            try db.create(
                index: "idx_calendarEvents_connection",
                on: "calendarEvents",
                columns: ["connectionId"]
            )
            try db.create(
                index: "idx_calendarEvents_sourceTask",
                on: "calendarEvents",
                columns: ["sourceTaskId"]
            )
            try db.create(
                index: "idx_icalFeedTokens_circle",
                on: "icalFeedTokens",
                columns: ["circleId"]
            )
        }

        // Migration 4: Calendar Security (HMAC checksums)
        migrator.registerMigration("v4_calendar_security") { db in
            // Add data_checksum column for HMAC integrity verification
            // SECURITY: Used to detect tampering with calendar event data
            try db.alter(table: "calendarEvents") { t in
                t.add(column: "dataChecksum", .text)
            }
        }

        // Migration 5: Appointment Questions
        migrator.registerMigration("v5_appointment_questions") { db in
            // Appointment Questions table for AI-generated and user-added questions
            try db.create(table: "appointmentQuestions") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).notNull().references("patients", onDelete: .cascade)
                t.column("appointmentPackId", .text)
                t.column("questionText", .text).notNull()
                t.column("reasoning", .text)
                t.column("category", .text).notNull()
                t.column("source", .text).notNull()
                t.column("sourceHandoffIds", .text) // JSON array
                t.column("sourceMedicationIds", .text) // JSON array
                t.column("createdBy", .text).notNull()
                t.column("priority", .text).notNull()
                t.column("priorityScore", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: "PENDING")
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("responseNotes", .text)
                t.column("discussedAt", .datetime)
                t.column("discussedBy", .text)
                t.column("followUpTaskId", .text).references("tasks", onDelete: .setNull)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Indexes for appointment questions
            try db.create(
                index: "idx_appointmentQuestions_patient",
                on: "appointmentQuestions",
                columns: ["patientId", "createdAt"]
            )
            try db.create(
                index: "idx_appointmentQuestions_pack",
                on: "appointmentQuestions",
                columns: ["appointmentPackId"]
            )
            try db.create(
                index: "idx_appointmentQuestions_pending",
                on: "appointmentQuestions",
                columns: ["patientId", "status"]
            )
        }

        // Migration 6: Document Scanner
        migrator.registerMigration("v6_document_scanner") { db in
            // Document Scans table
            try db.create(table: "documentScans") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).references("patients", onDelete: .setNull)
                t.column("createdBy", .text).notNull()
                t.column("storageKeysJson", .text).notNull() // JSON array of storage paths
                t.column("pageCount", .integer).notNull()
                t.column("ocrText", .text)
                t.column("ocrConfidence", .double)
                t.column("ocrProvider", .text)
                t.column("documentType", .text)
                t.column("classificationConfidence", .double)
                t.column("classificationSource", .text)
                t.column("extractedFieldsJson", .text)
                t.column("extractionConfidence", .double)
                t.column("routedToType", .text)
                t.column("routedToId", .text)
                t.column("routedAt", .datetime)
                t.column("routedBy", .text)
                t.column("status", .text).notNull()
                t.column("errorMessage", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Indexes for document scans
            try db.create(
                index: "idx_documentScans_circle",
                on: "documentScans",
                columns: ["circleId", "createdAt"]
            )
            try db.create(
                index: "idx_documentScans_patient",
                on: "documentScans",
                columns: ["patientId"]
            )
            try db.create(
                index: "idx_documentScans_status",
                on: "documentScans",
                columns: ["circleId", "status"]
            )
            try db.create(
                index: "idx_documentScans_type",
                on: "documentScans",
                columns: ["circleId", "documentType"]
            )
        }

        // Migration 7: Discharge Wizard
        migrator.registerMigration("v7_discharge_wizard") { db in
            // Discharge Templates (system templates for checklists)
            try db.create(table: "dischargeTemplates") { t in
                t.column("id", .text).primaryKey()
                t.column("templateName", .text).notNull()
                t.column("dischargeType", .text).notNull()
                t.column("description", .text)
                t.column("itemsJson", .text).notNull()
                t.column("isSystem", .boolean).notNull().defaults(to: false)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Discharge Records (wizard state)
            try db.create(table: "dischargeRecords") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).notNull().references("patients", onDelete: .cascade)
                t.column("createdBy", .text).notNull()
                t.column("facilityName", .text).notNull()
                t.column("dischargeDate", .date).notNull()
                t.column("admissionDate", .date)
                t.column("reasonForStay", .text).notNull()
                t.column("dischargeType", .text).notNull()
                t.column("templateId", .text)
                t.column("status", .text).notNull().defaults(to: "IN_PROGRESS")
                t.column("currentStep", .integer).notNull().defaults(to: 1)
                t.column("completedAt", .datetime)
                t.column("completedBy", .text)
                t.column("generatedTasks", .text)  // JSON array of task IDs
                t.column("generatedHandoffId", .text)
                t.column("generatedShifts", .text)  // JSON array of shift IDs
                t.column("generatedBinderItems", .text)  // JSON array of binder item IDs
                t.column("checklistStateJson", .text)
                t.column("shiftAssignmentsJson", .text)
                t.column("medicationChangesJson", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Discharge Checklist Items (progress tracking)
            try db.create(table: "dischargeChecklistItems") { t in
                t.column("id", .text).primaryKey()
                t.column("dischargeRecordId", .text).notNull().references("dischargeRecords", onDelete: .cascade)
                t.column("templateItemId", .text).notNull()
                t.column("category", .text).notNull()
                t.column("itemText", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("isCompleted", .boolean).notNull().defaults(to: false)
                t.column("completedAt", .datetime)
                t.column("completedBy", .text)
                t.column("createTask", .boolean).notNull().defaults(to: false)
                t.column("taskId", .text)
                t.column("assignedTo", .text)
                t.column("dueDate", .date)
                t.column("notes", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()

                t.uniqueKey(["dischargeRecordId", "templateItemId"])
            }

            // Indexes
            try db.create(
                index: "idx_dischargeRecords_circle",
                on: "dischargeRecords",
                columns: ["circleId", "status"]
            )
            try db.create(
                index: "idx_dischargeRecords_patient",
                on: "dischargeRecords",
                columns: ["patientId", "status"]
            )
            try db.create(
                index: "idx_dischargeChecklistItems_record",
                on: "dischargeChecklistItems",
                columns: ["dischargeRecordId"]
            )
        }

        // Migration 8: Wellness & Burnout Detection
        migrator.registerMigration("v8_wellness") { db in
            // Wellness Check-Ins (USER-PRIVATE)
            try db.create(table: "wellness_checkins") { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull()
                t.column("stress_level", .integer).notNull()
                t.column("sleep_quality", .integer).notNull()
                t.column("capacity_level", .integer).notNull()
                t.column("notes_encrypted", .text)
                t.column("notes_nonce", .text)
                t.column("notes_tag", .text)
                t.column("wellness_score", .integer)
                t.column("behavioral_score", .integer)
                t.column("total_score", .integer)
                t.column("week_start", .date).notNull()
                t.column("skipped", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()

                t.uniqueKey(["user_id", "week_start"])
            }

            // Wellness Alerts (USER-PRIVATE)
            try db.create(table: "wellness_alerts") { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull()
                t.column("risk_level", .text).notNull()
                t.column("alert_type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("message", .text).notNull()
                t.column("delegation_suggestions", .text)  // JSON
                t.column("status", .text).notNull()
                t.column("dismissed_at", .datetime)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Wellness Preferences (USER-PRIVATE)
            try db.create(table: "wellness_preferences") { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull().unique()
                t.column("check_in_reminders_enabled", .boolean).notNull().defaults(to: true)
                t.column("reminder_day", .text).notNull().defaults(to: "SUNDAY")
                t.column("reminder_hour", .integer).notNull().defaults(to: 9)
                t.column("show_score_on_dashboard", .boolean).notNull().defaults(to: true)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Indexes for wellness tables
            try db.create(
                index: "idx_wellness_checkins_user",
                on: "wellness_checkins",
                columns: ["user_id", "week_start"]
            )
            try db.create(
                index: "idx_wellness_alerts_user",
                on: "wellness_alerts",
                columns: ["user_id", "status"]
            )
        }

        // Migration 9: Communication Logs (Facility Communication Log Feature)
        migrator.registerMigration("v9_communication_logs") { db in
            // Communication Logs table
            try db.create(table: "communicationLogs") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).notNull().references("patients", onDelete: .cascade)
                t.column("createdBy", .text).notNull()

                // Contact info
                t.column("facilityName", .text).notNull()
                t.column("facilityId", .text)
                t.column("contactName", .text).notNull()
                t.column("contactRole", .text) // JSON array
                t.column("contactPhone", .text)
                t.column("contactEmail", .text)

                // Call details
                t.column("communicationType", .text).notNull().defaults(to: "CALL")
                t.column("callType", .text).notNull()
                t.column("callDate", .datetime).notNull()
                t.column("durationMinutes", .integer)
                t.column("summary", .text).notNull()

                // Follow-up
                t.column("followUpDate", .date)
                t.column("followUpReason", .text)
                t.column("followUpStatus", .text).notNull().defaults(to: "NONE")
                t.column("followUpCompletedAt", .datetime)
                t.column("followUpTaskId", .text)

                // Linked entities
                t.column("linkedHandoffId", .text)

                // AI suggestions
                t.column("aiSuggestedTasks", .text) // JSON
                t.column("aiSuggestionsAccepted", .boolean).notNull().defaults(to: false)

                // Status
                t.column("resolutionStatus", .text).notNull().defaults(to: "OPEN")

                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Indexes for communication logs
            try db.create(
                index: "idx_communicationLogs_patient",
                on: "communicationLogs",
                columns: ["patientId", "callDate"]
            )
            try db.create(
                index: "idx_communicationLogs_circle",
                on: "communicationLogs",
                columns: ["circleId", "callDate"]
            )
            try db.create(
                index: "idx_communicationLogs_facility",
                on: "communicationLogs",
                columns: ["circleId", "facilityName"]
            )
            try db.create(
                index: "idx_communicationLogs_followup",
                on: "communicationLogs",
                columns: ["followUpDate", "followUpStatus"]
            )
        }

        // Migration 10: Video Board (Family Video Message Board)
        migrator.registerMigration("v10_video_board") { db in
            // Video Messages
            try db.create(table: "video_messages") { t in
                t.column("id", .text).primaryKey()
                t.column("circle_id", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patient_id", .text).notNull().references("patients", onDelete: .cascade)
                t.column("created_by", .text).notNull()
                t.column("storage_key", .text).notNull()
                t.column("thumbnail_key", .text)
                t.column("duration_seconds", .integer).notNull()
                t.column("file_size_bytes", .integer).notNull()
                t.column("caption", .text)
                t.column("status", .text).notNull().defaults(to: "UPLOADING")
                t.column("flagged_by", .text)
                t.column("flagged_at", .datetime)
                t.column("removed_by", .text)
                t.column("removed_at", .datetime)
                t.column("removal_reason", .text)
                t.column("save_forever", .boolean).notNull().defaults(to: false)
                t.column("expires_at", .datetime)
                t.column("retention_days", .integer).notNull().defaults(to: 30)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("processed_at", .datetime)
            }

            // Video Reactions
            try db.create(table: "video_reactions") { t in
                t.column("id", .text).primaryKey()
                t.column("video_message_id", .text).notNull().references("video_messages", onDelete: .cascade)
                t.column("user_id", .text).notNull()
                t.column("reaction_type", .text).notNull().defaults(to: "LOVE")
                t.column("created_at", .datetime).notNull()

                t.uniqueKey(["video_message_id", "user_id"])
            }

            // Video Views
            try db.create(table: "video_views") { t in
                t.column("id", .text).primaryKey()
                t.column("video_message_id", .text).notNull().references("video_messages", onDelete: .cascade)
                t.column("viewed_by", .text).notNull()
                t.column("viewed_at", .datetime).notNull()
            }

            // Indexes
            try db.create(
                index: "idx_video_messages_patient",
                on: "video_messages",
                columns: ["patient_id", "created_at"]
            )
            try db.create(
                index: "idx_video_messages_circle",
                on: "video_messages",
                columns: ["circle_id", "created_at"]
            )
            try db.create(
                index: "idx_video_reactions_video",
                on: "video_reactions",
                columns: ["video_message_id"]
            )
            try db.create(
                index: "idx_video_views_video",
                on: "video_views",
                columns: ["video_message_id"]
            )
        }

        // Migration 11: Multi-Language Translation
        migrator.registerMigration("v11_translation") { db in
            // Add source_language to handoffs
            try db.alter(table: "handoffs") { t in
                t.add(column: "sourceLanguage", .text)
            }

            // Handoff Translations (cache of translated handoffs)
            try db.create(table: "handoffTranslations") { t in
                t.column("id", .text).primaryKey()
                t.column("handoffId", .text).notNull().references("handoffs", onDelete: .cascade)
                t.column("revisionId", .text)
                t.column("sourceLanguage", .text).notNull()
                t.column("targetLanguage", .text).notNull()
                t.column("translatedTitle", .text)
                t.column("translatedSummary", .text)
                t.column("translatedContentJson", .text)
                t.column("translationEngine", .text).notNull()
                t.column("confidenceScore", .double)
                t.column("sourceHash", .text).notNull()
                t.column("isStale", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()

                t.uniqueKey(["handoffId", "targetLanguage"])
            }

            // Translation Glossary (local cache)
            try db.create(table: "translationGlossary") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text)
                t.column("sourceLanguage", .text).notNull()
                t.column("targetLanguage", .text).notNull()
                t.column("sourceTerm", .text).notNull()
                t.column("translatedTerm", .text).notNull()
                t.column("context", .text)
                t.column("category", .text)
                t.column("createdBy", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            // Translation Cache (generic text translations)
            try db.create(table: "translationCache") { t in
                t.column("id", .text).primaryKey()
                t.column("sourceTextHash", .text).notNull()
                t.column("sourceLanguage", .text).notNull()
                t.column("targetLanguage", .text).notNull()
                t.column("translatedText", .text).notNull()
                t.column("confidenceScore", .double)
                t.column("containsMedicalTerms", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("expiresAt", .datetime).notNull()

                t.uniqueKey(["sourceTextHash", "sourceLanguage", "targetLanguage"])
            }

            // Indexes
            try db.create(
                index: "idx_handoffTranslations_handoff",
                on: "handoffTranslations",
                columns: ["handoffId", "targetLanguage"]
            )
            try db.create(
                index: "idx_translationGlossary_circle",
                on: "translationGlossary",
                columns: ["circleId", "sourceLanguage", "targetLanguage"]
            )
            try db.create(
                index: "idx_translationCache_lookup",
                on: "translationCache",
                columns: ["sourceTextHash", "sourceLanguage", "targetLanguage"]
            )
            try db.create(
                index: "idx_translationCache_expires",
                on: "translationCache",
                columns: ["expiresAt"]
            )
        }

        // Migration 12: Care Cost Projection
        migrator.registerMigration("v12_care_cost_projection") { db in
            // Care Expenses
            try db.create(table: "careExpenses") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).notNull().references("patients", onDelete: .cascade)
                t.column("createdBy", .text).notNull()
                t.column("category", .text).notNull()
                t.column("description", .text).notNull()
                t.column("vendorName", .text)
                t.column("amount", .text).notNull() // Store Decimal as text for precision
                t.column("expenseDate", .date).notNull()
                t.column("isRecurring", .boolean).notNull().defaults(to: false)
                t.column("recurrenceRule", .text)
                t.column("parentExpenseId", .text)
                t.column("coveredByInsurance", .text).notNull().defaults(to: "0")
                t.column("receiptStorageKey", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Care Cost Estimates
            try db.create(table: "careCostEstimates") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull().references("circles", onDelete: .cascade)
                t.column("patientId", .text).notNull().references("patients", onDelete: .cascade)
                t.column("createdBy", .text).notNull()
                t.column("scenarioType", .text).notNull()
                t.column("scenarioName", .text).notNull()
                t.column("monthlyTotal", .text).notNull() // Decimal as text
                t.column("annualTotal", .text).notNull() // Decimal as text
                t.column("breakdownJson", .text)
                t.column("assumptionsJson", .text)
                t.column("localCostId", .text)
                t.column("adjustmentFactor", .text).notNull().defaults(to: "1.0")
                t.column("isCurrent", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Local Care Costs (read-only cache from server)
            try db.create(table: "localCareCosts") { t in
                t.column("id", .text).primaryKey()
                t.column("state", .text).notNull()
                t.column("zipCodePrefix", .text)
                t.column("regionName", .text).notNull()
                t.column("homeCareHourlyMin", .text)
                t.column("homeCareHourlyMax", .text)
                t.column("homeCareHourlyMedian", .text)
                t.column("assistedLivingMonthlyMin", .text)
                t.column("assistedLivingMonthlyMax", .text)
                t.column("assistedLivingMonthlyMedian", .text)
                t.column("memoryCareMonthlyMin", .text)
                t.column("memoryCareMonthlyMax", .text)
                t.column("memoryCareMonthlyMedian", .text)
                t.column("nursingHomePrivateDaily", .text)
                t.column("nursingHomeSemiPrivateDaily", .text)
                t.column("adultDayCareDaily", .text)
                t.column("dataYear", .integer).notNull()
                t.column("sourceAttribution", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Financial Resources (read-only cache from server)
            try db.create(table: "financialResources") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("url", .text).notNull()
                t.column("resourceType", .text).notNull()
                t.column("category", .text).notNull()
                t.column("stateSpecific", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Indexes
            try db.create(
                index: "idx_careExpenses_circle",
                on: "careExpenses",
                columns: ["circleId", "expenseDate"]
            )
            try db.create(
                index: "idx_careExpenses_patient",
                on: "careExpenses",
                columns: ["patientId", "expenseDate"]
            )
            try db.create(
                index: "idx_careExpenses_category",
                on: "careExpenses",
                columns: ["circleId", "category"]
            )
            try db.create(
                index: "idx_careCostEstimates_circle",
                on: "careCostEstimates",
                columns: ["circleId", "isCurrent"]
            )
            try db.create(
                index: "idx_localCareCosts_location",
                on: "localCareCosts",
                columns: ["state", "zipCodePrefix"]
            )
            try db.create(
                index: "idx_financialResources_category",
                on: "financialResources",
                columns: ["category", "isActive"]
            )
        }

        // Migration 12b: Fix careCostEstimates and financialResources schemas
        migrator.registerMigration("v12b_care_cost_schema_fix") { db in
            // Drop and recreate careCostEstimates with columns matching Swift model
            try db.drop(table: "careCostEstimates")
            try db.create(table: "careCostEstimates") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull()
                t.column("patientId", .text).notNull()
                t.column("scenarioName", .text).notNull()
                t.column("scenarioType", .text).notNull()
                t.column("isCurrent", .boolean).notNull().defaults(to: false)
                t.column("homeCareHoursWeekly", .integer)
                t.column("homeCareHourlyRate", .text) // Decimal as text
                t.column("homeCareMonthly", .text)
                t.column("medicationsMonthly", .text)
                t.column("suppliesMonthly", .text)
                t.column("transportationMonthly", .text)
                t.column("facilityMonthly", .text)
                t.column("otherMonthly", .text)
                t.column("totalMonthly", .text).notNull()
                t.column("medicareCoveragePct", .text)
                t.column("medicaidCoveragePct", .text)
                t.column("privateInsurancePct", .text)
                t.column("outOfPocketMonthly", .text)
                t.column("notes", .text)
                t.column("dataSource", .text).notNull().defaults(to: "USER_INPUT")
                t.column("dataYear", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Drop and recreate financialResources with columns matching Swift model CodingKeys
            try db.drop(table: "financialResources")
            try db.create(table: "financialResources") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("description", .text) // CodingKey for resourceDescription
                t.column("url", .text)
                t.column("resourceType", .text).notNull()
                t.column("category", .text).notNull()
                t.column("contentMarkdown", .text)
                t.column("states", .text) // JSON-encoded [String]?
                t.column("isFeatured", .boolean).notNull().defaults(to: false)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Recreate indexes for the rebuilt tables
            try db.create(
                index: "idx_careCostEstimates_circle",
                on: "careCostEstimates",
                columns: ["circleId", "isCurrent"]
            )
            try db.create(
                index: "idx_financialResources_category",
                on: "financialResources",
                columns: ["category", "isActive"]
            )
        }

        // Migration 13: Respite Care Finder (local cache)
        migrator.registerMigration("v13_respite_care") { db in
            // Cached Respite Providers
            try db.create(table: "respiteProviders") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("providerType", .text).notNull()
                t.column("description", .text)
                t.column("address", .text)
                t.column("city", .text)
                t.column("state", .text)
                t.column("zipCode", .text)
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("phone", .text)
                t.column("email", .text)
                t.column("website", .text)
                t.column("hoursJson", .text)
                t.column("pricingModel", .text)
                t.column("priceMin", .double)
                t.column("priceMax", .double)
                t.column("acceptsMedicaid", .boolean).notNull().defaults(to: false)
                t.column("acceptsMedicare", .boolean).notNull().defaults(to: false)
                t.column("scholarshipsAvailable", .boolean).notNull().defaults(to: false)
                t.column("servicesJson", .text)
                t.column("verificationStatus", .text).notNull().defaults(to: "UNVERIFIED")
                t.column("avgRating", .double).notNull().defaults(to: 0)
                t.column("reviewCount", .integer).notNull().defaults(to: 0)
                t.column("cachedAt", .datetime).notNull()
            }

            // Respite Requests (local cache)
            try db.create(table: "respiteRequests") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull()
                t.column("patientId", .text).notNull()
                t.column("providerId", .text).notNull()
                t.column("createdBy", .text).notNull()
                t.column("startDate", .text).notNull()
                t.column("endDate", .text).notNull()
                t.column("specialConsiderations", .text)
                t.column("shareMedications", .boolean).notNull().defaults(to: false)
                t.column("shareContacts", .boolean).notNull().defaults(to: false)
                t.column("shareDietary", .boolean).notNull().defaults(to: false)
                t.column("shareFullSummary", .boolean).notNull().defaults(to: false)
                t.column("contactMethod", .text).notNull()
                t.column("contactValue", .text).notNull()
                t.column("status", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Respite Log (local cache)
            try db.create(table: "respiteLog") { t in
                t.column("id", .text).primaryKey()
                t.column("circleId", .text).notNull()
                t.column("patientId", .text).notNull()
                t.column("createdBy", .text).notNull()
                t.column("respiteType", .text).notNull()
                t.column("providerName", .text)
                t.column("startDate", .text).notNull()
                t.column("endDate", .text).notNull()
                t.column("totalDays", .integer).notNull()
                t.column("notes", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // Indexes
            try db.create(
                index: "idx_respiteProviders_type",
                on: "respiteProviders",
                columns: ["providerType"]
            )
            try db.create(
                index: "idx_respiteRequests_circle",
                on: "respiteRequests",
                columns: ["circleId", "status"]
            )
            try db.create(
                index: "idx_respiteLog_circle",
                on: "respiteLog",
                columns: ["circleId", "startDate"]
            )
        }

        return migrator
    }

    // MARK: - Helpers
    
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try databaseQueue.read(block)
    }
    
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try databaseQueue.write(block)
    }
}
