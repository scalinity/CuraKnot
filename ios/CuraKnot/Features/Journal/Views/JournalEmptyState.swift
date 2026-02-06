import SwiftUI

// MARK: - Journal Empty State

/// Empty state view for when there are no journal entries
/// Uses gentle, inviting language - no guilt or pressure
struct JournalEmptyState: View {
    let onCreateEntry: () -> Void
    var isFiltered: Bool = false
    var onClearFilters: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Illustration
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(.purple.gradient)

            // Message
            VStack(spacing: 8) {
                Text(isFiltered ? "No matching entries" : "Capture the bright moments")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(isFiltered
                     ? "Try adjusting your filters"
                     : "Your caregiving journey has moments worth remembering. Start capturing them here."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            // Action buttons
            VStack(spacing: 12) {
                if isFiltered {
                    if let onClearFilters = onClearFilters {
                        Button(action: onClearFilters) {
                            Label("Clear Filters", systemImage: "xmark.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                } else {
                    Button(action: onCreateEntry) {
                        Label("Share a Good Moment", systemImage: "face.smiling")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 32)

            // Gentle prompts (no pressure)
            if !isFiltered {
                VStack(spacing: 12) {
                    Text("Ideas to get started:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        PromptSuggestion(text: "What made you smile this week?")
                        PromptSuggestion(text: "A small victory worth celebrating")
                        PromptSuggestion(text: "A moment of connection")
                    }
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Prompt Suggestion

/// A gentle prompt suggestion pill
struct PromptSuggestion: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(.purple)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack {
        JournalEmptyState(onCreateEntry: {})

        Divider()

        JournalEmptyState(
            onCreateEntry: {},
            isFiltered: true,
            onClearFilters: {}
        )
    }
}
