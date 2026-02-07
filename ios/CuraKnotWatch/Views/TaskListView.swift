import SwiftUI
import WatchKit

// MARK: - Task List View

struct TaskListView: View {
    @EnvironmentObject var dataManager: WatchDataManager

    var openTasks: [WatchTask] {
        dataManager.todayTasks.filter { $0.isOpen }
    }

    var body: some View {
        Group {
            if openTasks.isEmpty {
                EmptyTasksView()
            } else {
                TasksListContent(tasks: openTasks)
            }
        }
        .navigationTitle("Tasks")
    }
}

// MARK: - Tasks List Content

private struct TasksListContent: View {
    let tasks: [WatchTask]
    @EnvironmentObject var dataManager: WatchDataManager

    var body: some View {
        List {
            ForEach(tasks) { task in
                TaskRow(task: task)
                    .swipeActions(edge: .trailing) {
                        Button {
                            completeTask(task)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.green)
                        .accessibilityIdentifier("CompleteTaskSwipe_\(task.id)")
                    }
                    .accessibilityIdentifier("TaskRow_\(task.id)")
            }
        }
    }

    private func completeTask(_ task: WatchTask) {
        dataManager.markTaskCompleted(task.id)
        WKInterfaceDevice.current().play(.success)
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: WatchTask
    @EnvironmentObject var dataManager: WatchDataManager
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Priority indicator
                    Image(systemName: task.priorityIcon)
                        .font(.caption)
                        .foregroundStyle(task.priorityColor)

                    Text(task.title)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                if let dueAt = task.dueAt {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(dueAt, style: .relative)
                            .font(.caption)
                    }
                    .foregroundStyle(task.isOverdue ? .red : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            TaskDetailSheet(task: task)
        }
    }
}

// MARK: - Task Detail Sheet

private struct TaskDetailSheet: View {
    let task: WatchTask
    @EnvironmentObject var dataManager: WatchDataManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Priority Badge
                HStack {
                    Image(systemName: task.priorityIcon)
                    Text(task.priority)
                }
                .font(.caption)
                .foregroundStyle(task.priorityColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(task.priorityColor.opacity(0.2), in: Capsule())

                // Title
                Text(task.title)
                    .font(.headline)

                // Description
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Due Date
                if let dueAt = task.dueAt {
                    Divider()

                    HStack {
                        Image(systemName: "calendar")
                        VStack(alignment: .leading) {
                            Text(dueAt, style: .date)
                            Text(dueAt, style: .time)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(task.isOverdue ? .red : .secondary)
                }

                Spacer(minLength: 20)

                // Complete Button
                Button {
                    completeTask()
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("TaskDetailCompleteButton")
            }
            .padding()
        }
        .navigationTitle("Task")
    }

    private func completeTask() {
        dataManager.markTaskCompleted(task.id)
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }
}

// MARK: - Empty Tasks View

private struct EmptyTasksView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("All Done!")
                .font(.headline)

            Text("No tasks for today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - WatchTask Priority Color Extension (DRY - CR3 fix)

extension WatchTask {
    var priorityColor: Color {
        switch priority {
        case "HIGH": return .red
        case "MED": return .orange
        default: return .green
        }
    }
}

#Preview {
    TaskListView()
        .environmentObject(WatchDataManager.shared)
}
