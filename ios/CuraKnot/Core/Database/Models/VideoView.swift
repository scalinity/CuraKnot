import Foundation
import GRDB

// MARK: - Video View Model

/// Tracks when a user views a video message
struct VideoView: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let videoMessageId: String
    let viewedBy: String
    let viewedAt: Date

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        videoMessageId: String,
        viewedBy: String,
        viewedAt: Date = Date()
    ) {
        self.id = id
        self.videoMessageId = videoMessageId
        self.viewedBy = viewedBy
        self.viewedAt = viewedAt
    }
}

// MARK: - GRDB Conformance

extension VideoView: FetchableRecord, PersistableRecord {
    static let databaseTableName = "video_views"

    enum Columns: String, ColumnExpression {
        case id
        case videoMessageId = "video_message_id"
        case viewedBy = "viewed_by"
        case viewedAt = "viewed_at"
    }
}

// MARK: - Associations

extension VideoView {
    static let videoMessage = belongsTo(VideoMessage.self, using: ForeignKey(["videoMessageId"], to: ["id"]))

    var videoMessage: QueryInterfaceRequest<VideoMessage> {
        request(for: VideoView.videoMessage)
    }
}
