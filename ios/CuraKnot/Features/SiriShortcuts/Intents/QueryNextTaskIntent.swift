import AppIntents
import SwiftUI
import os.log

// MARK: - Logger
private let logger = Logger(subsystem: "com.curaknot.app", category: "SiriShortcuts")

// MARK: - Query Next Task Intent

/// Intent for querying the user's next (most urgent) task.
/// Available for all tiers (FREE, PLUS, FAMILY).
struct QueryNextTaskIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "What's My Next Task"

    static var description = IntentDescription(
        "Find out what your most urgent pending task is.",
        categoryName: "Tasks",
        searchKeywords: ["task", "todo", "next", "urgent", "pending"]
    )

    static var openAppWhenRun: Bool = false

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let service = SiriShortcutsService.shared

        // Validate context
        guard service.currentUserId != nil else {
            return .result(
                dialog: "Please open CuraKnot and sign in first.",
                view: TaskErrorView(message: "Sign in required")
            )
        }

        // Get next task
        do {
            guard let task = try service.getNextTask() else {
                return .result(
                    dialog: "You have no pending tasks. Great job staying on top of things!",
                    view: NoTasksView()
                )
            }

            // Build response
            let dialog = buildTaskDialog(task)

            return .result(
                dialog: IntentDialog(stringLiteral: dialog),
                view: TaskDetailView(task: task)
            )

        } catch {
            logger.error("Failed to fetch next task: \(error.localizedDescription)")
            return .result(
                dialog: "I couldn't check your tasks right now. Please try again.",
                view: TaskErrorView(message: "Could not fetch tasks")
            )
        }
    }

    // MARK: - Helpers

    private func buildTaskDialog(_ task: CareTask) -> String {
        var parts: [String] = []

        // Task title
        parts.append("Your next task is: \(task.title)")

        // Due date
        if let dueAt = task.dueAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relativeDate = formatter.localizedString(for: dueAt, relativeTo: Date())

            if dueAt < Date() {
                parts.append("It was due \(relativeDate)")
            } else {
                parts.append("It's due \(relativeDate)")
            }
        }

        // Priority
        if task.priority == .high {
            parts.append("This is marked as high priority")
        }

        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - Task Views

struct TaskDetailView: View {
    let task: CareTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                priorityIndicator
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
            }

            if let dueAt = task.dueAt {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(dueAt, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(dueAt < Date() ? .red : .secondary)
                }
            }

            if let description = task.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var priorityIndicator: some View {
        switch task.priority {
        case .high:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .med:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        case .low:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        }
    }
}

struct NoTasksView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title)
            Text("All caught up!")
                .font(.headline)
            Text("No pending tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct TaskErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title)
            Text(message)
                .font(.subheadline)
        }
        .padding()
    }
}
