import Foundation
import GRDB

// MARK: - Video Reaction Model

/// Represents a "Send Love" reaction on a video message
struct VideoReaction: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let videoMessageId: String
    let userId: String
    var reactionType: ReactionType
    let createdAt: Date

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        videoMessageId: String,
        userId: String,
        reactionType: ReactionType = .love,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.videoMessageId = videoMessageId
        self.userId = userId
        self.reactionType = reactionType
        self.createdAt = createdAt
    }
}

// MARK: - Reaction Type

enum ReactionType: String, Codable, Sendable {
    case love = "LOVE"

    var emoji: String {
        switch self {
        case .love: return "❤️"
        }
    }
}

// MARK: - GRDB Conformance

extension VideoReaction: FetchableRecord, PersistableRecord {
    static let databaseTableName = "video_reactions"

    enum Columns: String, ColumnExpression {
        case id
        case videoMessageId = "video_message_id"
        case userId = "user_id"
        case reactionType = "reaction_type"
        case createdAt = "created_at"
    }
}

// MARK: - Associations

extension VideoReaction {
    static let videoMessage = belongsTo(VideoMessage.self, using: ForeignKey(["videoMessageId"], to: ["id"]))

    var videoMessage: QueryInterfaceRequest<VideoMessage> {
        request(for: VideoReaction.videoMessage)
    }
}
