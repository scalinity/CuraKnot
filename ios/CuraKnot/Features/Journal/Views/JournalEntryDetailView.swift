import SwiftUI

// MARK: - Journal Entry Detail View

/// Full detail view for a journal entry
struct JournalEntryDetailView: View {
    let entry: JournalEntry
    var authorName: String?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onVisibilityChange: ((EntryVisibility) -> Void)?

    @State private var showingDeleteConfirmation = false
    @State private var showingVisibilitySheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Content
                contentSection

                // Photos
                if entry.hasPhotos {
                    photosSection
                }

                // Milestone details
                if entry.isMilestone, let milestoneType = entry.milestoneType {
                    milestoneSection(milestoneType)
                }

                // Metadata
                metadataSection
            }
            .padding()
        }
        .navigationTitle(entry.isMilestone ? "Milestone" : "Good Moment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if onEdit != nil {
                        Button(action: { onEdit?() }) {
                            Label("Edit", systemImage: "pencil")
                        }
                    }

                    if onVisibilityChange != nil {
                        Button(action: { showingVisibilitySheet = true }) {
                            Label(
                                entry.isPrivate ? "Share with Circle" : "Make Private",
                                systemImage: entry.isPrivate ? "person.2" : "lock"
                            )
                        }
                    }

                    if onDelete != nil {
                        Divider()

                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete Entry",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry will be permanently deleted.")
        }
        .sheet(isPresented: $showingVisibilitySheet) {
            visibilitySheet
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Entry type badge
            HStack {
                Label(
                    entry.entryType.displayName,
                    systemImage: entry.entryType.icon
                )
                .font(.subheadline)
                .foregroundStyle(entry.isMilestone ? .purple : .secondary)

                Spacer()

                VisibilityBadge(visibility: entry.visibility)
            }

            // Title (milestones)
            if let title = entry.title {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            // Date
            Text(entry.formattedDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        Text(entry.content)
            .font(.body)
            .lineSpacing(4)
    }

    // MARK: - Photos Section

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photos")
                .font(.headline)

            // Placeholder for photo grid
            // In production, load actual photos from storage keys
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(0..<entry.photoCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
    }

    // MARK: - Milestone Section

    private func milestoneSection(_ type: MilestoneType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Milestone Type")
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title3)

                VStack(alignment: .leading) {
                    Text(type.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            if let authorName = authorName {
                HStack {
                    Text("By")
                        .foregroundStyle(.secondary)
                    Text(authorName)
                        .fontWeight(.medium)
                }
                .font(.caption)
            }

            HStack {
                Text("Created")
                    .foregroundStyle(.secondary)
                Text(entry.createdAt, style: .date)
            }
            .font(.caption)

            if entry.updatedAt > entry.createdAt {
                HStack {
                    Text("Updated")
                        .foregroundStyle(.secondary)
                    Text(entry.updatedAt, style: .relative)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Visibility Sheet

    private var visibilitySheet: some View {
        NavigationStack {
            List {
                ForEach(EntryVisibility.allCases, id: \.self) { option in
                    Button {
                        onVisibilityChange?(option)
                        showingVisibilitySheet = false
                    } label: {
                        HStack {
                            Image(systemName: option.icon)
                                .foregroundStyle(option == entry.visibility ? Color.accentColor : .secondary)

                            VStack(alignment: .leading) {
                                Text(option.displayName)
                                    .foregroundStyle(.primary)
                                Text(option.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if option == entry.visibility {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Change Visibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingVisibilitySheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        JournalEntryDetailView(
            entry: JournalEntry(
                circleId: "circle1",
                patientId: "patient1",
                createdBy: "user1",
                entryType: .milestone,
                title: "One Year Anniversary",
                content: "Today marks one year since we started this caregiving journey. It's been challenging but also filled with moments of connection and growth. We've learned so much about patience, love, and what really matters in life.",
                milestoneType: .anniversary,
                photoStorageKeys: ["photo1", "photo2"],
                visibility: .circle
            ),
            authorName: "Jane",
            onEdit: {},
            onDelete: {},
            onVisibilityChange: { _ in }
        )
    }
}
