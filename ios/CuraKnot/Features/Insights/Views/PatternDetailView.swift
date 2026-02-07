import SwiftUI

/// Detailed view of a detected pattern
struct PatternDetailView: View {
    let pattern: DetectedPattern
    @ObservedObject var viewModel: SymptomPatternsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var mentions: [PatternMention] = []
    @State private var isLoadingMentions = false
    @State private var showFeedbackSheet = false
    @State private var showAddToQuestionsConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                patternHeader

                // Disclaimer
                InsightsDisclaimer(compact: true)

                // Summary
                summarySection

                // Correlations
                if let events = pattern.correlatedEvents, !events.isEmpty {
                    correlationsSection(events)
                }

                // Mentions timeline
                mentionsSection

                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle(pattern.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMentions()
        }
        .confirmationDialog(
            "Add to Visit Pack Questions?",
            isPresented: $showAddToQuestionsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Add Question") {
                Task {
                    await viewModel.addToAppointmentQuestions(pattern)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will create a question based on this pattern for your next appointment.")
        }
        .sheet(isPresented: $showFeedbackSheet) {
            PatternFeedbackSheet(pattern: pattern, viewModel: viewModel)
        }
    }

    // MARK: - Header

    private var patternHeader: some View {
        HStack(spacing: 16) {
            Text(pattern.icon)
                .font(.system(size: 48))

            VStack(alignment: .leading, spacing: 8) {
                Text(pattern.displayName)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    PatternTypeBadge(type: pattern.patternType)
                    if let trend = pattern.trend {
                        TrendBadge(trend: trend)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            Text(pattern.summaryText)
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                SummaryStatView(
                    value: "\(pattern.mentionCount)",
                    label: "Mentions"
                )

                SummaryStatView(
                    value: daysSinceFirst,
                    label: "Days Tracked"
                )

                if pattern.hasStrongCorrelation {
                    SummaryStatView(
                        value: "Yes",
                        label: "Related Event"
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var daysSinceFirst: String {
        let days = Calendar.current.dateComponents([.day], from: pattern.firstMentionAt, to: Date()).day ?? 0
        return "\(days)"
    }

    // MARK: - Correlations

    private func correlationsSection(_ events: [CorrelatedEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Possibly Related Events")
                .font(.headline)

            ForEach(events) { event in
                HStack(spacing: 12) {
                    Image(systemName: event.eventType.icon)
                        .foregroundStyle(.orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.eventDescription)
                            .font(.subheadline)

                        Text("\(event.daysDifference) days before pattern started")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(event.strength.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(event.strength == .strong ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2))
                        .foregroundStyle(event.strength == .strong ? .orange : .gray)
                        .clipShape(Capsule())
                }
                .padding()
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text("These events occurred near the time this pattern started. Consider discussing with a healthcare provider.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Mentions Timeline

    private var mentionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mentions")
                    .font(.headline)

                Spacer()

                if isLoadingMentions {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if mentions.isEmpty && !isLoadingMentions {
                Text("No mentions found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mentions.prefix(5)) { mention in
                    MentionRow(mention: mention)
                }

                if mentions.count > 5 {
                    Text("+ \(mentions.count - 5) more mentions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                showAddToQuestionsConfirmation = true
            } label: {
                Label("Add to Visit Pack Questions", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if pattern.status == .active {
                Button {
                    Task {
                        await viewModel.trackPattern(pattern)
                    }
                } label: {
                    Label("Track This Concern", systemImage: "chart.line.uptrend.xyaxis")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.dismissPattern(pattern)
                        dismiss()
                    }
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showFeedbackSheet = true
                } label: {
                    Label("Feedback", systemImage: "hand.thumbsup")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Load Mentions

    private func loadMentions() async {
        isLoadingMentions = true
        defer { isLoadingMentions = false }

        do {
            mentions = try await viewModel.symptomService.fetchMentions(patternId: pattern.id)
        } catch {
            #if DEBUG
            print("Failed to load mentions: \(error)")
            #endif
        }
    }
}

// MARK: - Supporting Views

struct SummaryStatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MentionRow: View {
    let mention: PatternMention

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mention.matchedText)
                .font(.subheadline)
                .lineLimit(2)

            Text(mention.mentionedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Feedback Sheet

struct PatternFeedbackSheet: View {
    let pattern: DetectedPattern
    @ObservedObject var viewModel: SymptomPatternsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFeedback: PatternFeedbackType?
    @State private var feedbackText = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Was this pattern helpful?") {
                    feedbackButton(.helpful, title: "Yes, helpful", icon: "hand.thumbsup")
                    feedbackButton(.notHelpful, title: "Not helpful", icon: "hand.thumbsdown")
                    feedbackButton(.falsePositive, title: "Incorrect", icon: "xmark.circle")
                }

                if selectedFeedback != nil {
                    Section("Additional comments (optional)") {
                        TextField("Tell us more...", text: $feedbackText, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submitFeedback() }
                    }
                    .disabled(selectedFeedback == nil || isSubmitting)
                }
            }
        }
    }

    private func feedbackButton(_ type: PatternFeedbackType, title: String, icon: String) -> some View {
        Button {
            selectedFeedback = type
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(type == selectedFeedback ? .accentColor : .secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if type == selectedFeedback {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }

    private func submitFeedback() async {
        guard let type = selectedFeedback else { return }
        isSubmitting = true

        await viewModel.submitFeedback(
            for: pattern,
            type: type,
            text: feedbackText.isEmpty ? nil : feedbackText
        )

        dismiss()
    }
}

// MARK: - Pattern Feedback Type

enum PatternFeedbackType: String, Codable {
    case helpful = "HELPFUL"
    case notHelpful = "NOT_HELPFUL"
    case falsePositive = "FALSE_POSITIVE"
}
