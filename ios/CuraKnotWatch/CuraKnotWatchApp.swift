import SwiftUI

@main
struct CuraKnotWatchApp: App {
    // Use @ObservedObject for singletons, not @StateObject (rule-020)
    // @StateObject would try to manage the lifecycle of an already-existing singleton
    @ObservedObject private var connectivityHandler = WatchConnectivityHandler.shared
    @ObservedObject private var dataManager = WatchDataManager.shared

    init() {
        // Activate WatchConnectivity
        WatchConnectivityHandler.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivityHandler)
                .environmentObject(dataManager)
        }
    }
}

// MARK: - Content View (Subscription Gate)

struct ContentView: View {
    @EnvironmentObject var connectivityHandler: WatchConnectivityHandler
    @EnvironmentObject var dataManager: WatchDataManager

    var body: some View {
        if dataManager.hasWatchAccess {
            DashboardView()
        } else {
            PlusRequiredView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityHandler.shared)
        .environmentObject(WatchDataManager.shared)
}
