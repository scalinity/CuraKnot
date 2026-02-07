import SwiftUI
import WidgetKit

// MARK: - Emergency Complication

struct EmergencyComplication: Widget {
    let kind = "com.curaknot.complication.emergency"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EmergencyProvider()) { entry in
            EmergencyComplicationView(entry: entry)
        }
        .configurationDisplayName("Emergency Card")
        .description("Quick access to emergency info")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner
        ])
    }
}

// MARK: - Timeline Entry

struct EmergencyEntry: TimelineEntry {
    let date: Date
    let patientInitials: String
    let hasEmergencyCard: Bool

    static var placeholder: EmergencyEntry {
        EmergencyEntry(
            date: Date(),
            patientInitials: "MJ",
            hasEmergencyCard: true
        )
    }

    static var empty: EmergencyEntry {
        EmergencyEntry(
            date: Date(),
            patientInitials: "?",
            hasEmergencyCard: false
        )
    }
}

// MARK: - Timeline Provider

struct EmergencyProvider: TimelineProvider {
    func placeholder(in context: Context) -> EmergencyEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (EmergencyEntry) -> Void) {
        let entry = loadCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EmergencyEntry>) -> Void) {
        let entry = loadCurrentEntry()

        // Refresh every hour (emergency card data doesn't change often)
        let nextUpdate = Date().addingTimeInterval(60 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadCurrentEntry() -> EmergencyEntry {
        guard let data = UserDefaults(suiteName: "group.com.curaknot.app")?.data(forKey: "complication_emergency"),
              let emergency = try? JSONDecoder().decode(ComplicationEmergency.self, from: data) else {
            return .empty
        }

        return EmergencyEntry(
            date: Date(),
            patientInitials: emergency.patientInitials,
            hasEmergencyCard: emergency.hasCard
        )
    }
}

// MARK: - Complication Emergency (Shared Data)

struct ComplicationEmergency: Codable {
    let patientInitials: String
    let hasCard: Bool
}

// MARK: - Complication View

struct EmergencyComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: EmergencyEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularEmergencyView(entry: entry)
        case .accessoryCorner:
            CornerEmergencyView(entry: entry)
        default:
            EmptyView()
        }
    }
}

// MARK: - Circular View

private struct CircularEmergencyView: View {
    let entry: EmergencyEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Image(systemName: "staroflife.fill")
                    .font(.title3)
                    .foregroundStyle(.red)

                if entry.hasEmergencyCard {
                    Text(entry.patientInitials)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Corner View

private struct CornerEmergencyView: View {
    let entry: EmergencyEntry

    var body: some View {
        Image(systemName: "staroflife.fill")
            .font(.title3)
            .foregroundStyle(.red)
            .widgetCurvesContent()
            .widgetLabel {
                if entry.hasEmergencyCard {
                    Text(entry.patientInitials)
                } else {
                    Text("SOS")
                }
            }
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    EmergencyComplication()
} timeline: {
    EmergencyEntry.placeholder
    EmergencyEntry.empty
}

#Preview(as: .accessoryCorner) {
    EmergencyComplication()
} timeline: {
    EmergencyEntry.placeholder
}
