import Foundation
import SwiftUI

// MARK: - Export Format

enum CareCostExportFormat: String, CaseIterable {
    case pdf = "PDF"
    case csv = "CSV"

    var icon: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        }
    }
}

// MARK: - Expense Tracker View Model

@MainActor
final class ExpenseTrackerViewModel: ObservableObject {
    enum ViewState { case idle, loading, loaded, error }

    @Published var state: ViewState = .idle
    @Published var errorMessage: String?
    @Published var expenses: [CareExpense] = []
    @Published var monthlyGroups: [(month: String, expenses: [CareExpense], total: Decimal)] = []
    @Published var showingAddExpense = false
    @Published var showingExport = false
    @Published var exportURL: URL?
    @Published var isExporting = false
    @Published var hasExportAccess: Bool = false

    private let careCostService: CareCostService
    private var loadTask: Task<Void, Never>?
    let circleId: String
    let patientId: String

    init(careCostService: CareCostService, circleId: String, patientId: String) {
        self.careCostService = careCostService
        self.circleId = circleId
        self.patientId = patientId
    }

    deinit {
        loadTask?.cancel()
    }

    func load() async {
        loadTask?.cancel()
        let task = Task {
            state = .loading
            hasExportAccess = careCostService.hasExportAccess()

            do {
                try Task.checkCancellation()
                expenses = try await careCostService.fetchExpenses(
                    circleId: circleId,
                    patientId: patientId
                )
                monthlyGroups = groupByMonth(expenses)
                state = .loaded
            } catch is CancellationError {
                // Task was cancelled, don't update state
            } catch {
                errorMessage = error.localizedDescription
                state = .error
            }
        }
        loadTask = task
        await task.value
    }

    func deleteExpense(_ expense: CareExpense) async {
        do {
            try await careCostService.deleteExpense(id: expense.id)
            expenses.removeAll { $0.id == expense.id }
            monthlyGroups = groupByMonth(expenses)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportReport(format: CareCostExportFormat, startDate: Date, endDate: Date) async {
        isExporting = true
        defer { isExporting = false }

        do {
            let exportFormat: ExportFormat = format == .pdf ? .pdf : .csv
            let url = try await careCostService.generateExpenseReport(
                circleId: circleId,
                patientId: patientId,
                startDate: startDate,
                endDate: endDate,
                format: exportFormat
            )
            exportURL = url
            showingExport = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func groupByMonth(_ expenses: [CareExpense]) -> [(month: String, expenses: [CareExpense], total: Decimal)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: expenses) { expense -> DateComponents in
            calendar.dateComponents([.year, .month], from: expense.expenseDate)
        }

        return grouped
            .sorted { lhs, rhs in
                let lhsDate = calendar.date(from: lhs.key) ?? .distantPast
                let rhsDate = calendar.date(from: rhs.key) ?? .distantPast
                return lhsDate > rhsDate
            }
            .map { components, groupExpenses in
                let date = calendar.date(from: components) ?? Date()
                let monthLabel = formatter.string(from: date)
                let total = groupExpenses.reduce(Decimal(0)) { $0 + $1.amount }
                let sorted = groupExpenses.sorted { $0.expenseDate > $1.expenseDate }
                return (month: monthLabel, expenses: sorted, total: total)
            }
    }
}
