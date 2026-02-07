import Foundation
import SwiftUI

// MARK: - Wellness View Model

/// Main ViewModel for the wellness feature
/// Coordinates check-ins, alerts, and dashboard state
@MainActor
final class WellnessViewModel: ObservableObject {

    // MARK: - Types

    enum ViewState: Equatable {
        case loading
        case needsSubscription
        case needsCheckIn
        case hasCheckIn(WellnessCheckIn)
        case error(String)

        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.needsSubscription, .needsSubscription): return true
            case (.needsCheckIn, .needsCheckIn): return true
            case (.hasCheckIn(let a), .hasCheckIn(let b)): return a.id == b.id
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Properties

    let wellnessService: WellnessService

    @Published var viewState: ViewState = .loading
    @Published var activeAlerts: [WellnessAlert] = []
    @Published var showCheckInSheet = false
    @Published var showSettingsSheet = false
    @Published var showHistorySheet = false
    @Published var dismissError: String?

    var currentCheckIn: WellnessCheckIn? {
        if case .hasCheckIn(let checkIn) = viewState {
            return checkIn
        }
        return nil
    }

    var hasActiveAlerts: Bool {
        !activeAlerts.isEmpty
    }

    var highestSeverityAlert: WellnessAlert? {
        activeAlerts.first { $0.riskLevel == .high } ?? activeAlerts.first
    }

    // MARK: - Initialization

    init(wellnessService: WellnessService) {
        self.wellnessService = wellnessService
    }

    // MARK: - Data Loading

    func loadData() async {
        viewState = .loading

        do {
            // Check subscription first
            try await wellnessService.checkSubscriptionStatus()

            if !wellnessService.hasSubscription {
                viewState = .needsSubscription
                return
            }

            // Fetch current check-in
            if let checkIn = try await wellnessService.getCurrentWeekCheckIn() {
                viewState = .hasCheckIn(checkIn)
            } else {
                viewState = .needsCheckIn
            }

            // Fetch alerts
            try await wellnessService.fetchActiveAlerts()
            activeAlerts = wellnessService.activeAlerts

            // Fetch preferences
            try await wellnessService.fetchPreferences()

        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    func refreshData() async {
        await loadData()
    }

    // MARK: - Alert Actions

    func dismissAlert(_ alert: WellnessAlert) async {
        dismissError = nil
        do {
            try await wellnessService.dismissAlert(alert)
            activeAlerts.removeAll { $0.id == alert.id }
        } catch {
            // Show error to user - alert remains visible for retry
            dismissError = "Unable to dismiss alert. Please try again."
        }
    }

    func clearDismissError() {
        dismissError = nil
    }

    // MARK: - Check-In Actions

    func startCheckIn() {
        showCheckInSheet = true
    }

    func checkInCompleted(_ checkIn: WellnessCheckIn) {
        viewState = .hasCheckIn(checkIn)
        showCheckInSheet = false
    }

    // MARK: - Navigation

    func openSettings() {
        showSettingsSheet = true
    }

    func openHistory() {
        showHistorySheet = true
    }
}
