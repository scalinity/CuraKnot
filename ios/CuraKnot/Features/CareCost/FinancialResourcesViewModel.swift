import Foundation
import SwiftUI

// MARK: - Financial Resources View Model

@MainActor
final class FinancialResourcesViewModel: ObservableObject {
    enum ViewState { case idle, loading, loaded, error }

    @Published var state: ViewState = .idle
    @Published var resources: [FinancialResource] = []
    @Published var selectedCategory: ResourceCategory?
    @Published var errorMessage: String?

    private let careCostService: CareCostService
    private var loadTask: Task<Void, Never>?

    var filteredResources: [FinancialResource] {
        guard let category = selectedCategory else {
            return resources
        }
        return resources.filter { $0.category == category }
    }

    var groupedResources: [(category: ResourceCategory, resources: [FinancialResource])] {
        let filtered = filteredResources
        let grouped = Dictionary(grouping: filtered) { $0.category }

        return ResourceCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category: category, resources: items)
        }
    }

    init(careCostService: CareCostService) {
        self.careCostService = careCostService
    }

    deinit {
        loadTask?.cancel()
    }

    func load() async {
        loadTask?.cancel()
        let task = Task {
            state = .loading

            do {
                try Task.checkCancellation()
                resources = try await careCostService.fetchFinancialResources()
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
}
