import SwiftUI

// MARK: - Wellness Tab View

/// Wrapper view for the wellness feature that injects dependencies
struct WellnessTabView: View {
    @EnvironmentObject private var dependencyContainer: DependencyContainer
    @EnvironmentObject private var appState: AppState

    private var wellnessService: WellnessService {
        let service = dependencyContainer.wellnessService
        service.setCurrentUserId(appState.currentUser?.id)
        return service
    }

    var body: some View {
        WellnessView(wellnessService: wellnessService)
            .onChange(of: appState.currentUser?.id) { _, newId in
                dependencyContainer.wellnessService.setCurrentUserId(newId)
            }
    }
}
