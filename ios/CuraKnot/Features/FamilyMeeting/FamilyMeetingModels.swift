import SwiftUI
import Foundation

// MARK: - Family Meeting Model

struct FamilyMeeting: Identifiable, Codable, Hashable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let createdBy: UUID

    var title: String
    var scheduledAt: Date
    var format: MeetingFormat
    var meetingLink: String?

    var status: MeetingStatus
    var startedAt: Date?
    var endedAt: Date?

    var summaryHandoffId: UUID?
    var recurrenceRule: String?
    var parentMeetingId: UUID?

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case title
        case scheduledAt = "scheduled_at"
        case format
        case meetingLink = "meeting_link"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case summaryHandoffId = "summary_handoff_id"
        case recurrenceRule = "recurrence_rule"
        case parentMeetingId = "parent_meeting_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var duration: TimeInterval? {
        guard let start = startedAt, let end = endedAt else { return nil }
        return end.timeIntervalSince(start)
    }

    var durationMinutes: Int? {
        guard let dur = duration else { return nil }
        return Int(dur / 60)
    }

    var isUpcoming: Bool {
        status == .scheduled && scheduledAt > Date()
    }

    var isPast: Bool {
        status == .completed || status == .cancelled
    }
}

// MARK: - Meeting Format

enum MeetingFormat: String, Codable, CaseIterable, Hashable {
    case inPerson = "IN_PERSON"
    case video = "VIDEO"

    var displayName: String {
        switch self {
        case .inPerson: return "In Person"
        case .video: return "Video Call"
        }
    }

    var icon: String {
        switch self {
        case .inPerson: return "person.2.fill"
        case .video: return "video.fill"
        }
    }
}

// MARK: - Meeting Status

enum MeetingStatus: String, Codable, CaseIterable, Hashable {
    case scheduled = "SCHEDULED"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"

    var displayName: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .scheduled: return .blue
        case .inProgress: return .green
        case .completed: return .secondary
        case .cancelled: return .red
        }
    }
}

// MARK: - Meeting Attendee

struct MeetingAttendee: Identifiable, Codable, Hashable {
    let id: UUID
    let meetingId: UUID
    let userId: UUID
    var status: AttendeeStatus
    let invitedAt: Date
    var respondedAt: Date?
    var userName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case meetingId = "meeting_id"
        case userId = "user_id"
        case status
        case invitedAt = "invited_at"
        case respondedAt = "responded_at"
        case userName = "user_name"
    }

    var displayName: String {
        userName ?? "Member"
    }
}

// MARK: - Attendee Status

enum AttendeeStatus: String, Codable, CaseIterable, Hashable {
    case invited = "INVITED"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case attended = "ATTENDED"

    var displayName: String {
        switch self {
        case .invited: return "Invited"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .attended: return "Attended"
        }
    }

    var color: Color {
        switch self {
        case .invited: return .blue
        case .accepted: return .green
        case .declined: return .red
        case .attended: return .secondary
        }
    }
}

// MARK: - Meeting Agenda Item

struct MeetingAgendaItem: Identifiable, Codable, Hashable {
    let id: UUID
    let meetingId: UUID
    let addedBy: UUID

    var title: String
    var description: String?
    var sortOrder: Int

    var status: AgendaItemStatus
    var notes: String?
    var decision: String?

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case meetingId = "meeting_id"
        case addedBy = "added_by"
        case title, description
        case sortOrder = "sort_order"
        case status, notes, decision
        case createdAt = "created_at"
    }
}

// MARK: - Agenda Item Status

enum AgendaItemStatus: String, Codable, CaseIterable, Hashable {
    case pending = "PENDING"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
    case skipped = "SKIPPED"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "Discussing"
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "forward.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .skipped: return .orange
        }
    }
}

// MARK: - Meeting Action Item

struct MeetingActionItem: Identifiable, Codable, Hashable {
    let id: UUID
    let meetingId: UUID
    var agendaItemId: UUID?

    var description: String
    var assignedTo: UUID?
    var dueDate: Date?
    var taskId: UUID?

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case meetingId = "meeting_id"
        case agendaItemId = "agenda_item_id"
        case description
        case assignedTo = "assigned_to"
        case dueDate = "due_date"
        case taskId = "task_id"
        case createdAt = "created_at"
    }

    var hasTask: Bool {
        taskId != nil
    }
}

// MARK: - Suggested Topic

struct SuggestedTopic: Identifiable, Hashable {
    let id = UUID()
    let type: TopicType
    let title: String
    let topicDescription: String
    let priority: Int
    let sourceId: UUID

    enum TopicType: String, Codable {
        case overdueTask = "OVERDUE_TASK"
        case binderChange = "BINDER_CHANGE"

        var icon: String {
            switch self {
            case .overdueTask: return "exclamationmark.circle"
            case .binderChange: return "folder.badge.gearshape"
            }
        }

        var color: Color {
            switch self {
            case .overdueTask: return .red
            case .binderChange: return .orange
            }
        }
    }
}
