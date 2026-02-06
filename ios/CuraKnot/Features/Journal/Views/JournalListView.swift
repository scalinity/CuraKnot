import SwiftUI

// MARK: - Journal List View

/// Main journal timeline view showing entries grouped by date
struct JournalListView: View {
    @StateObject private var viewModel: JournalListViewModel
    @State private var showingNewEntry = false
    @State private var showingFilter = false
    @State private var showingExport = false

    init(circleId: String, patientId: String? = nil, journalService: JournalService) {
        _viewModel = StateObject(wrappedValue: JournalListViewModel(
            circleId: circleId,
            patientId: patientId,
            journalService: journalService
        ))
    }

    var body: some View {
        ZStack {
            if viewModel.isEmpty {
                JournalEmptyState(
                    onCreateEntry: { showingNewEntry = true },
                    isFiltered: viewModel.filter.isActive,
                    onClearFilters: {
                        Task { await viewModel.clearFilters() }
                    }
                )
            } else {
                entriesList
            }
        }
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!viewModel.canCreateEntry)
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    ForEach(JournalFilterPreset.allCases) { preset in
                        Button {
                            Task { await viewModel.applyPreset(preset) }
                        } label: {
                            Label(preset.displayName, systemImage: preset.icon)
                        }
                    }

                    if viewModel.canExportMemoryBook {
                        Divider()

                        Button {
                            showingExport = true
                        } label: {
                            Label("Export Memory Book", systemImage: "book")
                        }
                    }
                } label: {
                    Image(systemName: viewModel.filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle"
                    )
                }
            }
        }
        .task {
            await viewModel.loadEntries()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showingNewEntry) {
            // Entry sheet would be presented here
            // JournalEntrySheet(...)
            Text("New Entry Sheet")
        }
        .sheet(isPresented: $showingExport) {
            MemoryBookExportView(
                circleId: viewModel.circleId,
                journalService: viewModel.journalService
            )
        }
    }

    // MARK: - Entries List

    private var entriesList: some View {
        List {
            // Usage limit banner (if applicable)
            if let displayText = viewModel.usageDisplayText {
                Section {
                    UsageLimitBanner(
                        current: viewModel.usageCheck?.current ?? 0,
                        limit: viewModel.usageCheck?.limit ?? 5
                    ) {
                        // Navigate to upgrade
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Grouped entries by date
            ForEach(viewModel.sortedDates, id: \.self) { date in
                Section {
                    if let entries = viewModel.groupedEntries[date] {
                        ForEach(entries, id: \.id) { entry in
                            NavigationLink {
                                JournalEntryDetailView(
                                    entry: entry,
                                    onEdit: nil,
                                    onDelete: {
                                        Task { try? await viewModel.deleteEntry(entry) }
                                    },
                                    onVisibilityChange: nil
                                )
                            } label: {
                                JournalEntryRow(entry: entry)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { try? await viewModel.deleteEntry(entry) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text(viewModel.sectionHeader(for: date))
                        .font(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Journal List View with convenience init

extension JournalListView {
    /// Convenience initializer that pulls from DependencyContainer
    init(circleId: String, patientId: String? = nil) {
        // In production, this would use @EnvironmentObject or similar
        // For now, this is a placeholder
        fatalError("Use init with explicit journalService")
    }
}

#Preview {
    NavigationStack {
        // Would need mock service for preview
        Text("Journal List Preview")
    }
}
