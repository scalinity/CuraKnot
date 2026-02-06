import Foundation

// MARK: - Memory Book ViewModel

/// ViewModel for Memory Book PDF export configuration and generation
@MainActor
final class MemoryBookViewModel: ObservableObject {

    // MARK: - Export State

    enum ExportState: Equatable {
        case idle
        case checkingAccess
        case configuring
        case generating
        case ready(URL)
        case error(String)
    }

    @Published var state: ExportState = .idle

    // MARK: - Configuration

    @Published var dateRangeOption: DateRangeOption = .allTime
    @Published var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
    @Published var customEndDate: Date = Date()
    @Published var includePrivateEntries: Bool = false

    // MARK: - Access

    @Published var hasAccess: Bool = false

    // MARK: - Properties

    let circleId: String
    private let journalService: JournalService

    // MARK: - Initialization

    init(circleId: String, journalService: JournalService) {
        self.circleId = circleId
        self.journalService = journalService
    }

    // MARK: - Date Range Options

    enum DateRangeOption: String, CaseIterable, Identifiable {
        case last30Days = "last_30"
        case last3Months = "last_3_months"
        case lastYear = "last_year"
        case allTime = "all_time"
        case custom = "custom"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .last30Days: return "Last 30 Days"
            case .last3Months: return "Last 3 Months"
            case .lastYear: return "Last Year"
            case .allTime: return "All Time"
            case .custom: return "Custom Range"
            }
        }

        var dateRange: (start: Date, end: Date)? {
            let calendar = Calendar.current
            let now = Date()

            switch self {
            case .last30Days:
                return (calendar.date(byAdding: .day, value: -30, to: now) ?? now, now)
            case .last3Months:
                return (calendar.date(byAdding: .month, value: -3, to: now) ?? now, now)
            case .lastYear:
                return (calendar.date(byAdding: .year, value: -1, to: now) ?? now, now)
            case .allTime:
                // Use a very old date for "all time"
                return (Date(timeIntervalSince1970: 0), now)
            case .custom:
                return nil  // Use custom dates
            }
        }
    }

    // MARK: - Computed Properties

    /// Get the effective date range based on selection
    var effectiveDateRange: (start: Date, end: Date) {
        if dateRangeOption == .custom {
            return (customStartDate, customEndDate)
        }
        return dateRangeOption.dateRange ?? (customStartDate, customEndDate)
    }

    /// Check if custom date range is valid
    var isDateRangeValid: Bool {
        if dateRangeOption == .custom {
            return customStartDate <= customEndDate
        }
        return true
    }

    /// Check if generating is in progress
    var isGenerating: Bool {
        if case .generating = state { return true }
        return false
    }

    /// Get the generated PDF URL
    var pdfURL: URL? {
        if case .ready(let url) = state { return url }
        return nil
    }

    /// Get error message
    var errorMessage: String? {
        if case .error(let message) = state { return message }
        return nil
    }

    // MARK: - Actions

    /// Check if user has access to Memory Book export
    func checkAccess() async {
        state = .checkingAccess

        hasAccess = await journalService.canExportMemoryBook()

        if hasAccess {
            state = .configuring
        } else {
            state = .error("Memory Book export requires a Family subscription")
        }
    }

    /// Generate the Memory Book PDF
    func generate() async {
        guard hasAccess else {
            state = .error("Memory Book export requires a Family subscription")
            return
        }

        guard isDateRangeValid else {
            state = .error("Invalid date range. Start date must be before end date.")
            return
        }

        state = .generating

        do {
            let range = effectiveDateRange
            let url = try await journalService.generateMemoryBook(
                circleId: circleId,
                patientId: nil,
                dateRange: range.start...range.end
            )

            state = .ready(url)

        } catch let serviceError as JournalServiceError {
            switch serviceError {
            case .featureNotAvailable(let feature):
                state = .error("\(feature) requires a Family subscription")
            case .memoryBookGenerationFailed:
                state = .error("Failed to generate Memory Book. Please try again.")
            default:
                state = .error(serviceError.localizedDescription)
            }
        } catch {
            state = .error("An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    /// Reset state for new export
    func reset() {
        state = hasAccess ? .configuring : .idle
        dateRangeOption = .allTime
        includePrivateEntries = false
    }

    /// Dismiss error and return to configuring
    func dismissError() {
        if hasAccess {
            state = .configuring
        } else {
            state = .idle
        }
    }
}

// MARK: - Formatted Date Display

extension MemoryBookViewModel {

    /// Format date range for display
    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let range = effectiveDateRange
        return "\(formatter.string(from: range.start)) – \(formatter.string(from: range.end))"
    }
}
