import SwiftUI

/// Card displaying a detected symptom pattern
struct PatternCard: View {
    let pattern: DetectedPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and category
            HStack {
                Text(pattern.icon)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern.displayName)
                        .font(.headline)

                    HStack(spacing: 8) {
                        PatternTypeBadge(type: pattern.patternType)

                        if let trend = pattern.trend {
                            TrendBadge(trend: trend)
                        }
                    }
                }

                Spacer()

                if pattern.hasStrongCorrelation {
                    Image(systemName: "link")
                        .foregroundStyle(.orange)
                        .imageScale(.large)
                }
            }

            // Summary text
            Text(pattern.summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Correlation hint if present
            if let correlation = pattern.primaryCorrelation {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .imageScale(.small)
                        .foregroundStyle(.orange)
                    Text("Possibly related: \(correlation.eventDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Mention count badge
            HStack {
                Spacer()
                Text("\(pattern.mentionCount) mentions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Badge showing the pattern type
struct PatternTypeBadge: View {
    let type: PatternType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .imageScale(.small)
            Text(type.displayName)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(type.color.opacity(0.2))
        .foregroundStyle(type.color)
        .clipShape(Capsule())
    }
}

/// Badge showing trend direction
struct TrendBadge: View {
    let trend: TrendDirection

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.icon)
            Text(trend.displayName)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(trend.color.opacity(0.2))
        .foregroundStyle(trend.color)
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 16) {
        PatternCard(pattern: .preview)
        PatternCard(pattern: .previewWithCorrelation)
    }
    .padding()
}

// MARK: - Preview Helpers

extension DetectedPattern {
    static var preview: DetectedPattern {
        DetectedPattern(
            id: UUID(),
            circleId: UUID(),
            patientId: UUID(),
            concernCategory: .tiredness,
            concernKeywords: ["tired", "exhausted"],
            patternType: .frequency,
            patternHash: "abc123",
            mentionCount: 5,
            firstMentionAt: Date().addingTimeInterval(-7 * 24 * 60 * 60),
            lastMentionAt: Date().addingTimeInterval(-1 * 24 * 60 * 60),
            trend: .increasing,
            correlatedEvents: nil,
            status: .active,
            dismissedBy: nil,
            dismissedAt: nil,
            sourceHandoffIds: [UUID(), UUID()],
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static var previewWithCorrelation: DetectedPattern {
        DetectedPattern(
            id: UUID(),
            circleId: UUID(),
            patientId: UUID(),
            concernCategory: .pain,
            concernKeywords: ["pain", "aching"],
            patternType: .correlation,
            patternHash: "def456",
            mentionCount: 3,
            firstMentionAt: Date().addingTimeInterval(-5 * 24 * 60 * 60),
            lastMentionAt: Date().addingTimeInterval(-1 * 24 * 60 * 60),
            trend: nil,
            correlatedEvents: [
                CorrelatedEvent(
                    eventType: .medication,
                    eventId: UUID().uuidString,
                    eventDescription: "Lisinopril was added",
                    eventDate: Date().addingTimeInterval(-7 * 24 * 60 * 60),
                    daysDifference: 2,
                    strength: .strong
                )
            ],
            status: .active,
            dismissedBy: nil,
            dismissedAt: nil,
            sourceHandoffIds: [UUID()],
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
