import Foundation

// MARK: - Condition List ViewModel

@MainActor
final class ConditionListViewModel: ObservableObject {

    // MARK: - Published State

    @Published var conditions: [TrackedCondition] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var activeCount: Int = 0
    @Published var canCreate: Bool = false
    @Published var showingNewCondition = false
    @Published var statusFilter: ConditionStatus? = .active

    // MARK: - Dependencies

    private var conditionPhotoService: ConditionPhotoService?
    private var subscriptionManager: SubscriptionManager?
    let circleId: UUID
    let patientId: UUID

    // MARK: - Computed

    var conditionLimit: Int? {
        guard let subscriptionManager else { return nil }
        switch subscriptionManager.currentPlan {
        case .free: return 0
        case .plus: return 5
        case .family: return nil
        }
    }

    var isAtLimit: Bool {
        guard let limit = conditionLimit else { return false }
        return activeCount >= limit
    }

    var limitLabel: String {
        if let limit = conditionLimit {
            return "\(activeCount)/\(limit) conditions"
        }
        return "\(activeCount) active"
    }

    // MARK: - Initialization

    init(circleId: UUID, patientId: UUID) {
        self.circleId = circleId
        self.patientId = patientId
    }

    func configure(conditionPhotoService: ConditionPhotoService, subscriptionManager: SubscriptionManager) {
        self.conditionPhotoService = conditionPhotoService
        self.subscriptionManager = subscriptionManager
    }

    // MARK: - Data Loading

    func loadConditions() async {
        guard let conditionPhotoService, let subscriptionManager else { return }
        isLoading = true
        errorMessage = nil

        do {
            conditions = try await conditionPhotoService.getConditions(
                circleId: circleId,
                patientId: patientId,
                status: statusFilter
            )
            activeCount = try await conditionPhotoService.getActiveConditionCount(circleId: circleId)

            // Compute canCreate locally based on plan and active count
            switch subscriptionManager.currentPlan {
            case .free:
                canCreate = false
            case .plus:
                canCreate = activeCount < 5
            case .family:
                canCreate = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Actions

    func createCondition(
        type: ConditionType,
        bodyLocation: String,
        description: String?,
        startDate: Date
    ) async {
        guard let conditionPhotoService, let subscriptionManager else { return }

        // Validate input
        let trimmedLocation = bodyLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else {
            errorMessage = "Body location is required."
            return
        }

        do {
            let condition = try await conditionPhotoService.createCondition(
                circleId: circleId,
                patientId: patientId,
                type: type,
                bodyLocation: trimmedLocation,
                description: description,
                startDate: startDate
            )
            conditions.insert(condition, at: 0)
            activeCount += 1

            // Recompute canCreate
            switch subscriptionManager.currentPlan {
            case .free:
                canCreate = false
            case .plus:
                canCreate = activeCount < 5
            case .family:
                canCreate = true
            }

            showingNewCondition = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
