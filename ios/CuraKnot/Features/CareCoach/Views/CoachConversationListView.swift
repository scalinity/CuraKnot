import SwiftUI

// MARK: - Coach Conversation List View

struct CoachConversationListView: View {
    @ObservedObject var viewModel: CoachChatViewModel
    let onSelect: (CoachConversation) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingConversations {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if viewModel.conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.startNewConversation()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New conversation")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Conversations Yet")
                .font(.headline)

            Text("Start a conversation with your Care Coach to get personalized guidance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                viewModel.startNewConversation()
                dismiss()
            } label: {
                Text("Start Conversation")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var conversationList: some View {
        List {
            ForEach(viewModel.conversations) { conversation in
                Button {
                    onSelect(conversation)
                } label: {
                    ConversationRow(conversation: conversation)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(conversation.title ?? "Untitled conversation")
                .accessibilityHint("Double tap to open")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteConversation(conversation)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            Task {
                                await viewModel.archiveConversation(conversation)
                            }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.secondary)
                    }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: CoachConversation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(conversation.displayTitle)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                if conversation.status == .archived {
                    Image(systemName: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if conversation.patientId != nil {
                    Text("•")
                        .foregroundStyle(.secondary)

                    Image(systemName: "person.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    CoachConversationListView(
        viewModel: {
            let vm = CoachChatViewModel()
            return vm
        }(),
        onSelect: { _ in }
    )
}
