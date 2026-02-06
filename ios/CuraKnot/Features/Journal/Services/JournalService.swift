import Foundation
import UIKit
import GRDB

// MARK: - Journal Service

/// Service for managing gratitude and milestone journal entries
/// Handles CRUD operations, usage checking, offline sync, and photo uploads
@MainActor
final class JournalService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isLoading = false
    @Published private(set) var entries: [JournalEntry] = []
    @Published private(set) var usageCheck: JournalUsageCheck?
    @Published private(set) var error: JournalServiceError?

    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient
    private let syncCoordinator: SyncCoordinator
    private let authManager: AuthManager

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        syncCoordinator: SyncCoordinator,
        authManager: AuthManager
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.syncCoordinator = syncCoordinator
        self.authManager = authManager
    }

    // MARK: - User ID

    private var currentUserId: String? {
        authManager.currentUser?.id
    }

    private func requireUserId() throws -> String {
        guard let userId = currentUserId else {
            throw JournalServiceError.notAuthenticated
        }
        return userId
    }

    // MARK: - Circle Membership Verification

    /// Verify user is an active member of the circle
    private func verifyCircleMembership(circleId: String, userId: String) async throws {
        struct MemberCheck: Decodable {
            let id: String
        }

        let members: [MemberCheck] = try await supabaseClient
            .from("circle_members")
            .select("id")
            .eq("circle_id", circleId)
            .eq("user_id", userId)
            .eq("status", "ACTIVE")
            .execute()

        guard !members.isEmpty else {
            throw JournalServiceError.notCircleMember
        }
    }

    // MARK: - Usage Checking

    /// Check if user can create a new journal entry (respects tier limits)
    func checkCanCreateEntry(circleId: String) async throws -> JournalUsageCheck {
        let userId = try requireUserId()
        
        // Verify user has access to this circle before checking usage
        try await verifyCircleMembership(circleId: circleId, userId: userId)

        let result: JournalUsageCheck = try await supabaseClient.rpc(
            "check_journal_usage",
            params: [
                "p_user_id": userId,
                "p_circle_id": circleId
            ]
        )

        usageCheck = result
        return result
    }

    /// Check if user has access to photo attachments (Plus+)
    func canAttachPhotos() async -> Bool {
        guard let userId = currentUserId else { return false }

        do {
            let hasAccess: Bool = try await supabaseClient.rpc(
                "has_feature_access",
                params: [
                    "p_user_id": userId,
                    "p_feature": "journal_photos"
                ]
            )
            return hasAccess
        } catch {
            return false
        }
    }

    /// Check if user can export Memory Book (Family only)
    func canExportMemoryBook() async -> Bool {
        guard let userId = currentUserId else { return false }

        do {
            let hasAccess: Bool = try await supabaseClient.rpc(
                "has_feature_access",
                params: [
                    "p_user_id": userId,
                    "p_feature": "memory_book_export"
                ]
            )
            return hasAccess
        } catch {
            return false
        }
    }

    // MARK: - Create Entry

    /// Create a new journal entry
    func createEntry(
        circleId: String,
        patientId: String,
        entryType: JournalEntryType,
        title: String? = nil,
        content: String,
        milestoneType: MilestoneType? = nil,
        visibility: EntryVisibility = .circle,
        entryDate: Date = Date(),
        photos: [UIImage] = []
    ) async throws -> JournalEntry {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let userId = try requireUserId()

        // Verify user is a member of this circle (security check)
        try await verifyCircleMembership(circleId: circleId, userId: userId)

        // Check usage limit
        let usage = try await checkCanCreateEntry(circleId: circleId)
        guard usage.allowed else {
            throw JournalServiceError.usageLimitReached(
                current: usage.current,
                limit: usage.limit ?? 5
            )
        }

        // Check photo access if photos provided
        if !photos.isEmpty {
            let canAddPhotos = await canAttachPhotos()
            guard canAddPhotos else {
                throw JournalServiceError.featureNotAvailable("Photo attachments")
            }
        }

        // Create entry ID first for photo paths
        let entryId = UUID().uuidString

        // Upload photos if any - with rollback tracking
        var photoStorageKeys: [String] = []
        
        do {
            if !photos.isEmpty {
                photoStorageKeys = try await JournalPhotoUploader.uploadMultiple(
                    images: photos,
                    circleId: circleId,
                    entryId: entryId,
                    supabaseClient: supabaseClient
                )
            }

            // Sanitize input content (XSS prevention)
            let sanitizedContent = content.sanitizedForDisplay
            let sanitizedTitle = title?.sanitizedForDisplay

            // Create entry with sanitized content
            let entry = JournalEntry(
                id: entryId,
                circleId: circleId,
                patientId: patientId,
                createdBy: userId,
                entryType: entryType,
                title: sanitizedTitle,
                content: sanitizedContent,
                milestoneType: milestoneType,
                photoStorageKeys: photoStorageKeys,
                visibility: visibility,
                entryDate: entryDate,
                createdAt: Date(),
                updatedAt: Date()
            )

            // Validate before saving
            try entry.validate()

            // Save locally first
            try databaseManager.write { db in
                try entry.save(db)
            }

            // Sync to remote - this must succeed before incrementing usage
            try await syncEntry(entry)

            // Only increment usage AFTER successful sync to prevent inflated counts
            try await supabaseClient.rpc(
                "increment_journal_usage",
                params: [
                    "p_user_id": userId,
                    "p_circle_id": circleId
                ]
            )

            // Update local list
            entries.insert(entry, at: 0)

            return entry
            
        } catch {
            // Rollback: Delete any uploaded photos if entry creation failed
            if !photoStorageKeys.isEmpty {
                for key in photoStorageKeys {
                    try? await supabaseClient.storage(JournalPhotoUploader.storageBucket).remove(path: key)
                }
            }
            throw error
        }
    }

    // MARK: - Read Entries

    /// Fetch entries for a circle with optional filtering
    func fetchEntries(
        circleId: String,
        filter: JournalFilter = .all
    ) async throws -> [JournalEntry] {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let userId = try requireUserId()

        // Verify user is a member of this circle (security check)
        try await verifyCircleMembership(circleId: circleId, userId: userId)

        // Read from local cache first
        let localEntries = try databaseManager.read { db in
            var query = JournalEntry
                .filter(Column("circle_id") == circleId)

            // Apply visibility filter (user sees own PRIVATE + all CIRCLE)
            query = query.filter(
                Column("created_by") == userId ||
                Column("visibility") == EntryVisibility.circle.rawValue
            )

            // Apply additional filters
            if let entryType = filter.entryType {
                query = query.filter(Column("entry_type") == entryType.rawValue)
            }

            if let patientId = filter.patientId {
                query = query.filter(Column("patient_id") == patientId)
            }

            if let startDate = filter.startDate {
                query = query.filter(Column("entry_date") >= startDate)
            }

            if let endDate = filter.endDate {
                query = query.filter(Column("entry_date") <= endDate)
            }

            if filter.privateOnly {
                query = query.filter(Column("visibility") == EntryVisibility.private.rawValue)
            }

            if filter.myEntriesOnly {
                query = query.filter(Column("created_by") == userId)
            }

            return try query
                .order(Column("entry_date").desc, Column("created_at").desc)
                .fetchAll(db)
        }

        entries = localEntries

        // Background sync
        Task {
            try? await syncEntries(circleId: circleId)
        }

        return localEntries
    }

    /// Fetch a single entry by ID with full authorization checks
    func fetchEntry(id: String) async throws -> JournalEntry {
        // Verify user is authenticated
        let userId = try requireUserId()
        
        // First fetch the entry to get its circleId and visibility
        let entries: [JournalEntry] = try await supabaseClient
            .from("journal_entries")
            .select()
            .eq("id", id)
            .execute()
        
        guard let entry = entries.first else {
            throw JournalServiceError.entryNotFound
        }
        
        // Verify user has access to this circle
        try await verifyCircleMembership(circleId: entry.circleId, userId: userId)
        
        // Check visibility permissions
        // Private entries can only be viewed by the author
        if entry.visibility == .private && entry.createdBy != userId {
            throw JournalServiceError.insufficientPermissions
        }
        
        return entry
    }

    // MARK: - Update Entry

    /// Updates an existing journal entry with full authorization checks
    func updateEntry(
        id: String,
        content: String? = nil,
        title: String? = nil,
        visibility: EntryVisibility? = nil,
        milestoneType: MilestoneType? = nil,
        tags: [String]? = nil
    ) async throws -> JournalEntry {
        let userId = try requireUserId()
        
        // First fetch the entry to verify ownership and get circleId
        let existingEntries: [JournalEntry] = try await supabaseClient
            .from("journal_entries")
            .select()
            .eq("id", id)
            .execute()
        
        guard let existingEntry = existingEntries.first else {
            throw JournalServiceError.entryNotFound
        }
        
        // Verify user still has access to this circle
        try await verifyCircleMembership(circleId: existingEntry.circleId, userId: userId)
        
        // Only the author can update an entry
        guard existingEntry.createdBy == userId else {
            throw JournalServiceError.insufficientPermissions
        }
        
        // Build update payload
        var updates: [String: Any] = [
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let content = content {
            updates["content"] = content.sanitizedForDisplay
        }
        if let title = title {
            updates["title"] = title.sanitizedForDisplay
        }
        if let visibility = visibility {
            updates["visibility"] = visibility.rawValue
        }
        if let milestoneType = milestoneType {
            updates["milestone_type"] = milestoneType.rawValue
        }
        
        let updated: [JournalEntry] = try await supabaseClient
            .from("journal_entries")
            .update(updates)
            .eq("id", id)
            .executeReturning()
        
        guard let entry = updated.first else {
            throw JournalServiceError.updateFailed
        }
        
        // Update local cache
        try databaseManager.write { db in
            try entry.save(db)
        }
        
        return entry
    }

    /// Update visibility of an entry
    func updateVisibility(entryId: String, newVisibility: EntryVisibility) async throws {
        // Use the new updateEntry API with visibility parameter
        _ = try await updateEntry(id: entryId, visibility: newVisibility)
    }

    // MARK: - Delete Entry

    /// Deletes a journal entry with full authorization checks
    func deleteEntry(id: String) async throws {
        let userId = try requireUserId()
        
        // First fetch the entry to verify ownership and get circleId
        let existingEntries: [JournalEntry] = try await supabaseClient
            .from("journal_entries")
            .select()
            .eq("id", id)
            .execute()
        
        guard let existingEntry = existingEntries.first else {
            throw JournalServiceError.entryNotFound
        }
        
        // Verify user still has access to this circle
        try await verifyCircleMembership(circleId: existingEntry.circleId, userId: userId)
        
        // Only the author can delete an entry
        guard existingEntry.createdBy == userId else {
            throw JournalServiceError.insufficientPermissions
        }
        
        // Delete associated photos from storage first
        if !existingEntry.photoStorageKeys.isEmpty {
            for key in existingEntry.photoStorageKeys {
                try? await supabaseClient.storage(JournalPhotoUploader.storageBucket).remove(path: key)
            }
        }
        
        // Delete from remote
        try await supabaseClient
            .from("journal_entries")
            .eq("id", id)
            .delete()
        
        // Delete from local cache
        try databaseManager.write { db in
            try JournalEntry.deleteOne(db, key: id)
        }
    }

    // MARK: - Sync

    /// Sync a single entry to Supabase
    private func syncEntry(_ entry: JournalEntry) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        let payload = try encoder.encode(entry)

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "UPSERT",
            entityType: "journal_entries",
            entityId: entry.id,
            payloadJson: String(data: payload, encoding: .utf8) ?? "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    /// Sync entry deletion to Supabase
    private func syncEntryDeletion(_ entryId: String) async throws {
        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "DELETE",
            entityType: "journal_entries",
            entityId: entryId,
            payloadJson: "{}",
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }

    /// Sync entries from remote for a circle
    private func syncEntries(circleId: String) async throws {
        // Fetch from Supabase (RLS will filter appropriately)
        let remoteEntries: [JournalEntry] = try await supabaseClient
            .from("journal_entries")
            .select()
            .eq("circle_id", circleId)
            .order("entry_date", ascending: false)
            .execute()

        // Merge into local database
        try databaseManager.write { db in
            for entry in remoteEntries {
                try entry.save(db)
            }
        }

        // Refresh local list
        _ = try await fetchEntries(circleId: circleId)
    }

    // MARK: - Prompts

    /// Fetch random prompts for entry suggestions
    func fetchPrompts(type: JournalEntryType, limit: Int = 3) async throws -> [JournalPrompt] {
        return try await supabaseClient
            .from("journal_prompts")
            .select()
            .eq("prompt_type", type.rawValue)
            .eq("is_active", "true")
            .limit(limit)
            .execute()
    }

    // MARK: - Memory Book Export

    /// Generates a Memory Book PDF export for the given circle
    /// - Parameters:
    ///   - circleId: The care circle ID
    ///   - patientId: Optional patient ID to filter entries
    ///   - dateRange: Optional date range for filtering
    /// - Returns: URL to the generated PDF
    func generateMemoryBook(
        circleId: String,
        patientId: String? = nil,
        dateRange: ClosedRange<Date>? = nil
    ) async throws -> URL {
        let userId = try requireUserId()
        
        // CRITICAL: Verify circle membership BEFORE checking tier
        try await verifyCircleMembership(circleId: circleId, userId: userId)
        
        // Verify Family tier access
        let canExport = await canExportMemoryBook()
        guard canExport else {
            throw JournalServiceError.featureNotAvailable("Memory Book export")
        }
        
        // Build request parameters
        var params: [String: Any] = [
            "circleId": circleId
        ]
        
        if let patientId = patientId {
            params["patientId"] = patientId
        }
        
        if let dateRange = dateRange {
            let formatter = ISO8601DateFormatter()
            params["startDate"] = formatter.string(from: dateRange.lowerBound)
            params["endDate"] = formatter.string(from: dateRange.upperBound)
        }
        
        // Call Edge Function to generate PDF
        struct MemoryBookRequest: Encodable {
            let circleId: String
            let patientId: String?
            let startDate: String?
            let endDate: String?
        }
        
        let formatter = ISO8601DateFormatter()
        let request = MemoryBookRequest(
            circleId: circleId,
            patientId: patientId,
            startDate: dateRange.map { formatter.string(from: $0.lowerBound) },
            endDate: dateRange.map { formatter.string(from: $0.upperBound) }
        )
        
        struct MemoryBookResponse: Decodable {
            let url: String
        }
        
        let response: MemoryBookResponse = try await supabaseClient
            .functions("generate-memory-book")
            .invoke(body: request)
        
        guard let url = URL(string: response.url) else {
            throw JournalServiceError.memoryBookGenerationFailed
        }
        
        return url
    }

    // MARK: - Grouped Entries

    /// Get entries grouped by date for timeline display
    func groupedEntries() -> [Date: [JournalEntry]] {
        let calendar = Calendar.current
        var grouped: [Date: [JournalEntry]] = [:]

        for entry in entries {
            let dateKey = calendar.startOfDay(for: entry.entryDate)
            if grouped[dateKey] != nil {
                grouped[dateKey]?.append(entry)
            } else {
                grouped[dateKey] = [entry]
            }
        }

        return grouped
    }
}

// MARK: - Response Types

struct MemoryBookResponse: Codable {
    let url: String
    let expiresAt: String
}

// MARK: - Service Errors

enum JournalServiceError: LocalizedError {
    case notAuthenticated
    case notCircleMember
    case insufficientPermissions
    case entryNotFound
    case updateFailed
    case notAuthor
    case validationFailed(String)
    case photoUploadFailed
    case syncFailed(Error)
    case featureNotAvailable(String)
    case featureRequiresFamilyTier
    case featureRequiresPlusTier
    case usageLimitReached(current: Int, limit: Int)
    case invalidResponse
    case memoryBookGenerationFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to use the journal."
        case .notCircleMember:
            return "You don't have access to this care circle."
        case .insufficientPermissions:
            return "You don't have permission to perform this action."
        case .entryNotFound:
            return "Entry not found."
        case .updateFailed:
            return "Failed to update the journal entry."
        case .notAuthor:
            return "You can only edit your own entries."
        case .validationFailed(let message):
            return message
        case .photoUploadFailed:
            return "Failed to upload photo. Please try again."
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .featureNotAvailable(let feature):
            return "\(feature) requires a Plus or Family subscription."
        case .featureRequiresFamilyTier:
            return "This feature requires a Family subscription."
        case .featureRequiresPlusTier:
            return "This feature requires a Plus or Family subscription."
        case .usageLimitReached(let current, let limit):
            return "You've used \(current)/\(limit) journal entries this month. Upgrade for unlimited entries."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .memoryBookGenerationFailed:
            return "Failed to generate Memory Book. Please try again."
        }
    }
}
