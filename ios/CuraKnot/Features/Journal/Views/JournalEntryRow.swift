import SwiftUI

// MARK: - Journal Entry Row

/// A row displaying a journal entry in the timeline list
struct JournalEntryRow: View {
    let entry: JournalEntry
    var authorName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Date, Type, Privacy
            HStack(spacing: 6) {
                // Milestone emoji
                if entry.isMilestone {
                    Text("🎉")
                }

                // Date
                Text(entry.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.secondary)

                // Entry type
                Text(entry.entryType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Privacy badge
                if entry.isPrivate {
                    VisibilityBadge(visibility: .private)
                }
            }

            // Title (milestones only)
            if let title = entry.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            }

            // Content preview
            Text(entry.displaySummary)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)

            // Photo thumbnails (if any)
            if entry.hasPhotos {
                HStack(spacing: 4) {
                    ForEach(0..<min(entry.photoCount, 3), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            )
                    }

                    if entry.photoCount > 3 {
                        Text("+\(entry.photoCount - 3)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Author attribution
            if let name = authorName {
                Text("— \(name)")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }

            // Milestone type badge
            if let milestoneType = entry.milestoneType {
                HStack(spacing: 4) {
                    Image(systemName: milestoneType.icon)
                        .font(.caption2)

                    Text(milestoneType.displayName)
                        .font(.caption2)
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Compact Entry Row

/// A more compact version for dense lists
struct JournalEntryCompactRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: entry.entryType.icon)
                .font(.title3)
                .foregroundStyle(entry.isMilestone ? .purple : .secondary)
                .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                if let title = entry.title {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Text(entry.displaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Date
            Text(entry.relativeDate)
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Privacy indicator
            if entry.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        Section("Standard Rows") {
            JournalEntryRow(
                entry: JournalEntry(
                    circleId: "circle1",
                    patientId: "patient1",
                    createdBy: "user1",
                    entryType: .goodMoment,
                    content: "Mom recognized me today when I walked in. She said my name and reached for my hand. It was brief but wonderful.",
                    visibility: .circle
                ),
                authorName: "Jane"
            )

            JournalEntryRow(
                entry: JournalEntry(
                    circleId: "circle1",
                    patientId: "patient1",
                    createdBy: "user1",
                    entryType: .milestone,
                    title: "One Year Since Diagnosis",
                    content: "It's been one year since Mom's diagnosis. We've learned so much and grown closer as a family.",
                    milestoneType: .anniversary,
                    visibility: .private
                )
            )
        }

        Section("Compact Rows") {
            JournalEntryCompactRow(
                entry: JournalEntry(
                    circleId: "circle1",
                    patientId: "patient1",
                    createdBy: "user1",
                    entryType: .goodMoment,
                    content: "Great visit today!",
                    visibility: .circle
                )
            )
        }
    }
}
