import Foundation

// MARK: - Coach Service

actor CoachService {
    private let supabaseClient: SupabaseClient
    private let databaseManager: DatabaseManager

    init(supabaseClient: SupabaseClient, databaseManager: DatabaseManager) {
        self.supabaseClient = supabaseClient
        self.databaseManager = databaseManager
    }

    // MARK: - Chat

    /// Send a message to the Care Coach and get a response
    func chat(
        message: String,
        conversationId: String?,
        patientId: String?,
        circleId: String
    ) async throws -> CoachChatResponse {
        let request = CoachChatRequest(
            conversationId: conversationId,
            message: message,
            patientId: patientId,
            circleId: circleId
        )

        // Retry logic for transient network failures
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let response: CoachChatResponse = try await supabaseClient
                    .functions("coach-chat")
                    .invoke(body: request)

                // Cache conversation and messages locally if successful
                if response.success, let convId = response.conversationId {
                    await cacheConversationUpdate(conversationId: convId)
                }

                return response
            } catch {
                lastError = error

                // Check if it's a retryable error (network issues)
                let isRetryable = isRetryableError(error)
                if !isRetryable || attempt == 2 {
                    throw mapError(error)
                }

                // Exponential backoff
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? CoachServiceError.networkError
    }

    private func isRetryableError(_ error: Error) -> Bool {
        // Check for network-related errors
        let nsError = error as NSError
        let networkErrorCodes = [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost
        ]
        return networkErrorCodes.contains(nsError.code)
    }

    private func mapError(_ error: Error) -> CoachServiceError {
        let nsError = error as NSError
        if nsError.code == NSURLErrorNotConnectedToInternet {
            return .networkError
        }
        return .messageFailed
    }

    // MARK: - Usage

    /// Check current usage limits
    func checkUsage() async throws -> CoachUsageInfo {
        try await supabaseClient.rpc("check_coach_usage", params: [:])
    }

    /// Check if user has coach access
    func hasAccess() async throws -> Bool {
        try await supabaseClient.rpc("has_coach_access", params: [:])
    }

    /// Check if user has proactive suggestions access
    func hasProactiveAccess() async throws -> Bool {
        try await supabaseClient.rpc("has_proactive_coach_access", params: [:])
    }

    // MARK: - Conversations

    /// Fetch all conversations for the current user
    func fetchConversations(circleId: String) async throws -> [CoachConversation] {
        try await supabaseClient
            .from("coach_conversations")
            .select("*")
            .eq("circle_id", circleId)
            .order("updated_at", ascending: false)
            .execute()
    }

    /// Fetch a single conversation with its messages
    func fetchConversation(id: String) async throws -> (conversation: CoachConversation, messages: [CoachMessage]) {
        async let conversationTask: [CoachConversation] = supabaseClient
            .from("coach_conversations")
            .select("*")
            .eq("id", id)
            .execute()

        async let messagesTask: [CoachMessage] = supabaseClient
            .from("coach_messages")
            .select("*")
            .eq("conversation_id", id)
            .order("created_at", ascending: true)
            .execute()

        let (conversations, messages) = try await (conversationTask, messagesTask)

        guard let conversation = conversations.first else {
            throw CoachServiceError.conversationNotFound
        }

        return (conversation, messages)
    }

    /// Archive a conversation
    func archiveConversation(id: String) async throws {
        try await supabaseClient
            .from("coach_conversations")
            .eq("id", id)
            .update(["status": "ARCHIVED"])
    }

    /// Delete a conversation
    func deleteConversation(id: String) async throws {
        try await supabaseClient
            .from("coach_conversations")
            .eq("id", id)
            .delete()
    }

    // MARK: - Messages

    /// Fetch messages for a conversation
    func fetchMessages(conversationId: String) async throws -> [CoachMessage] {
        try await supabaseClient
            .from("coach_messages")
            .select("*")
            .eq("conversation_id", conversationId)
            .order("created_at", ascending: true)
            .execute()
    }

    /// Toggle bookmark on a message
    func toggleBookmark(messageId: String, isBookmarked: Bool) async throws {
        try await supabaseClient
            .from("coach_messages")
            .eq("id", messageId)
            .update(["is_bookmarked": isBookmarked])
    }

    /// Submit feedback for a message
    func submitFeedback(messageId: String, feedback: CoachMessage.Feedback) async throws {
        try await supabaseClient
            .from("coach_messages")
            .eq("id", messageId)
            .update(["feedback": feedback.rawValue])
    }

    /// Fetch bookmarked messages
    func fetchBookmarkedMessages(circleId: String) async throws -> [CoachMessage] {
        // Use a single query with join to avoid N+1
        // Fetch bookmarked messages through conversation relationship
        let messages: [CoachMessage] = try await supabaseClient
            .from("coach_messages")
            .select("*, coach_conversations!inner(circle_id)")
            .eq("coach_conversations.circle_id", circleId)
            .eq("is_bookmarked", "true")
            .order("created_at", ascending: false)
            .limit(100)  // Limit to prevent unbounded queries
            .execute()

        return messages
    }

    // MARK: - Suggestions

    /// Fetch pending suggestions
    func fetchSuggestions(circleId: String) async throws -> [CoachSuggestion] {
        try await supabaseClient
            .from("coach_suggestions")
            .select("*")
            .eq("circle_id", circleId)
            .eq("status", "PENDING")
            .order("created_at", ascending: false)
            .execute()
    }

    /// Mark suggestion as viewed
    func markSuggestionViewed(id: String) async throws {
        try await supabaseClient
            .from("coach_suggestions")
            .eq("id", id)
            .update(["status": "VIEWED"])
    }

    /// Dismiss a suggestion
    func dismissSuggestion(id: String) async throws {
        try await supabaseClient
            .from("coach_suggestions")
            .eq("id", id)
            .update([
                "status": "DISMISSED",
                "dismissed_at": ISO8601DateFormatter().string(from: Date())
            ])
    }

    /// Mark suggestion as actioned
    func actionSuggestion(id: String) async throws {
        try await supabaseClient
            .from("coach_suggestions")
            .eq("id", id)
            .update([
                "status": "ACTIONED",
                "actioned_at": ISO8601DateFormatter().string(from: Date())
            ])
    }

    // MARK: - Local Cache

    private func cacheConversationUpdate(conversationId: String) async {
        // Optionally cache for offline viewing
        // For now, we rely on Supabase for persistence
    }
}

// MARK: - Errors

enum CoachServiceError: Error, LocalizedError {
    case conversationNotFound
    case messageFailed
    case notAuthorized
    case limitReached
    case networkError

    var errorDescription: String? {
        switch self {
        case .conversationNotFound:
            return "Conversation not found"
        case .messageFailed:
            return "Failed to send message"
        case .notAuthorized:
            return "Care Coach requires a Plus or Family subscription"
        case .limitReached:
            return "Monthly message limit reached"
        case .networkError:
            return "Network error. Please check your connection."
        }
    }
}
