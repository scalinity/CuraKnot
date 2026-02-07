import Foundation
import SwiftUI

// MARK: - Cost Projections View Model

@MainActor
final class CostProjectionsViewModel: ObservableObject {
    enum ViewState { case idle, loading, loaded, error }

    @Published var state: ViewState = .idle
    @Published var errorMessage: String?
    @Published var currentScenario: CareCostEstimate?
    @Published var projectedScenarios: [CareCostEstimate] = []
    @Published var dataSource: String = ""
    @Published var dataYear: Int = 0
    @Published var areaName: String = ""
    @Published var showingCustomScenario = false
    @Published var zipCode: String = ""
    @Published var needsZipCode: Bool = true

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

    func loadProjections() async {
        guard !zipCode.isEmpty else {
            needsZipCode = true
            state = .loaded
            return
        }

        loadTask?.cancel()
        let task = Task {
            state = .loading
            needsZipCode = false

            do {
                let defaultScenarios: [ScenarioType] = [
                    .current,
                    .fullTimeHome,
                    .twentyFourSeven,
                    .assistedLiving,
                    .memoryCare,
                    .nursingHome
                ]

                let response = try await careCostService.generateCostEstimates(
                    circleId: circleId,
                    patientId: patientId,
                    zipCode: zipCode,
                    scenarios: defaultScenarios
                )

                try Task.checkCancellation()

                // Map response scenarios to CareCostEstimate models for UI
                var estimates: [CareCostEstimate] = []
                for scenario in response.scenarios {
                    let scenarioType = ScenarioType(rawValue: scenario.type) ?? .custom

                    // Parse breakdown into individual monthly fields
                    var homeCareMonthly: Decimal?
                    var medicationsMonthly: Decimal?
                    var suppliesMonthly: Decimal?
                    var transportationMonthly: Decimal?
                    var facilityMonthly: Decimal?
                    var otherMonthly: Decimal?

                    for item in scenario.breakdown {
                        let category = item.category.lowercased()
                        let amount = item.amount
                        if category.contains("home") || category.contains("aide") {
                            homeCareMonthly = (homeCareMonthly ?? 0) + amount
                        } else if category.contains("medication") {
                            medicationsMonthly = amount
                        } else if category.contains("suppli") {
                            suppliesMonthly = amount
                        } else if category.contains("transport") {
                            transportationMonthly = amount
                        } else if category.contains("facility") || category.contains("living") || category.contains("nursing") || category.contains("memory") {
                            facilityMonthly = (facilityMonthly ?? 0) + amount
                        } else {
                            otherMonthly = (otherMonthly ?? 0) + amount
                        }
                    }

                    let estimate = CareCostEstimate(
                        id: UUID().uuidString,
                        circleId: circleId,
                        patientId: patientId,
                        scenarioName: scenario.scenarioName,
                        scenarioType: scenarioType,
                        isCurrent: scenarioType == .current,
                        homeCareHoursWeekly: nil,
                        homeCareHourlyRate: nil,
                        homeCareMonthly: homeCareMonthly,
                        medicationsMonthly: medicationsMonthly,
                        suppliesMonthly: suppliesMonthly,
                        transportationMonthly: transportationMonthly,
                        facilityMonthly: facilityMonthly,
                        otherMonthly: otherMonthly,
                        totalMonthly: scenario.monthlyTotal,
                        medicareCoveragePct: nil,
                        medicaidCoveragePct: nil,
                        privateInsurancePct: nil,
                        outOfPocketMonthly: scenario.monthlyTotal,
                        notes: nil,
                        dataSource: response.localCostData.source,
                        dataYear: response.localCostData.year,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    estimates.append(estimate)
                }

                currentScenario = estimates.first { $0.isCurrent }
                projectedScenarios = estimates.filter { !$0.isCurrent }

                areaName = response.localCostData.areaName
                dataYear = response.localCostData.year
                dataSource = response.localCostData.source

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

    func reloadWithZipCode() async {
        guard !zipCode.isEmpty else { return }
        await loadProjections()
    }
}
