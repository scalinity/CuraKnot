import SwiftUI
import WidgetKit

// MARK: - Last Handoff Complication

struct LastHandoffComplication: Widget {
    let kind = "com.curaknot.complication.lasthandoff"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LastHandoffProvider()) { entry in
            LastHandoffComplicationView(entry: entry)
        }
        .configurationDisplayName("Last Handoff")
        .description("Shows the most recent handoff")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Timeline Entry

struct LastHandoffEntry: TimelineEntry {
    let date: Date
    let handoffTitle: String?
    let handoffSummary: String?
    let publishedAt: Date?
    let createdByName: String?

    var relativeTime: String {
        guard let publishedAt = publishedAt else { return "" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: publishedAt, relativeTo: date)
    }

    static var placeholder: LastHandoffEntry {
        LastHandoffEntry(
            date: Date(),
            handoffTitle: "Good appetite today",
            handoffSummary: "Mom ate well at lunch, no issues with medication.",
            publishedAt: Date().addingTimeInterval(-3 * 3600),
            createdByName: "Sarah"
        )
    }

    static var empty: LastHandoffEntry {
        LastHandoffEntry(
            date: Date(),
            handoffTitle: nil,
            handoffSummary: nil,
            publishedAt: nil,
            createdByName: nil
        )
    }
}

// MARK: - Timeline Provider

struct LastHandoffProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastHandoffEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (LastHandoffEntry) -> Void) {
        let entry = loadCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastHandoffEntry>) -> Void) {
        let entry = loadCurrentEntry()

        // Refresh every 30 minutes
        let nextUpdate = Date().addingTimeInterval(30 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadCurrentEntry() -> LastHandoffEntry {
        guard let data = UserDefaults(suiteName: "group.com.curaknot.app")?.data(forKey: "complication_last_handoff"),
              let handoff = try? JSONDecoder().decode(ComplicationHandoff.self, from: data) else {
            return .empty
        }

        return LastHandoffEntry(
            date: Date(),
            handoffTitle: handoff.title,
            handoffSummary: handoff.summary,
            publishedAt: handoff.publishedAt,
            createdByName: handoff.createdByName
        )
    }
}

// MARK: - Complication Handoff (Shared Data)

struct ComplicationHandoff: Codable {
    let title: String
    let summary: String?
    let publishedAt: Date?
    let createdByName: String?
}

// MARK: - Complication View

struct LastHandoffComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: LastHandoffEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularHandoffView(entry: entry)
        case .accessoryInline:
            InlineHandoffView(entry: entry)
        default:
            EmptyView()
        }
    }
}

// MARK: - Rectangular View

private struct RectangularHandoffView: View {
    let entry: LastHandoffEntry

    var body: some View {
        if let title = entry.handoffTitle {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                    Text("Last Handoff")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                if let summary = entry.handoffSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text("No handoffs")
                        .font(.headline)
                }
                Text("No recent updates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Inline View

private struct InlineHandoffView: View {
    let entry: LastHandoffEntry

    var body: some View {
        if let title = entry.handoffTitle {
            Text("Update: \(title)")
        } else {
            Text("No recent updates")
        }
    }
}

// MARK: - Preview

#Preview(as: .accessoryRectangular) {
    LastHandoffComplication()
} timeline: {
    LastHandoffEntry.placeholder
    LastHandoffEntry.empty
}
