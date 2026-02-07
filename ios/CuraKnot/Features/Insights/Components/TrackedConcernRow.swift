import SwiftUI

/// Row displaying a tracked concern
struct TrackedConcernRow: View {
    let concern: TrackedConcern
    var latestEntry: TrackingEntry?

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Text(concern.icon)
                .font(.title2)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(concern.concernName)
                    .font(.body)
                    .fontWeight(.medium)

                if let entry = latestEntry {
                    HStack(spacing: 4) {
                        if let rating = entry.rating {
                            RatingIndicator(rating: rating)
                        }
                        Text(entry.recordedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No entries yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status indicator
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Small rating indicator
struct RatingIndicator: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: ratingIcon)
                .imageScale(.small)
            Text(ratingText)
        }
        .font(.caption)
        .foregroundStyle(ratingColor)
    }

    private var ratingIcon: String {
        switch rating {
        case 1, 2: return "arrow.down"
        case 3: return "minus"
        case 4, 5: return "arrow.up"
        default: return "minus"
        }
    }

    private var ratingText: String {
        switch rating {
        case 1: return "Much better"
        case 2: return "Better"
        case 3: return "Same"
        case 4: return "Worse"
        case 5: return "Much worse"
        default: return ""
        }
    }

    private var ratingColor: Color {
        switch rating {
        case 1, 2: return .green
        case 3: return .orange
        case 4, 5: return .red
        default: return .gray
        }
    }
}

#Preview {
    List {
        TrackedConcernRow(
            concern: .preview,
            latestEntry: .preview
        )
        TrackedConcernRow(
            concern: .preview,
            latestEntry: nil
        )
    }
}

// MARK: - Preview Helpers

extension TrackedConcern {
    static var preview: TrackedConcern {
        TrackedConcern(
            id: UUID(),
            circleId: UUID(),
            patientId: UUID(),
            patternId: nil,
            createdBy: UUID(),
            concernName: "Tiredness",
            concernCategory: .tiredness,
            trackingPrompt: "How was tiredness today?",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

extension TrackingEntry {
    static var preview: TrackingEntry {
        TrackingEntry(
            id: UUID(),
            concernId: UUID(),
            recordedBy: UUID(),
            rating: 3,
            notes: "About the same as yesterday",
            handoffId: nil,
            recordedAt: Date().addingTimeInterval(-2 * 60 * 60),
            createdAt: Date().addingTimeInterval(-2 * 60 * 60)
        )
    }
}
