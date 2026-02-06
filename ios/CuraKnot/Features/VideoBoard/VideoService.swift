import Foundation
import GRDB

// MARK: - Video Service

/// Service for managing video messages, reactions, views, and storage
@MainActor
final class VideoService: ObservableObject {

    // MARK: - Types

    struct VideoQuotaStatus: Sendable {
        let allowed: Bool
        let featureLocked: Bool
        let plan: String
        let usedBytes: Int64
        let limitBytes: Int64
        let remainingBytes: Int64
        let maxDuration: Int
        let retentionDays: Int

        var usagePercent: Double {
            guard limitBytes > 0 else { return 0 }
            return (Double(usedBytes) / Double(limitBytes)) * 100
        }

        var usedMB: Double {
            Double(usedBytes) / 1_048_576
        }

        var limitMB: Double {
            Double(limitBytes) / 1_048_576
        }

        var remainingMB: Double {
            Double(remainingBytes) / 1_048_576
        }
    }

    /// Result of atomic quota reservation
    struct QuotaReservation: Sendable {
        let allowed: Bool
        let reservationId: UUID?
        let reservedBytes: Int64
        let availableAfter: Int64
        let error: String?
        let message: String?
        let usedBytes: Int64?
        let limitBytes: Int64?
    }

    struct RateLimitStatus: Sendable {
        let allowed: Bool
        let currentCount: Int
        let maxUploads: Int
        let windowHours: Int

        var remainingUploads: Int {
            max(0, maxUploads - currentCount)
        }
    }

    enum VideoServiceError: LocalizedError {
        case notAuthenticated
        case featureLocked
        case quotaExceeded(used: Int64, limit: Int64)
        case rateLimited(remainingTime: Int)
        case videoNotFound
        case uploadFailed(String)
        case networkError(Error)
        case databaseError(Error)
        case invalidResponse
        case invalidVideoFormat
        case reservationFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Please sign in to use video messages."
            case .featureLocked:
                return "Video messages require a Plus or Family subscription."
            case .quotaExceeded(let used, let limit):
                let usedMB = Double(used) / 1_048_576
                let limitMB = Double(limit) / 1_048_576
                return String(format: "Storage limit reached (%.0f MB / %.0f MB). Delete old videos or upgrade.", usedMB, limitMB)
            case .rateLimited(let remainingTime):
                return "Too many uploads. Please wait \(remainingTime) minutes before uploading again."
            case .videoNotFound:
                return "Video not found."
            case .uploadFailed(let message):
                return "Upload failed: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .databaseError(let error):
                return "Database error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Received an invalid response from the server."
            case .invalidVideoFormat:
                return "Invalid video format. Please record a new video."
            case .reservationFailed(let message):
                return "Could not reserve storage: \(message)"
            }
        }
    }

    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient
    private let subscriptionManager: SubscriptionManager
    private let authManager: AuthManager
    private let syncCoordinator: SyncCoordinator

    // MARK: - Published State

    @Published private(set) var isLoading = false

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        subscriptionManager: SubscriptionManager,
        authManager: AuthManager,
        syncCoordinator: SyncCoordinator
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.subscriptionManager = subscriptionManager
        self.authManager = authManager
        self.syncCoordinator = syncCoordinator
    }

    // MARK: - Quota & Access

    /// Check if user has access to video board feature
    func hasFeatureAccess() -> Bool {
        subscriptionManager.hasFeature(.familyVideoBoard)
    }

    /// Check video storage quota for a circle
    func checkQuota(circleId: String) async throws -> VideoQuotaStatus {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        struct QuotaResponse: Decodable {
            let allowed: Bool
            let featureLocked: Bool
            let plan: String
            let usedBytes: Int64
            let limitBytes: Int64
            let remainingBytes: Int64
            let maxDuration: Int?
            let retentionDays: Int?
            
            enum CodingKeys: String, CodingKey {
                case allowed
                case featureLocked = "feature_locked"
                case plan
                case usedBytes = "used_bytes"
                case limitBytes = "limit_bytes"
                case remainingBytes = "remaining_bytes"
                case maxDuration = "max_duration"
                case retentionDays = "retention_days"
            }
        }

        let result: QuotaResponse = try await supabaseClient.rpc(
            "check_video_quota",
            params: [
                "p_user_id": userId,
                "p_circle_id": circleId
            ]
        )

        return VideoQuotaStatus(
            allowed: result.allowed,
            featureLocked: result.featureLocked,
            plan: result.plan,
            usedBytes: result.usedBytes,
            limitBytes: result.limitBytes,
            remainingBytes: result.remainingBytes,
            maxDuration: result.maxDuration ?? 30,
            retentionDays: result.retentionDays ?? 30
        )
    }

    // MARK: - Rate Limiting

    /// Check if user is rate limited for uploads
    func checkRateLimit() async throws -> RateLimitStatus {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        struct RateLimitResponse: Decodable {
            let allowed: Bool
            let currentCount: Int
            let maxUploads: Int
            let windowHours: Int

            enum CodingKeys: String, CodingKey {
                case allowed
                case currentCount = "current_count"
                case maxUploads = "max_uploads"
                case windowHours = "window_hours"
            }
        }

        let result: RateLimitResponse = try await supabaseClient.rpc(
            "check_rate_limit",
            params: ["p_user_id": userId]
        )

        return RateLimitStatus(
            allowed: result.allowed,
            currentCount: result.currentCount,
            maxUploads: result.maxUploads,
            windowHours: result.windowHours
        )
    }

    // MARK: - Atomic Quota Reservation (TOCTOU-safe)

    /// Atomically reserve quota for a video upload (prevents race conditions)
    /// Returns a reservation ID that must be finalized after upload completes or fails
    func reserveQuota(circleId: String, requestedBytes: Int64) async throws -> QuotaReservation {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        struct ReserveResponse: Decodable {
            let allowed: Bool
            let reservationId: String?
            let reservedBytes: Int64?
            let availableAfter: Int64?
            let error: String?
            let message: String?
            let usedBytes: Int64?
            let limitBytes: Int64?

            enum CodingKeys: String, CodingKey {
                case allowed
                case reservationId = "reservation_id"
                case reservedBytes = "reserved_bytes"
                case availableAfter = "available_after"
                case error
                case message
                case usedBytes = "used_bytes"
                case limitBytes = "limit_bytes"
            }
        }

        let result: ReserveResponse = try await supabaseClient.rpc(
            "reserve_video_quota",
            params: [
                "p_user_id": userId,
                "p_circle_id": circleId,
                "p_requested_bytes": requestedBytes
            ]
        )

        return QuotaReservation(
            allowed: result.allowed,
            reservationId: result.reservationId.flatMap { UUID(uuidString: $0) },
            reservedBytes: result.reservedBytes ?? 0,
            availableAfter: result.availableAfter ?? 0,
            error: result.error,
            message: result.message,
            usedBytes: result.usedBytes,
            limitBytes: result.limitBytes
        )
    }

    /// Finalize a quota reservation (confirm upload or release on failure)
    func finalizeQuota(reservationId: UUID, finalize: Bool, actualBytes: Int64? = nil, storageKey: String? = nil) async throws {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        var params: [String: Any] = [
            "p_reservation_id": reservationId.uuidString,
            "p_user_id": userId,
            "p_finalize": finalize
        ]

        if let actualBytes = actualBytes {
            params["p_actual_bytes"] = actualBytes
        }
        if let storageKey = storageKey {
            params["p_storage_key"] = storageKey
        }

        try await supabaseClient.rpc(
            "finalize_video_quota",
            params: params
        )
    }

    // MARK: - Fetch Videos

    /// Fetch videos for a patient from local database
    func fetchVideos(patientId: String, circleId: String) async throws -> [VideoMessage] {
        try await readFromDatabase { db in
            try VideoMessage
                .filter(VideoMessage.Columns.patientId == patientId)
                .filter(VideoMessage.Columns.circleId == circleId)
                .filter(VideoMessage.Columns.status == VideoStatus.active.rawValue ||
                        VideoMessage.Columns.status == VideoStatus.flagged.rawValue)
                .order(VideoMessage.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Fetch videos with details (reaction count, author name) - optimized single query
    func fetchVideosWithDetails(patientId: String, circleId: String) async throws -> [VideoMessageWithDetails] {
        guard let currentUserId = authManager.currentUser?.id else {
            // If not authenticated, return basic data
            let videos = try await fetchVideos(patientId: patientId, circleId: circleId)
            return videos.map { video in
                VideoMessageWithDetails(
                    video: video,
                    authorName: "Unknown",
                    authorInitials: "?",
                    reactionCount: 0,
                    viewCount: 0,
                    hasUserReacted: false
                )
            }
        }

        // Use a single optimized query with JOINs to avoid N+1
        let sql = """
            SELECT 
                vm.*,
                u.display_name AS author_name,
                COALESCE(rc.reaction_count, 0) AS reaction_count,
                COALESCE(vc.view_count, 0) AS view_count,
                CASE WHEN ur.id IS NOT NULL THEN 1 ELSE 0 END AS has_user_reacted
            FROM video_messages vm
            LEFT JOIN users u ON u.id = vm.created_by
            LEFT JOIN (
                SELECT video_message_id, COUNT(*) AS reaction_count
                FROM video_reactions
                GROUP BY video_message_id
            ) rc ON rc.video_message_id = vm.id
            LEFT JOIN (
                SELECT video_message_id, COUNT(*) AS view_count
                FROM video_views
                GROUP BY video_message_id
            ) vc ON vc.video_message_id = vm.id
            LEFT JOIN video_reactions ur ON ur.video_message_id = vm.id AND ur.user_id = ?
            WHERE vm.patient_id = ? 
              AND vm.circle_id = ?
              AND vm.status IN ('ACTIVE', 'FLAGGED')
            ORDER BY vm.created_at DESC
            """

        struct VideoWithDetailsRow: FetchableRecord, Decodable {
            let id: String
            let circleId: String
            let patientId: String
            let createdBy: String
            let storageKey: String
            let thumbnailKey: String?
            let durationSeconds: Int
            let fileSizeBytes: Int64
            let caption: String?
            let status: String
            let flaggedBy: String?
            let flaggedAt: Date?
            let removedBy: String?
            let removedAt: Date?
            let removalReason: String?
            let saveForever: Bool
            let expiresAt: Date?
            let retentionDays: Int
            let createdAt: Date
            let updatedAt: Date
            let processedAt: Date?
            let authorName: String?
            let reactionCount: Int
            let viewCount: Int
            let hasUserReacted: Int
            
            enum CodingKeys: String, CodingKey {
                case id
                case circleId = "circle_id"
                case patientId = "patient_id"
                case createdBy = "created_by"
                case storageKey = "storage_key"
                case thumbnailKey = "thumbnail_key"
                case durationSeconds = "duration_seconds"
                case fileSizeBytes = "file_size_bytes"
                case caption
                case status
                case flaggedBy = "flagged_by"
                case flaggedAt = "flagged_at"
                case removedBy = "removed_by"
                case removedAt = "removed_at"
                case removalReason = "removal_reason"
                case saveForever = "save_forever"
                case expiresAt = "expires_at"
                case retentionDays = "retention_days"
                case createdAt = "created_at"
                case updatedAt = "updated_at"
                case processedAt = "processed_at"
                case authorName = "author_name"
                case reactionCount = "reaction_count"
                case viewCount = "view_count"
                case hasUserReacted = "has_user_reacted"
            }
        }

        let rows = try await readFromDatabase { db in
            try VideoWithDetailsRow.fetchAll(db, sql: sql, arguments: [currentUserId, patientId, circleId])
        }

        return rows.map { row in
            let video = VideoMessage(
                id: row.id,
                circleId: row.circleId,
                patientId: row.patientId,
                createdBy: row.createdBy,
                storageKey: row.storageKey,
                thumbnailKey: row.thumbnailKey,
                durationSeconds: row.durationSeconds,
                fileSizeBytes: row.fileSizeBytes,
                caption: row.caption,
                status: VideoStatus(rawValue: row.status) ?? .active,
                flaggedBy: row.flaggedBy,
                flaggedAt: row.flaggedAt,
                removedBy: row.removedBy,
                removedAt: row.removedAt,
                removalReason: row.removalReason,
                saveForever: row.saveForever,
                expiresAt: row.expiresAt,
                retentionDays: row.retentionDays,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                processedAt: row.processedAt
            )
            
            let authorName = row.authorName ?? "Unknown"
            let initials = authorName.split(separator: " ")
                .prefix(2)
                .compactMap { $0.first }
                .map(String.init)
                .joined()
                .uppercased()
            
            return VideoMessageWithDetails(
                video: video,
                authorName: authorName,
                authorInitials: initials.isEmpty ? "?" : initials,
                reactionCount: row.reactionCount,
                viewCount: row.viewCount,
                hasUserReacted: row.hasUserReacted == 1
            )
        }
    }

    /// Sync videos from server
    func syncVideos(circleId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        // Fetch from Supabase
        struct VideoRow: Decodable {
            let id: String
            let circle_id: String
            let patient_id: String
            let created_by: String
            let storage_key: String
            let thumbnail_key: String?
            let duration_seconds: Int
            let file_size_bytes: Int64
            let caption: String?
            let status: String
            let flagged_by: String?
            let flagged_at: Date?
            let removed_by: String?
            let removed_at: Date?
            let removal_reason: String?
            let save_forever: Bool
            let expires_at: Date?
            let retention_days: Int
            let created_at: Date
            let updated_at: Date
            let processed_at: Date?
        }

        let (data, _) = try await supabaseClient.request(
            path: "rest/v1/video_messages?circle_id=eq.\(circleId)&status=in.(ACTIVE,FLAGGED)&order=created_at.desc",
            method: "GET"
        )

        let rows = try JSONDecoder.supabase.decode([VideoRow].self, from: data)

        // Save to local database off main thread
        try await writeToDatabase { db in
            for row in rows {
                let video = VideoMessage(
                    id: row.id,
                    circleId: row.circle_id,
                    patientId: row.patient_id,
                    createdBy: row.created_by,
                    storageKey: row.storage_key,
                    thumbnailKey: row.thumbnail_key,
                    durationSeconds: row.duration_seconds,
                    fileSizeBytes: row.file_size_bytes,
                    caption: row.caption,
                    status: VideoStatus(rawValue: row.status) ?? .active,
                    flaggedBy: row.flagged_by,
                    flaggedAt: row.flagged_at,
                    removedBy: row.removed_by,
                    removedAt: row.removed_at,
                    removalReason: row.removal_reason,
                    saveForever: row.save_forever,
                    expiresAt: row.expires_at,
                    retentionDays: row.retention_days,
                    createdAt: row.created_at,
                    updatedAt: row.updated_at,
                    processedAt: row.processed_at
                )
                try video.save(db)
            }
        }

        // Also sync reactions
        try await syncReactions(circleId: circleId)
    }

    private func syncReactions(circleId: String) async throws {
        struct ReactionRow: Decodable {
            let id: String
            let video_message_id: String
            let user_id: String
            let reaction_type: String
            let created_at: Date
        }

        // Get video IDs for this circle off main thread
        let videoIds = try await readFromDatabase { db in
            try VideoMessage
                .filter(VideoMessage.Columns.circleId == circleId)
                .select(VideoMessage.Columns.id)
                .fetchAll(db)
                .map { $0.id }
        }

        guard !videoIds.isEmpty else { return }

        let videoIdsString = videoIds.map { "\"\($0)\"" }.joined(separator: ",")

        let (data, _) = try await supabaseClient.request(
            path: "rest/v1/video_reactions?video_message_id=in.(\(videoIdsString))",
            method: "GET"
        )

        let rows = try JSONDecoder.supabase.decode([ReactionRow].self, from: data)

        try await writeToDatabase { db in
            for row in rows {
                let reaction = VideoReaction(
                    id: row.id,
                    videoMessageId: row.video_message_id,
                    userId: row.user_id,
                    reactionType: ReactionType(rawValue: row.reaction_type) ?? .love,
                    createdAt: row.created_at
                )
                try reaction.save(db)
            }
        }
    }

    // MARK: - Create Video

    /// Convenience method to upload a compressed video
    func uploadVideo(
        url: URL,
        circleId: String,
        patientId: String,
        caption: String?,
        durationSeconds: Double,
        progressHandler: @escaping @Sendable (Double) async -> Void
    ) async throws -> VideoMessage {
        // Get file size off main thread to avoid blocking UI
        let fileSizeBytes = try await Task.detached {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        }.value

        // Check rate limit first (client-side check for UX)
        let rateLimit = try await checkRateLimit()
        if !rateLimit.allowed {
            throw VideoServiceError.rateLimited(remainingTime: rateLimit.windowHours * 60)
        }

        // Get retention days from subscription
        let quota = try await checkQuota(circleId: circleId)

        return try await uploadVideo(
            localURL: url,
            circleId: circleId,
            patientId: patientId,
            caption: caption,
            durationSeconds: Int(durationSeconds),
            fileSizeBytes: fileSizeBytes,
            retentionDays: quota.retentionDays,
            progressHandler: progressHandler
        )
    }

    /// Upload a video to storage and create the video message record
    func uploadVideo(
        localURL: URL,
        circleId: String,
        patientId: String,
        caption: String?,
        durationSeconds: Int,
        fileSizeBytes: Int64,
        retentionDays: Int,
        progressHandler: @escaping @Sendable (Double) async -> Void
    ) async throws -> VideoMessage {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        // Step 1: Atomically reserve quota (TOCTOU-safe)
        let reservation = try await reserveQuota(circleId: circleId, requestedBytes: fileSizeBytes)

        // Handle reservation failures
        if !reservation.allowed {
            switch reservation.error {
            case "FEATURE_LOCKED":
                throw VideoServiceError.featureLocked
            case "QUOTA_EXCEEDED":
                throw VideoServiceError.quotaExceeded(
                    used: reservation.usedBytes ?? 0,
                    limit: reservation.limitBytes ?? 0
                )
            default:
                throw VideoServiceError.reservationFailed(reservation.message ?? "Unknown error")
            }
        }

        // Must have a reservation ID to proceed
        guard let reservationId = reservation.reservationId else {
            throw VideoServiceError.reservationFailed("No reservation ID returned")
        }

        // Generate storage key using reservation ID
        let storageKey = "\(circleId)/\(reservationId.uuidString).mp4"

        // Create local record (status = UPLOADING)
        let expiresAt = Calendar.current.date(byAdding: .day, value: retentionDays, to: Date())

        var video = VideoMessage(
            id: reservationId.uuidString,
            circleId: circleId,
            patientId: patientId,
            createdBy: userId,
            storageKey: storageKey,
            durationSeconds: durationSeconds,
            fileSizeBytes: fileSizeBytes,
            caption: caption,
            status: .uploading,
            expiresAt: expiresAt,
            retentionDays: retentionDays
        )

        // Write to database off main thread
        try await writeToDatabase { db in
            try video.save(db)
        }

        do {
            // Step 2: Upload video data to Supabase Storage (off main thread for file I/O)
            let videoData = try await Task.detached {
                try Data(contentsOf: localURL)
            }.value

            await progressHandler(0.1)

            _ = try await supabaseClient.storage("video-messages")
                .upload(path: storageKey, data: videoData, contentType: "video/mp4")

            await progressHandler(0.7)

            // Step 3: Call Edge Function to process (generate thumbnail, update record)
            let processResult = try await processVideoUpload(
                videoId: reservationId.uuidString,
                circleId: circleId,
                patientId: patientId,
                storageKey: storageKey,
                caption: caption,
                durationSeconds: durationSeconds,
                fileSizeBytes: fileSizeBytes,
                retentionDays: retentionDays
            )

            await progressHandler(0.9)

            // Step 4: Finalize the reservation (confirm success)
            try await finalizeQuota(
                reservationId: reservationId,
                finalize: true,
                actualBytes: fileSizeBytes,
                storageKey: storageKey
            )

            // Update local record with processing result
            video.status = .active
            video.thumbnailKey = processResult.thumbnailKey
            video.processedAt = Date()

            try await writeToDatabase { db in
                try video.update(db)
            }

            await progressHandler(1.0)

            return video

        } catch {
            // Step 4 (failure): Release the quota reservation
            try? await finalizeQuota(reservationId: reservationId, finalize: false)

            // Mark as failed in local database
            video.status = .deleted
            try? await writeToDatabase { db in
                try video.update(db)
            }

            // Clean up storage if upload partially succeeded
            try? await supabaseClient.storage("video-messages").remove(path: storageKey)

            throw VideoServiceError.uploadFailed(error.localizedDescription)
        }
    }

    // MARK: - Database Helpers (Off Main Thread)

    /// Write to database without blocking main thread
    private func writeToDatabase(_ block: @escaping (Database) throws -> Void) async throws {
        try await Task.detached { [databaseManager] in
            try databaseManager.write(block)
        }.value
    }

    /// Read from database without blocking main thread
    private func readFromDatabase<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await Task.detached { [databaseManager] in
            try databaseManager.read(block)
        }.value
    }

    private func processVideoUpload(
        videoId: String,
        circleId: String,
        patientId: String,
        storageKey: String,
        caption: String?,
        durationSeconds: Int,
        fileSizeBytes: Int64,
        retentionDays: Int
    ) async throws -> ProcessVideoResponse {
        struct ProcessRequest: Encodable {
            let videoId: String
            let circleId: String
            let patientId: String
            let storageKey: String
            let caption: String?
            let durationSeconds: Int
            let fileSizeBytes: Int64
            let retentionDays: Int
        }

        let request = ProcessRequest(
            videoId: videoId,
            circleId: circleId,
            patientId: patientId,
            storageKey: storageKey,
            caption: caption,
            durationSeconds: durationSeconds,
            fileSizeBytes: fileSizeBytes,
            retentionDays: retentionDays
        )

        let body = try JSONEncoder.supabase.encode(request)

        let (data, _) = try await supabaseClient.request(
            path: "functions/v1/process-video-upload",
            method: "POST",
            body: body
        )

        return try JSONDecoder.supabase.decode(ProcessVideoResponse.self, from: data)
    }

    // MARK: - Delete Video

    /// Delete a video (soft delete - marks as DELETED)
    func deleteVideo(id: String) async throws {
        // Update server
        let body = try JSONSerialization.data(withJSONObject: ["status": "DELETED"])

        _ = try await supabaseClient.request(
            path: "rest/v1/video_messages?id=eq.\(id)",
            method: "PATCH",
            body: body
        )

        // Update local database (off main thread)
        try await writeToDatabase { db in
            if var video = try VideoMessage.fetchOne(db, key: id) {
                video.status = .deleted
                try video.update(db)
            }
        }
    }

    // MARK: - Moderation

    /// Flag a video as inappropriate
    func flagVideo(id: String) async throws {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        let body = try JSONSerialization.data(withJSONObject: [
            "status": "FLAGGED",
            "flagged_by": userId,
            "flagged_at": ISO8601DateFormatter().string(from: Date())
        ])

        _ = try await supabaseClient.request(
            path: "rest/v1/video_messages?id=eq.\(id)",
            method: "PATCH",
            body: body
        )

        try await writeToDatabase { db in
            if var video = try VideoMessage.fetchOne(db, key: id) {
                video.status = .flagged
                video.flaggedBy = userId
                video.flaggedAt = Date()
                try video.update(db)
            }
        }
    }

    /// Remove a video (admin action)
    func removeVideo(id: String, reason: String) async throws {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        let body = try JSONSerialization.data(withJSONObject: [
            "status": "REMOVED",
            "removed_by": userId,
            "removed_at": ISO8601DateFormatter().string(from: Date()),
            "removal_reason": reason
        ])

        _ = try await supabaseClient.request(
            path: "rest/v1/video_messages?id=eq.\(id)",
            method: "PATCH",
            body: body
        )

        try await writeToDatabase { db in
            if var video = try VideoMessage.fetchOne(db, key: id) {
                video.status = .removed
                video.removedBy = userId
                video.removedAt = Date()
                video.removalReason = reason
                try video.update(db)
            }
        }
    }

    /// Toggle save forever for a video
    func toggleSaveForever(id: String) async throws {
        guard let video = try await readFromDatabase({ db in
            try VideoMessage.fetchOne(db, key: id)
        }) else {
            throw VideoServiceError.videoNotFound
        }

        let newValue = !video.saveForever
        let newExpiresAt: Date? = newValue ? nil : Calendar.current.date(byAdding: .day, value: video.retentionDays, to: Date())

        var bodyDict: [String: Any] = ["save_forever": newValue]
        if let expiresAt = newExpiresAt {
            bodyDict["expires_at"] = ISO8601DateFormatter().string(from: expiresAt)
        } else {
            bodyDict["expires_at"] = NSNull()
        }

        let body = try JSONSerialization.data(withJSONObject: bodyDict)

        _ = try await supabaseClient.request(
            path: "rest/v1/video_messages?id=eq.\(id)",
            method: "PATCH",
            body: body
        )

        try await writeToDatabase { db in
            if var video = try VideoMessage.fetchOne(db, key: id) {
                video.saveForever = newValue
                video.expiresAt = newExpiresAt
                try video.update(db)
            }
        }
    }

    // MARK: - Reactions

    /// Add a "Send Love" reaction to a video
    func addReaction(videoId: String) async throws -> VideoReaction {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        let reaction = VideoReaction(
            videoMessageId: videoId,
            userId: userId
        )

        // Save to server
        let body = try JSONEncoder.supabase.encode(reaction)

        _ = try await supabaseClient.request(
            path: "rest/v1/video_reactions",
            method: "POST",
            body: body,
            headers: ["Prefer": "return=minimal"]
        )

        // Save locally (off main thread)
        try await writeToDatabase { db in
            try reaction.save(db)
        }

        return reaction
    }

    /// Remove a reaction from a video
    func removeReaction(videoId: String) async throws {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        // Delete from server
        _ = try await supabaseClient.request(
            path: "rest/v1/video_reactions?video_message_id=eq.\(videoId)&user_id=eq.\(userId)",
            method: "DELETE"
        )

        // Delete locally (off main thread)
        try await writeToDatabase { db in
            try VideoReaction
                .filter(VideoReaction.Columns.videoMessageId == videoId)
                .filter(VideoReaction.Columns.userId == userId)
                .deleteAll(db)
        }
    }

    /// Toggle reaction on a video atomically (prevents race conditions)
    func toggleReaction(videoId: String) async throws {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        struct ToggleResponse: Decodable {
            let action: String
            let reactionId: String?

            enum CodingKeys: String, CodingKey {
                case action
                case reactionId = "reaction_id"
            }
        }

        // Use atomic RPC to toggle reaction (prevents race conditions)
        let result: ToggleResponse = try await supabaseClient.rpc(
            "toggle_video_reaction",
            params: [
                "p_video_id": videoId,
                "p_user_id": userId,
                "p_reaction_type": "LOVE"
            ]
        )

        // Sync local database based on result
        try await writeToDatabase { db in
            if result.action == "ADDED", let reactionIdString = result.reactionId {
                let reaction = VideoReaction(
                    id: reactionIdString,
                    videoMessageId: videoId,
                    userId: userId
                )
                try reaction.save(db)
            } else if result.action == "REMOVED" {
                try VideoReaction
                    .filter(VideoReaction.Columns.videoMessageId == videoId)
                    .filter(VideoReaction.Columns.userId == userId)
                    .deleteAll(db)
            }
        }
    }

    // MARK: - Views

    /// Record a view for a video atomically (idempotent - once per user per day)
    func recordView(videoId: String, watchDurationSeconds: Int = 0) async throws {
        guard let userId = authManager.currentUser?.id else {
            throw VideoServiceError.notAuthenticated
        }

        struct ViewResponse: Decodable {
            let action: String
            let viewId: String?

            enum CodingKeys: String, CodingKey {
                case action
                case viewId = "view_id"
            }
        }

        // Use atomic RPC to record view (prevents duplicates, handles concurrency)
        let result: ViewResponse = try await supabaseClient.rpc(
            "record_video_view",
            params: [
                "p_video_id": videoId,
                "p_user_id": userId,
                "p_watch_duration_seconds": watchDurationSeconds
            ]
        )

        // Only save locally if this was a new view
        if result.action == "RECORDED", let viewIdString = result.viewId {
            try await writeToDatabase { db in
                let view = VideoView(
                    id: viewIdString,
                    videoMessageId: videoId,
                    viewedBy: userId
                )
                try view.save(db)
            }
        }
    }

    // MARK: - Storage URLs

    /// Get signed URL for video playback
    func getVideoURL(storageKey: String) async throws -> URL {
        try await supabaseClient.storage("video-messages")
            .createSignedURL(path: storageKey, expiresIn: 3600)
    }

    /// Get signed URL for thumbnail
    func getThumbnailURL(thumbnailKey: String) async throws -> URL {
        try await supabaseClient.storage("video-messages")
            .createSignedURL(path: thumbnailKey, expiresIn: 3600)
    }
}

// MARK: - Response Types

private struct ProcessVideoResponse: Decodable {
    let success: Bool
    let videoMessageId: String?
    let thumbnailKey: String?
    let error: ErrorDetail?

    struct ErrorDetail: Decodable {
        let code: String
        let message: String
    }
}
