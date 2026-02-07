import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.curaknot.app", category: "CoachChat")

// MARK: - Coach Chat View Model

@MainActor
class CoachChatViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var messages: [CoachMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var isSending = false
    @Published var usageInfo: CoachUsageInfo?
    @Published var showUpgradePrompt = false
    @Published var errorMessage: String?
    @Published var suggestedFollowups: [String] = []
    @Published var contextReferences: [String] = []

    // MARK: - Conversation State

    @Published var currentConversation: CoachConversation?
    @Published var conversations: [CoachConversation] = []
    @Published var isLoadingConversations = false

    // MARK: - Configuration

    var circleId: String?
    var patientId: String?
    var patientName: String?

    // MARK: - Private Properties

    private var coachService: CoachService?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {}

    func configure(coachService: CoachService) {
        self.coachService = coachService
    }

    // MARK: - Usage Check

    func checkAccess() async {
        guard let service = coachService else { return }

        do {
            usageInfo = try await service.checkUsage()
            if usageInfo?.allowed == false {
                showUpgradePrompt = true
            }
        } catch {
            logger.error("Failed to check usage: \(error.localizedDescription)")
        }
    }

    // MARK: - Conversations

    func loadConversations() async {
        guard let service = coachService, let circleId = circleId else { return }

        isLoadingConversations = true
        defer { isLoadingConversations = false }

        do {
            conversations = try await service.fetchConversations(circleId: circleId)
        } catch {
            logger.error("Failed to load conversations: \(error.localizedDescription)")
            errorMessage = "Failed to load conversations"
        }
    }

    func selectConversation(_ conversation: CoachConversation) async {
        guard let service = coachService else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.fetchConversation(id: conversation.id)
            currentConversation = result.conversation
            messages = result.messages
            suggestedFollowups = []
            contextReferences = []
        } catch {
            logger.error("Failed to load conversation: \(error.localizedDescription)")
            errorMessage = "Failed to load conversation"
        }
    }

    func startNewConversation() {
        currentConversation = nil
        messages = []
        suggestedFollowups = []
        contextReferences = []
        inputText = ""
    }

    func archiveConversation(_ conversation: CoachConversation) async {
        guard let service = coachService else { return }

        do {
            try await service.archiveConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            if currentConversation?.id == conversation.id {
                startNewConversation()
            }
        } catch {
            logger.error("Failed to archive conversation: \(error.localizedDescription)")
            errorMessage = "Failed to archive conversation"
        }
    }

    func deleteConversation(_ conversation: CoachConversation) async {
        guard let service = coachService else { return }

        do {
            try await service.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            if currentConversation?.id == conversation.id {
                startNewConversation()
            }
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
            errorMessage = "Failed to delete conversation"
        }
    }

    // MARK: - Messaging

    func sendMessage() async {
        guard let service = coachService,
              let circleId = circleId,
              !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        // Add user message immediately for responsiveness
        let tempUserMessage = CoachMessage(
            id: UUID().uuidString,
            conversationId: currentConversation?.id ?? "temp",
            role: .user,
            content: userMessage,
            contextHandoffIds: nil,
            contextBinderIds: nil,
            contextSnapshotJson: nil,
            actionsJson: nil,
            isBookmarked: false,
            feedback: nil,
            tokensUsed: nil,
            latencyMs: nil,
            modelVersion: nil,
            createdAt: Date()
        )
        messages.append(tempUserMessage)

        isSending = true
        errorMessage = nil
        suggestedFollowups = []

        defer { isSending = false }

        do {
            let response = try await service.chat(
                message: userMessage,
                conversationId: currentConversation?.id,
                patientId: patientId,
                circleId: circleId
            )

            if response.success {
                // Update conversation ID if new
                if currentConversation == nil, let convId = response.conversationId {
                    // Create local representation
                    let newConversation = CoachConversation(
                        id: convId,
                        circleId: circleId,
                        userId: "",  // Will be set by server
                        patientId: patientId,
                        title: userMessage.prefix(50) + (userMessage.count > 50 ? "..." : ""),
                        status: .active,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    currentConversation = newConversation

                    // Add to conversations list
                    if !conversations.contains(where: { $0.id == convId }) {
                        conversations.insert(newConversation, at: 0)
                    }
                }

                // Add assistant response
                if let content = response.content {
                    let assistantMessage = CoachMessage(
                        id: response.messageId ?? UUID().uuidString,
                        conversationId: currentConversation?.id ?? "temp",
                        role: .assistant,
                        content: content,
                        contextHandoffIds: nil,
                        contextBinderIds: nil,
                        contextSnapshotJson: nil,
                        actionsJson: encodeActions(response.actions ?? []),
                        isBookmarked: false,
                        feedback: nil,
                        tokensUsed: nil,
                        latencyMs: nil,
                        modelVersion: nil,
                        createdAt: Date()
                    )
                    messages.append(assistantMessage)
                }

                // Update UI state
                usageInfo = response.usageInfo
                suggestedFollowups = response.suggestedFollowups ?? []
                contextReferences = response.contextReferences ?? []

                // Check if limit reached
                if usageInfo?.allowed == false {
                    showUpgradePrompt = true
                }
            } else if let error = response.error {
                // Remove temp message on error
                if !messages.isEmpty {
                    messages.removeLast()
                }

                if error.code == "LIMIT_REACHED" {
                    showUpgradePrompt = true
                    usageInfo = response.usageInfo
                } else {
                    errorMessage = error.message
                }
            }
        } catch {
            // Remove temp message on error
            if !messages.isEmpty {
                messages.removeLast()
            }
            errorMessage = "Failed to send message. Please try again."
            logger.error("Chat error: \(error.localizedDescription)")
        }
    }

    func sendFollowUp(_ text: String) async {
        // Prevent concurrent sends
        guard !isSending else { return }
        inputText = text
        await sendMessage()
    }

    // MARK: - Message Actions

    func toggleBookmark(_ message: CoachMessage) async {
        guard let service = coachService else { return }

        let newValue = !message.isBookmarked

        // Update locally first
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            var updatedMessage = messages[index]
            updatedMessage = CoachMessage(
                id: updatedMessage.id,
                conversationId: updatedMessage.conversationId,
                role: updatedMessage.role,
                content: updatedMessage.content,
                contextHandoffIds: updatedMessage.contextHandoffIds,
                contextBinderIds: updatedMessage.contextBinderIds,
                contextSnapshotJson: updatedMessage.contextSnapshotJson,
                actionsJson: updatedMessage.actionsJson,
                isBookmarked: newValue,
                feedback: updatedMessage.feedback,
                tokensUsed: updatedMessage.tokensUsed,
                latencyMs: updatedMessage.latencyMs,
                modelVersion: updatedMessage.modelVersion,
                createdAt: updatedMessage.createdAt
            )
            messages[index] = updatedMessage
        }

        do {
            try await service.toggleBookmark(messageId: message.id, isBookmarked: newValue)
        } catch {
            // Revert on failure
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                var revertedMessage = messages[index]
                revertedMessage = CoachMessage(
                    id: revertedMessage.id,
                    conversationId: revertedMessage.conversationId,
                    role: revertedMessage.role,
                    content: revertedMessage.content,
                    contextHandoffIds: revertedMessage.contextHandoffIds,
                    contextBinderIds: revertedMessage.contextBinderIds,
                    contextSnapshotJson: revertedMessage.contextSnapshotJson,
                    actionsJson: revertedMessage.actionsJson,
                    isBookmarked: !newValue,
                    feedback: revertedMessage.feedback,
                    tokensUsed: revertedMessage.tokensUsed,
                    latencyMs: revertedMessage.latencyMs,
                    modelVersion: revertedMessage.modelVersion,
                    createdAt: revertedMessage.createdAt
                )
                messages[index] = revertedMessage
            }
            logger.error("Failed to toggle bookmark: \(error.localizedDescription)")
        }
    }

    func submitFeedback(_ message: CoachMessage, feedback: CoachMessage.Feedback) async {
        guard let service = coachService else { return }

        do {
            try await service.submitFeedback(messageId: message.id, feedback: feedback)
        } catch {
            logger.error("Failed to submit feedback: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func encodeActions(_ actions: [CoachAction]) -> String? {
        guard !actions.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(actions),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

// MARK: - Conversation List View Model

@MainActor
class CoachConversationListViewModel: ObservableObject {
    @Published var conversations: [CoachConversation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var coachService: CoachService?
    var circleId: String?

    func configure(coachService: CoachService) {
        self.coachService = coachService
    }

    func loadConversations() async {
        guard let service = coachService, let circleId = circleId else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try await service.fetchConversations(circleId: circleId)
        } catch {
            errorMessage = "Failed to load conversations"
            logger.error("Error loading conversations: \(error.localizedDescription)")
        }
    }
}
