import SwiftUI

// MARK: - Coach Message Bubble

struct CoachMessageBubble: View {
    let message: CoachMessage
    let onAction: (CoachAction) -> Void
    let onBookmark: () -> Void
    let onFeedback: (CoachMessage.Feedback) -> Void

    @State private var showingFeedbackMenu = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 6) {
                // Message content
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(backgroundColor)
                    .foregroundStyle(foregroundColor)
                    .cornerRadius(18)

                // Actions (for assistant messages)
                if message.isFromAssistant && !message.actions.isEmpty {
                    actionButtons
                }

                // Timestamp and actions row
                HStack(spacing: 12) {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if message.isFromAssistant {
                        // Bookmark button
                        Button {
                            onBookmark()
                        } label: {
                            Image(systemName: message.isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.caption)
                                .foregroundStyle(message.isBookmarked ? .orange : .secondary)
                        }
                        .accessibilityLabel(message.isBookmarked ? "Remove bookmark" : "Bookmark message")

                        // Feedback button
                        Menu {
                            Button {
                                onFeedback(.helpful)
                            } label: {
                                Label("Helpful", systemImage: "hand.thumbsup")
                            }

                            Button {
                                onFeedback(.notHelpful)
                            } label: {
                                Label("Not Helpful", systemImage: "hand.thumbsdown")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Provide feedback")
                    }
                }
            }

            if !message.isFromUser {
                Spacer(minLength: 60)
            }
        }
    }

    private var backgroundColor: Color {
        message.isFromUser ? Color.accentColor : Color(.secondarySystemBackground)
    }

    private var foregroundColor: Color {
        message.isFromUser ? .white : .primary
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.actions) { action in
                Button {
                    onAction(action)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: action.type.icon)
                            .font(.caption)

                        Text(action.label)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(8)
                }
                .accessibilityLabel(action.label)
                .accessibilityHint("Double tap to \(action.label.lowercased())")
            }
        }
    }
}

// MARK: - Coach Disclaimer

struct CoachDisclaimer: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text("This is not medical advice. Consult a healthcare provider for medical questions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        CoachMessageBubble(
            message: CoachMessage(
                id: "1",
                conversationId: "conv1",
                role: .user,
                content: "How do I manage my stress as a caregiver?",
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
            ),
            onAction: { _ in },
            onBookmark: {},
            onFeedback: { _ in }
        )

        CoachMessageBubble(
            message: CoachMessage(
                id: "2",
                conversationId: "conv1",
                role: .assistant,
                content: "Caregiving can be incredibly demanding, and it's completely normal to feel stressed. Here are some strategies that might help:\n\n• Take regular breaks, even if just for a few minutes\n• Connect with other caregivers who understand\n• Don't hesitate to ask for help from your Care Circle\n• Consider respite care options",
                contextHandoffIds: nil,
                contextBinderIds: nil,
                contextSnapshotJson: nil,
                actionsJson: nil,
                isBookmarked: true,
                feedback: nil,
                tokensUsed: nil,
                latencyMs: nil,
                modelVersion: nil,
                createdAt: Date()
            ),
            onAction: { _ in },
            onBookmark: {},
            onFeedback: { _ in }
        )
    }
    .padding()
}
