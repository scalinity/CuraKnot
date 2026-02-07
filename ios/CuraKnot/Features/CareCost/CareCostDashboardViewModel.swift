import Foundation
import SwiftUI

// MARK: - Care Cost Dashboard View Model

@MainActor
final class CareCostDashboardViewModel: ObservableObject {
    enum ViewState {
        case idle, loading, loaded, error
    }

    @Published var state: ViewState = .idle
    @Published var errorMessage: String?
    @Published var currentMonthlyTotal: Decimal = 0
    @Published var costBreakdown: [ExpenseCategory: Decimal] = [:]
    @Published var insuranceCoveredTotal: Decimal = 0
    @Published var outOfPocketTotal: Decimal = 0
    @Published var expenseCount: Int = 0
    @Published var hasExpenseAccess: Bool = false
    @Published var hasProjectionAccess: Bool = false

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
            hasExpenseAccess = careCostService.hasExpenseAccess()
            hasProjectionAccess = careCostService.hasProjectionAccess()

            guard hasExpenseAccess else {
                state = .loaded
                return
            }

            do {
                try Task.checkCancellation()
                let now = Date()
                let expenses = try await careCostService.fetchExpenses(
                    circleId: circleId,
                    patientId: patientId,
                    month: now
                )

                try Task.checkCancellation()

                let summary = careCostService.calculateMonthlySummary(expenses: expenses)
                currentMonthlyTotal = summary.total
                costBreakdown = summary.breakdown
                insuranceCoveredTotal = summary.insuranceCovered
                outOfPocketTotal = summary.outOfPocket
                expenseCount = expenses.count
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

    func refresh() async {
        await load()
    }
}
