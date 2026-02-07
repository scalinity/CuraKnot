import SwiftUI
import WidgetKit

// MARK: - Next Task Complication

struct NextTaskComplication: Widget {
    let kind = "com.curaknot.complication.nexttask"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextTaskProvider()) { entry in
            NextTaskComplicationView(entry: entry)
        }
        .configurationDisplayName("Next Task")
        .description("Shows your next task due")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Timeline Entry

struct NextTaskEntry: TimelineEntry {
    let date: Date
    let taskTitle: String?
    let dueAt: Date?
    let isOverdue: Bool

    var timeUntilDue: TimeInterval? {
        guard let dueAt = dueAt else { return nil }
        return dueAt.timeIntervalSince(date)
    }

    var shortTimeLabel: String {
        guard let timeUntil = timeUntilDue else { return "--" }

        if timeUntil < 0 {
            return "Late"
        } else if timeUntil < 60 * 60 {
            return "\(Int(timeUntil / 60))m"
        } else if timeUntil < 24 * 60 * 60 {
            return "\(Int(timeUntil / 3600))h"
        } else {
            return "\(Int(timeUntil / (24 * 3600)))d"
        }
    }

    var gaugeValue: Double {
        guard let timeUntil = timeUntilDue, timeUntil > 0 else { return 0 }
        // Scale to 24 hours max
        return min(1.0, timeUntil / (24 * 60 * 60))
    }

    static var placeholder: NextTaskEntry {
        NextTaskEntry(
            date: Date(),
            taskTitle: "Give medication",
            dueAt: Date().addingTimeInterval(2 * 3600),
            isOverdue: false
        )
    }

    static var empty: NextTaskEntry {
        NextTaskEntry(
            date: Date(),
            taskTitle: nil,
            dueAt: nil,
            isOverdue: false
        )
    }
}

// MARK: - Timeline Provider

struct NextTaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextTaskEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (NextTaskEntry) -> Void) {
        let entry = loadCurrentEntry()
        completion(entry)
    }

    // Shared UserDefaults for better performance (CA3 fix)
    private static let sharedDefaults = UserDefaults(suiteName: "group.com.curaknot.app")

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextTaskEntry>) -> Void) {
        // Decode JSON once, then create entries (CA3 fix - was decoding 4x)
        let task = loadTask()
        var entries: [NextTaskEntry] = []
        let currentDate = Date()

        for minuteOffset in stride(from: 0, to: 60, by: 15) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate)!
            let entry = createEntry(from: task, date: entryDate)
            entries.append(entry)
        }

        // Use .atEnd for time-sensitive tasks to ensure overdue state updates correctly
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func loadCurrentEntry() -> NextTaskEntry {
        let task = loadTask()
        return createEntry(from: task, date: Date())
    }

    private func loadTask() -> ComplicationTask? {
        guard let data = Self.sharedDefaults?.data(forKey: "complication_next_task"),
              let task = try? JSONDecoder().decode(ComplicationTask.self, from: data) else {
            return nil
        }
        return task
    }

    private func createEntry(from task: ComplicationTask?, date: Date) -> NextTaskEntry {
        guard let task = task else { return .empty }
        return NextTaskEntry(
            date: date,
            taskTitle: task.title,
            dueAt: task.dueAt,
            isOverdue: task.dueAt.map { $0 < date } ?? false
        )
    }
}

// MARK: - Complication Task (Shared Data)

struct ComplicationTask: Codable {
    let title: String
    let dueAt: Date?
}

// MARK: - Complication View

struct NextTaskComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextTaskEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        case .accessoryCorner:
            CornerView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        default:
            EmptyView()
        }
    }
}

// MARK: - Circular View

private struct CircularView: View {
    let entry: NextTaskEntry

    var body: some View {
        if entry.taskTitle != nil {
            Gauge(value: entry.gaugeValue, in: 0...1) {
                Image(systemName: "checklist")
            } currentValueLabel: {
                Text(entry.shortTimeLabel)
                    .font(.system(size: 12, weight: .semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(entry.isOverdue ? .red : .orange)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Rectangular View

private struct RectangularView: View {
    let entry: NextTaskEntry

    var body: some View {
        if let title = entry.taskTitle {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "checklist")
                        .font(.caption2)
                    Text("Next Task")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if let dueAt = entry.dueAt {
                    Text(dueAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(entry.isOverdue ? .red : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("No tasks")
                        .font(.headline)
                }
                Text("All done for today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Corner View

private struct CornerView: View {
    let entry: NextTaskEntry

    var body: some View {
        if entry.taskTitle != nil {
            Text(entry.shortTimeLabel)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(entry.isOverdue ? .red : .orange)
                .widgetCurvesContent()
                .widgetLabel {
                    Text("Task")
                }
        } else {
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
                .widgetCurvesContent()
        }
    }
}

// MARK: - Inline View

private struct InlineView: View {
    let entry: NextTaskEntry

    var body: some View {
        if let title = entry.taskTitle {
            Text("Next: \(title)")
        } else {
            Text("No tasks due")
        }
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    NextTaskComplication()
} timeline: {
    NextTaskEntry.placeholder
    NextTaskEntry.empty
}

#Preview(as: .accessoryRectangular) {
    NextTaskComplication()
} timeline: {
    NextTaskEntry.placeholder
    NextTaskEntry.empty
}
