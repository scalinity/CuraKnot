import SwiftUI

/// View for manually tracking a concern
struct ManualTrackingView: View {
    let concern: TrackedConcern
    @ObservedObject var viewModel: SymptomPatternsViewModel

    @State private var entries: [TrackingEntry] = []
    @State private var isLoading = false
    @State private var showAddEntrySheet = false
    @State private var showResolveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                concernHeader

                // Quick add
                quickAddSection

                // History
                historySection

                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Track \(concern.concernName)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadEntries()
        }
        .sheet(isPresented: $showAddEntrySheet) {
            AddTrackingEntrySheet(concern: concern, viewModel: viewModel) {
                Task { await loadEntries() }
            }
        }
        .confirmationDialog(
            "Mark as Resolved?",
            isPresented: $showResolveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark Resolved") {
                Task { await resolveConcern() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will stop tracking this concern. You can start tracking again from the pattern if needed.")
        }
    }

    // MARK: - Header

    private var concernHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Text(concern.icon)
                    .font(.system(size: 48))

                VStack(alignment: .leading, spacing: 4) {
                    Text(concern.concernName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Tracking since \(concern.createdAt, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(concern.displayPrompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Quick Add

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How is it today?")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { rating in
                    QuickRatingButton(rating: rating) {
                        Task {
                            await addQuickEntry(rating: rating)
                        }
                    }
                }
            }

            Button {
                showAddEntrySheet = true
            } label: {
                Label("Add Note", systemImage: "square.and.pencil")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if entries.isEmpty && !isLoading {
                Text("No entries yet. Start tracking by rating how the concern is today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Simple trend visualization
                if entries.count >= 2 {
                    TrendChart(entries: entries)
                        .frame(height: 100)
                        .padding(.bottom, 8)
                }

                ForEach(entries.prefix(10)) { entry in
                    TrackingEntryRow(entry: entry)
                }

                if entries.count > 10 {
                    Text("+ \(entries.count - 10) more entries")
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
        Button {
            showResolveConfirmation = true
        } label: {
            Label("Mark as Resolved", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.2))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Actions

    private func loadEntries() async {
        guard let service = viewModel.service else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await service.fetchTrackingEntries(concernId: concern.id)
        } catch {
            #if DEBUG
            print("Failed to load entries: \(error)")
            #endif
        }
    }

    private func addQuickEntry(rating: Int) async {
        guard let service = viewModel.service else { return }

        do {
            let entry = try await service.addTrackingEntry(
                concernId: concern.id,
                rating: rating,
                notes: nil
            )
            entries.insert(entry, at: 0)
        } catch {
            #if DEBUG
            print("Failed to add entry: \(error)")
            #endif
        }
    }

    private func resolveConcern() async {
        guard let service = viewModel.service else { return }

        do {
            try await service.resolveConcern(concern.id)
        } catch {
            #if DEBUG
            print("Failed to resolve concern: \(error)")
            #endif
        }
    }
}

// MARK: - Supporting Views

struct QuickRatingButton: View {
    let rating: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.title2)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var emoji: String {
        switch rating {
        case 1: return "😊"
        case 2: return "🙂"
        case 3: return "😐"
        case 4: return "😟"
        case 5: return "😢"
        default: return "😐"
        }
    }

    private var label: String {
        switch rating {
        case 1: return "Much better"
        case 2: return "Better"
        case 3: return "Same"
        case 4: return "Worse"
        case 5: return "Much worse"
        default: return ""
        }
    }
}

struct TrackingEntryRow: View {
    let entry: TrackingEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let rating = entry.rating {
                    HStack(spacing: 4) {
                        Text(ratingEmoji(rating))
                        Text(entry.ratingDescription ?? "")
                            .font(.subheadline)
                    }
                }

                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(entry.recordedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func ratingEmoji(_ rating: Int) -> String {
        switch rating {
        case 1: return "😊"
        case 2: return "🙂"
        case 3: return "😐"
        case 4: return "😟"
        case 5: return "😢"
        default: return "😐"
        }
    }
}

struct TrendChart: View {
    let entries: [TrackingEntry]

    var body: some View {
        // Simple bar chart visualization
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(entries.prefix(14).reversed()) { entry in
                    if let rating = entry.rating {
                        Rectangle()
                            .fill(ratingColor(rating))
                            .frame(width: max(4, geometry.size.width / 16), height: barHeight(rating, maxHeight: geometry.size.height))
                    }
                }
            }
        }
    }

    private func barHeight(_ rating: Int, maxHeight: CGFloat) -> CGFloat {
        // Invert: rating 1 = tall bar (good), rating 5 = short bar (bad)
        let normalizedHeight = CGFloat(6 - rating) / 5.0
        return max(10, normalizedHeight * maxHeight)
    }

    private func ratingColor(_ rating: Int) -> Color {
        switch rating {
        case 1, 2: return .green
        case 3: return .yellow
        case 4, 5: return .red
        default: return .gray
        }
    }
}

// MARK: - Add Entry Sheet

struct AddTrackingEntrySheet: View {
    let concern: TrackedConcern
    @ObservedObject var viewModel: SymptomPatternsViewModel
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRating: Int = 3
    @State private var notes = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section(concern.displayPrompt) {
                    Picker("Rating", selection: $selectedRating) {
                        Text("Much better").tag(1)
                        Text("Better").tag(2)
                        Text("About the same").tag(3)
                        Text("Worse").tag(4)
                        Text("Much worse").tag(5)
                    }
                    .pickerStyle(.wheel)
                }

                Section("Notes (optional)") {
                    TextField("Any additional observations...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveEntry() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func saveEntry() async {
        guard let service = viewModel.service else { return }
        isSubmitting = true

        do {
            _ = try await service.addTrackingEntry(
                concernId: concern.id,
                rating: selectedRating,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
            dismiss()
        } catch {
            #if DEBUG
            print("Failed to save entry: \(error)")
            #endif
            isSubmitting = false
        }
    }
}
