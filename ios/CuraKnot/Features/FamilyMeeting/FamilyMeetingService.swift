import Foundation

// MARK: - Family Meeting Service

@MainActor
final class FamilyMeetingService: ObservableObject {
    private let supabaseClient: SupabaseClient

    init(supabaseClient: SupabaseClient) {
        self.supabaseClient = supabaseClient
    }

    // MARK: - Meetings CRUD

    func fetchMeetings(circleId: UUID) async throws -> [FamilyMeeting] {
        return try await supabaseClient
            .from("family_meetings")
            .select()
            .eq("circle_id", circleId.uuidString)
            .order("scheduled_at", ascending: false)
            .execute()
    }

    func createMeeting(
        circleId: UUID,
        patientId: UUID,
        createdBy: UUID,
        title: String,
        scheduledAt: Date,
        format: MeetingFormat,
        meetingLink: String?,
        recurrenceRule: String?,
        attendeeUserIds: [UUID]
    ) async throws -> FamilyMeeting {
        let sanitizedTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !sanitizedTitle.isEmpty else {
            throw NSError(domain: "FamilyMeetingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Meeting title cannot be empty"])
        }

        let meetingId = UUID()
        var body: [String: Any] = [
            "id": meetingId.uuidString,
            "circle_id": circleId.uuidString,
            "patient_id": patientId.uuidString,
            "created_by": createdBy.uuidString,
            "title": sanitizedTitle,
            "scheduled_at": ISO8601DateFormatter().string(from: scheduledAt),
            "format": format.rawValue,
        ]
        if let meetingLink = meetingLink?.trimmingCharacters(in: .whitespacesAndNewlines), !meetingLink.isEmpty {
            guard let url = URL(string: meetingLink),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                throw NSError(domain: "FamilyMeetingService", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Meeting link must be an http or https URL"])
            }
            body["meeting_link"] = String(meetingLink.prefix(2048))
        }
        if let recurrenceRule = recurrenceRule {
            let sanitizedRule = String(recurrenceRule.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
            let validPrefixes = ["FREQ=DAILY", "FREQ=WEEKLY", "FREQ=BIWEEKLY", "FREQ=MONTHLY"]
            guard validPrefixes.contains(where: { sanitizedRule.hasPrefix($0) }) else {
                throw NSError(domain: "FamilyMeetingService", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid recurrence rule format"])
            }
            body["recurrence_rule"] = sanitizedRule
        }

        try await supabaseClient
            .from("family_meetings")
            .insert(body)
            .execute()

        // Fetch the created meeting by its known UUID (no race condition)
        let meetings: [FamilyMeeting] = try await supabaseClient
            .from("family_meetings")
            .select()
            .eq("id", meetingId.uuidString)
            .limit(1)
            .execute()

        guard let meeting = meetings.first else {
            throw NSError(domain: "FamilyMeetingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create meeting"])
        }

        // Add attendees (best-effort: meeting is created even if attendee adds partially fail)
        if !attendeeUserIds.isEmpty {
            do {
                try await addAttendees(meetingId: meeting.id, userIds: attendeeUserIds)
            } catch {
                // Meeting was created successfully — return it even if attendees partially failed.
                // Attendees can be re-added later.
                return meeting
            }
        }

        return meeting
    }

    func startMeeting(_ meetingId: UUID) async throws {
        // Server-side status validation via conditional update
        try await supabaseClient
            .from("family_meetings")
            .update([
                "status": MeetingStatus.inProgress.rawValue,
                "started_at": ISO8601DateFormatter().string(from: Date()),
            ])
            .eq("id", meetingId.uuidString)
            .eq("status", MeetingStatus.scheduled.rawValue)
            .execute()

        // Verify the update took effect (select only status for efficiency)
        let meetings: [FamilyMeeting] = try await supabaseClient
            .from("family_meetings")
            .select()
            .eq("id", meetingId.uuidString)
            .limit(1)
            .execute()

        guard let meeting = meetings.first, meeting.status == .inProgress else {
            throw NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start meeting — it may have already been started or cancelled"])
        }
    }

    func endMeeting(_ meetingId: UUID) async throws {
        // Server-side status validation via conditional update
        try await supabaseClient
            .from("family_meetings")
            .update([
                "status": MeetingStatus.completed.rawValue,
                "ended_at": ISO8601DateFormatter().string(from: Date()),
            ])
            .eq("id", meetingId.uuidString)
            .eq("status", MeetingStatus.inProgress.rawValue)
            .execute()

        // Verify the update took effect
        let meetings: [FamilyMeeting] = try await supabaseClient
            .from("family_meetings")
            .select()
            .eq("id", meetingId.uuidString)
            .limit(1)
            .execute()

        guard let meeting = meetings.first, meeting.status == .completed else {
            throw NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to end meeting — it may not be in progress"])
        }
    }

    func cancelMeeting(_ meetingId: UUID) async throws {
        // Server-side status validation via conditional update
        try await supabaseClient
            .from("family_meetings")
            .update([
                "status": MeetingStatus.cancelled.rawValue,
            ])
            .eq("id", meetingId.uuidString)
            .eq("status", MeetingStatus.scheduled.rawValue)
            .execute()

        // Verify the update took effect
        let meetings: [FamilyMeeting] = try await supabaseClient
            .from("family_meetings")
            .select()
            .eq("id", meetingId.uuidString)
            .limit(1)
            .execute()

        guard let meeting = meetings.first, meeting.status == .cancelled else {
            throw NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to cancel meeting — it may have already started"])
        }
    }

    // MARK: - Attendees

    func fetchAttendees(meetingId: UUID) async throws -> [MeetingAttendee] {
        return try await supabaseClient
            .from("meeting_attendees")
            .select()
            .eq("meeting_id", meetingId.uuidString)
            .order("invited_at")
            .execute()
    }

    func addAttendees(meetingId: UUID, userIds: [UUID]) async throws {
        // Remove duplicates
        let uniqueUserIds = Array(Set(userIds))
        guard !uniqueUserIds.isEmpty else { return }

        let rows = uniqueUserIds.map { userId in
            [
                "meeting_id": meetingId.uuidString,
                "user_id": userId.uuidString,
            ]
        }
        try await supabaseClient
            .from("meeting_attendees")
            .upsert(rows)
            .execute()
    }

    func updateAttendeeStatus(meetingId: UUID, userId: UUID, status: AttendeeStatus) async throws {
        try await supabaseClient
            .from("meeting_attendees")
            .update([
                "status": status.rawValue,
                "responded_at": ISO8601DateFormatter().string(from: Date()),
            ])
            .eq("meeting_id", meetingId.uuidString)
            .eq("user_id", userId.uuidString)
            .execute()
    }

    func markAllAttendeesAttended(meetingId: UUID) async throws {
        // Fetch non-declined attendees first
        struct AttendeeRecord: Decodable {
            let userId: String
            let status: String
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case status
            }
        }
        
        let attendees: [AttendeeRecord] = try await supabaseClient
            .from("meeting_attendees")
            .select("user_id, status")
            .eq("meeting_id", meetingId.uuidString)
            .execute()
        
        // Filter out declined attendees and update the rest
        let nonDeclinedIds = attendees
            .filter { $0.status != AttendeeStatus.declined.rawValue }
            .map { $0.userId }
        
        guard !nonDeclinedIds.isEmpty else { return }
        
        // Update each non-declined attendee
        for userId in nonDeclinedIds {
            try await supabaseClient
                .from("meeting_attendees")
                .update(["status": AttendeeStatus.attended.rawValue])
                .eq("meeting_id", meetingId.uuidString)
                .eq("user_id", userId)
                .execute()
        }
    }

    // MARK: - Agenda Items

    func fetchAgendaItems(meetingId: UUID) async throws -> [MeetingAgendaItem] {
        return try await supabaseClient
            .from("meeting_agenda_items")
            .select()
            .eq("meeting_id", meetingId.uuidString)
            .order("sort_order")
            .execute()
    }

    func addAgendaItem(meetingId: UUID, addedBy: UUID, title: String, description: String?, sortOrder: Int) async throws -> MeetingAgendaItem {
        let sanitizedTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !sanitizedTitle.isEmpty else {
            throw NSError(domain: "FamilyMeetingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Agenda item title cannot be empty"])
        }

        let itemId = UUID()
        var body: [String: Any] = [
            "id": itemId.uuidString,
            "meeting_id": meetingId.uuidString,
            "added_by": addedBy.uuidString,
            "title": sanitizedTitle,
            "sort_order": sortOrder,
        ]
        if let description = description, !description.isEmpty {
            body["description"] = String(description.prefix(2000))
        }

        try await supabaseClient
            .from("meeting_agenda_items")
            .insert(body)
            .execute()

        // Fetch the created item by its known UUID (no race condition)
        let items: [MeetingAgendaItem] = try await supabaseClient
            .from("meeting_agenda_items")
            .select()
            .eq("id", itemId.uuidString)
            .limit(1)
            .execute()

        guard let item = items.first else {
            throw NSError(domain: "FamilyMeetingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create agenda item"])
        }

        return item
    }

    func updateAgendaItem(_ item: MeetingAgendaItem) async throws {
        // Validate input lengths
        let sanitizedTitle = String(item.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !sanitizedTitle.isEmpty else {
            throw NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Agenda item title cannot be empty"])
        }

        var body: [String: Any] = [
            "title": sanitizedTitle,
            "sort_order": item.sortOrder,
            "status": item.status.rawValue,
        ]
        if let description = item.description {
            body["description"] = String(description.prefix(2000))
        }
        if let notes = item.notes {
            body["notes"] = String(notes.prefix(5000))
        }
        if let decision = item.decision {
            body["decision"] = String(decision.prefix(2000))
        }

        try await supabaseClient
            .from("meeting_agenda_items")
            .update(body)
            .eq("id", item.id.uuidString)
            .execute()
    }

    func batchUpdateAgendaItems(_ items: [MeetingAgendaItem]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask { [self] in
                    try await self.updateAgendaItem(item)
                }
            }
            try await group.waitForAll()
        }
    }

    func deleteAgendaItem(_ itemId: UUID, from meeting: FamilyMeeting) async throws {
        guard meeting.status == .scheduled else {
            throw NSError(domain: "FamilyMeetingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Agenda items can only be deleted from scheduled meetings"])
        }
        try await supabaseClient
            .from("meeting_agenda_items")
            .eq("id", itemId.uuidString)
            .delete()
    }

    func reorderAgendaItems(_ items: [MeetingAgendaItem]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, item) in items.enumerated() {
                let safeIndex = min(index, Int.max - 1)
                group.addTask { [self] in
                    try await self.supabaseClient
                        .from("meeting_agenda_items")
                        .update(["sort_order": safeIndex])
                        .eq("id", item.id.uuidString)
                        .execute()
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Action Items

    func fetchActionItems(meetingId: UUID) async throws -> [MeetingActionItem] {
        return try await supabaseClient
            .from("meeting_action_items")
            .select()
            .eq("meeting_id", meetingId.uuidString)
            .order("created_at")
            .execute()
    }

    func addActionItem(
        meetingId: UUID,
        agendaItemId: UUID?,
        description: String,
        assignedTo: UUID?,
        dueDate: Date?
    ) async throws -> MeetingActionItem {
        let sanitizedDescription = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !sanitizedDescription.isEmpty else {
            throw NSError(domain: "FamilyMeetingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Action item description cannot be empty"])
        }

        let itemId = UUID()
        var body: [String: Any] = [
            "id": itemId.uuidString,
            "meeting_id": meetingId.uuidString,
            "description": sanitizedDescription,
        ]
        if let agendaItemId = agendaItemId {
            body["agenda_item_id"] = agendaItemId.uuidString
        }
        if let assignedTo = assignedTo {
            body["assigned_to"] = assignedTo.uuidString
        }
        if let dueDate = dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            body["due_date"] = formatter.string(from: dueDate)
        }

        try await supabaseClient
            .from("meeting_action_items")
            .insert(body)
            .execute()

        // Fetch the created item by its known UUID (no race condition)
        let items: [MeetingActionItem] = try await supabaseClient
            .from("meeting_action_items")
            .select()
            .eq("id", itemId.uuidString)
            .limit(1)
            .execute()

        guard let item = items.first else {
            throw NSError(domain: "FamilyMeetingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create action item"])
        }

        return item
    }

    func deleteActionItem(_ itemId: UUID) async throws {
        try await supabaseClient
            .from("meeting_action_items")
            .eq("id", itemId.uuidString)
            .delete()
    }

    // MARK: - Suggested Topics

    func fetchSuggestedTopics(circleId: UUID, patientId: UUID) async throws -> [SuggestedTopic] {
        struct TopicResponse: Codable {
            let topicType: String
            let title: String
            let description: String
            let priority: Int
            let sourceId: UUID

            enum CodingKeys: String, CodingKey {
                case topicType = "topic_type"
                case title
                case description
                case priority
                case sourceId = "source_id"
            }
        }

        let topics: [TopicResponse] = try await supabaseClient.rpc("get_suggested_meeting_topics", params: [
            "p_circle_id": circleId.uuidString,
            "p_patient_id": patientId.uuidString,
        ])

        return topics.compactMap { topic in
            guard let type = SuggestedTopic.TopicType(rawValue: topic.topicType) else { return nil }
            return SuggestedTopic(
                type: type,
                title: topic.title,
                topicDescription: topic.description,
                priority: topic.priority,
                sourceId: topic.sourceId
            )
        }
    }

    // MARK: - Edge Functions

    func generateSummary(meetingId: UUID, createTasks: Bool) async throws -> (handoffId: UUID, tasksCreated: [UUID]) {
        struct Request: Encodable {
            let meetingId: String
            let createTasks: Bool
        }

        struct Response: Decodable {
            let success: Bool
            let handoffId: String?
            let tasksCreated: [String]?
            let error: ErrorDetail?

            struct ErrorDetail: Decodable {
                let code: String
                let message: String
            }
        }

        let response: Response = try await supabaseClient
            .functions("generate-meeting-summary")
            .invoke(body: Request(
                meetingId: meetingId.uuidString,
                createTasks: createTasks
            ))

        guard response.success,
              let handoffIdStr = response.handoffId,
              let handoffId = UUID(uuidString: handoffIdStr) else {
            throw NSError(
                domain: "FamilyMeetingService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: response.error?.message ?? "Failed to generate summary"]
            )
        }

        let taskIds = (response.tasksCreated ?? []).compactMap { UUID(uuidString: $0) }
        return (handoffId, taskIds)
    }

    func sendInvites(meetingId: UUID) async throws -> Int {
        struct Request: Encodable {
            let meetingId: String
        }

        struct Response: Decodable {
            let success: Bool
            let invitesSent: Int?
            let error: ErrorDetail?

            struct ErrorDetail: Decodable {
                let code: String
                let message: String
            }
        }

        let response: Response = try await supabaseClient
            .functions("send-meeting-invites")
            .invoke(body: Request(meetingId: meetingId.uuidString))

        guard response.success else {
            throw NSError(
                domain: "FamilyMeetingService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: response.error?.message ?? "Failed to send invites"]
            )
        }

        return response.invitesSent ?? 0
    }
}
