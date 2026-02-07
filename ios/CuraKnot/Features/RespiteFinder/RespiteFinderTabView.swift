import SwiftUI

// MARK: - Respite Finder Tab View

/// Wrapper view that injects dependencies for the respite finder feature
struct RespiteFinderTabView: View {
    @EnvironmentObject private var dependencyContainer: DependencyContainer

    var body: some View {
        RespiteFinderView(service: dependencyContainer.respiteFinderService)
    }
}
