import Foundation
import Combine

// MARK: - Journal List ViewModel

/// ViewModel for the journal timeline view
/// Manages entry list, filtering, and usage status
@MainActor
final class JournalListViewModel: ObservableObject {

    // MARK: - Published State

    @Published var entries: [JournalEntry] = []
    @Published var groupedEntries: [Date: [JournalEntry]] = [:]
    @Published var sortedDates: [Date] = []
    @Published var filter: JournalFilter = .all
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var error: JournalServiceError?
    @Published var usageCheck: JournalUsageCheck?
    @Published var canAttachPhotos = false
    @Published var canExportMemoryBook = false

    // MARK: - Properties

    let circleId: String
    let patientId: String?
    let journalService: JournalService

    // MARK: - Initialization

    init(
        circleId: String,
        patientId: String? = nil,
        journalService: JournalService
    ) {
        self.circleId = circleId
        self.patientId = patientId
        self.journalService = journalService

        // Apply patient filter if provided
        if let patientId = patientId {
            filter.patientId = patientId
        }
    }

    // MARK: - Data Loading

    /// Load entries from cache and sync
    func loadEntries() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            // Check feature access in parallel
            async let photosCheck = journalService.canAttachPhotos()
            async let exportCheck = journalService.canExportMemoryBook()
            async let usageResult = journalService.checkCanCreateEntry(circleId: circleId)

            canAttachPhotos = await photosCheck
            canExportMemoryBook = await exportCheck
            usageCheck = try await usageResult

            // Load entries
            let loadedEntries = try await journalService.fetchEntries(
                circleId: circleId,
                filter: filter
            )

            entries = loadedEntries
            updateGroupedEntries()

        } catch let serviceError as JournalServiceError {
            error = serviceError
        } catch {
            self.error = .syncFailed(error)
        }

        isLoading = false
    }

    /// Refresh entries (pull-to-refresh)
    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true

        do {
            let loadedEntries = try await journalService.fetchEntries(
                circleId: circleId,
                filter: filter
            )

            entries = loadedEntries
            updateGroupedEntries()

            // Refresh usage check
            usageCheck = try await journalService.checkCanCreateEntry(circleId: circleId)

        } catch {
            // Silently fail refresh, keep existing data
        }

        isRefreshing = false
    }

    // MARK: - Filtering

    /// Apply a new filter
    func applyFilter(_ newFilter: JournalFilter) async {
        filter = newFilter
        await loadEntries()
    }

    /// Apply a filter preset
    func applyPreset(_ preset: JournalFilterPreset) async {
        var newFilter = preset.toFilter()

        // Preserve patient filter if set
        if let patientId = patientId {
            newFilter.patientId = patientId
        }

        await applyFilter(newFilter)
    }

    /// Clear all filters
    func clearFilters() async {
        var clearedFilter = JournalFilter.all

        // Preserve patient filter if set
        if let patientId = patientId {
            clearedFilter.patientId = patientId
        }

        await applyFilter(clearedFilter)
    }

    // MARK: - Entry Management

    /// Called when a new entry is created
    func onEntryCreated(_ entry: JournalEntry) {
        entries.insert(entry, at: 0)
        updateGroupedEntries()

        // Refresh usage check
        Task {
            usageCheck = try? await journalService.checkCanCreateEntry(circleId: circleId)
        }
    }

    /// Called when an entry is updated
    func onEntryUpdated(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            updateGroupedEntries()
        }
    }

    /// Called when an entry is deleted
    func onEntryDeleted(_ entryId: String) {
        entries.removeAll { $0.id == entryId }
        updateGroupedEntries()
    }

    /// Delete an entry
    func deleteEntry(_ entry: JournalEntry) async throws {
        try await journalService.deleteEntry(id: entry.id)
        onEntryDeleted(entry.id)
    }

    // MARK: - Grouping

    /// Update grouped entries for timeline display
    private func updateGroupedEntries() {
        let calendar = Calendar.current
        var grouped: [Date: [JournalEntry]] = [:]

        for entry in entries {
            let dateKey = calendar.startOfDay(for: entry.entryDate)
            if grouped[dateKey] != nil {
                grouped[dateKey]?.append(entry)
            } else {
                grouped[dateKey] = [entry]
            }
        }

        groupedEntries = grouped
        sortedDates = grouped.keys.sorted(by: >)
    }

    // MARK: - Usage Status

    /// Check if user can create new entry
    /// Returns false if usage check hasn't been performed yet (safe default)
    var canCreateEntry: Bool {
        guard let usage = usageCheck else { return false }
        return usage.allowed
    }

    /// Check if user is near usage limit
    var isNearLimit: Bool {
        usageCheck?.isNearLimit ?? false
    }

    /// Remaining entries this month
    var remainingEntries: Int? {
        usageCheck?.remaining
    }

    /// Format remaining entries for display
    var usageDisplayText: String? {
        guard let usage = usageCheck, !usage.unlimited else { return nil }
        guard let limit = usage.limit else { return nil }

        if usage.current >= limit {
            return "Limit reached (\(usage.current)/\(limit))"
        } else if usage.current >= limit - 1 {
            return "\(limit - usage.current) entry left this month"
        }
        return nil
    }

    // MARK: - Empty State

    /// Check if there are no entries
    var isEmpty: Bool {
        entries.isEmpty && !isLoading
    }

    /// Empty state message based on filter
    var emptyStateMessage: String {
        if filter.isActive {
            return "No entries match your filter"
        }
        return "Start capturing the bright moments in your caregiving journey"
    }

    /// Empty state button title
    var emptyStateButtonTitle: String {
        if filter.isActive {
            return "Clear Filters"
        }
        return "Add First Entry"
    }
}

// MARK: - Section Header Formatting

extension JournalListViewModel {

    /// Format date for section header
    func sectionHeader(for date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter.string(from: date)
        }
    }
}
