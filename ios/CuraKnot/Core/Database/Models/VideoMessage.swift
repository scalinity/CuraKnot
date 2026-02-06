import Foundation
import GRDB

// MARK: - Video Message Model

/// Represents a video message shared within a care circle for emotional connection
struct VideoMessage: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String

    // Storage
    let storageKey: String
    var thumbnailKey: String?
    let durationSeconds: Int
    let fileSizeBytes: Int64

    // Content
    var caption: String?

    // Status
    var status: VideoStatus
    var flaggedBy: String?
    var flaggedAt: Date?
    var removedBy: String?
    var removedAt: Date?
    var removalReason: String?

    // Retention
    var saveForever: Bool
    var expiresAt: Date?
    var retentionDays: Int

    // Timestamps
    let createdAt: Date
    var updatedAt: Date
    var processedAt: Date?

    // MARK: - Computed Properties

    var isActive: Bool { status == .active }
    var isFlagged: Bool { status == .flagged }
    var isRemoved: Bool { status == .removed }
    var isProcessing: Bool { status == .processing || status == .uploading || status == .pending }

    var durationFormatted: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: "0:%02d", seconds)
    }

    var fileSizeMB: Double {
        Double(fileSizeBytes) / 1_048_576.0
    }

    var expiresInDays: Int? {
        guard let expiresAt = expiresAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day
        return max(0, days ?? 0)
    }

    var relativeTimeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        circleId: String,
        patientId: String,
        createdBy: String,
        storageKey: String,
        thumbnailKey: String? = nil,
        durationSeconds: Int,
        fileSizeBytes: Int64,
        caption: String? = nil,
        status: VideoStatus = .uploading,
        flaggedBy: String? = nil,
        flaggedAt: Date? = nil,
        removedBy: String? = nil,
        removedAt: Date? = nil,
        removalReason: String? = nil,
        saveForever: Bool = false,
        expiresAt: Date? = nil,
        retentionDays: Int = 30,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        processedAt: Date? = nil
    ) {
        self.id = id
        self.circleId = circleId
        self.patientId = patientId
        self.createdBy = createdBy
        self.storageKey = storageKey
        self.thumbnailKey = thumbnailKey
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.caption = caption
        self.status = status
        self.flaggedBy = flaggedBy
        self.flaggedAt = flaggedAt
        self.removedBy = removedBy
        self.removedAt = removedAt
        self.removalReason = removalReason
        self.saveForever = saveForever
        self.expiresAt = expiresAt
        self.retentionDays = retentionDays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.processedAt = processedAt
    }
}

// MARK: - Video Status

enum VideoStatus: String, Codable, Sendable {
    case pending = "PENDING"      // Quota reserved, upload not started
    case uploading = "UPLOADING"
    case processing = "PROCESSING"
    case active = "ACTIVE"
    case flagged = "FLAGGED"
    case removed = "REMOVED"
    case deleted = "DELETED"
}

// MARK: - GRDB Conformance

extension VideoMessage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "video_messages"

    enum Columns: String, ColumnExpression {
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
    }
}

// MARK: - Associations

extension VideoMessage {
    static let patient = belongsTo(Patient.self, using: ForeignKey(["patientId"], to: ["id"]))
    static let reactions = hasMany(VideoReaction.self)
    static let views = hasMany(VideoView.self)

    var patient: QueryInterfaceRequest<Patient> {
        request(for: VideoMessage.patient)
    }

    var reactions: QueryInterfaceRequest<VideoReaction> {
        request(for: VideoMessage.reactions)
    }

    var views: QueryInterfaceRequest<VideoView> {
        request(for: VideoMessage.views)
    }
}

// MARK: - Video Message with Details

/// VideoMessage with additional fetched data (reaction count, author info)
struct VideoMessageWithDetails: Codable, Identifiable, Equatable {
    let video: VideoMessage
    let authorName: String
    let authorInitials: String
    var reactionCount: Int
    var viewCount: Int
    var hasUserReacted: Bool

    var id: String { video.id }
}
