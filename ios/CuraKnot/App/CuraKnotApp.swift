import SwiftUI

@main
struct CuraKnotApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var dependencyContainer = DependencyContainer()

    init() {
        // Activate WatchConnectivity on app launch
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(dependencyContainer)
                .onAppear {
                    // CRITICAL: Configure AppState with dependencies
                    // This must be called for auth and sync operations to work
                    appState.configure(
                        authManager: dependencyContainer.authManager,
                        syncCoordinator: dependencyContainer.syncCoordinator
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchSyncRequested)) { _ in
                    // Watch requested sync - send current data
                    Task {
                        await sendCacheDataToWatch()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchVoiceDraftReceived)) { notification in
                    // Handle voice draft received from Watch
                    if let metadata = notification.userInfo?["metadata"] as? WatchDraftMetadata {
                        handleWatchVoiceDraft(metadata: metadata)
                    }
                }
        }
    }

    private func sendCacheDataToWatch() async {
        // This will be implemented when we have the data gathering logic
        // For now, a placeholder that shows the integration point
    }

    private func handleWatchVoiceDraft(metadata: WatchDraftMetadata) {
        // This will be implemented to create draft handoffs from Watch recordings
        // For now, a placeholder that shows the integration point
        #if DEBUG
        print("Received voice draft from Watch: patient=\(metadata.patientId), duration=\(metadata.duration)s")
        #endif
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            switch appState.authState {
            case .loading:
                LoadingView()
            case .unauthenticated:
                AuthView()
            case .authenticated:
                MainTabView()
            }
        }
        .task {
            await appState.checkAuthStatus()
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @State private var selectedTab: Tab = .timeline

    enum Tab: Hashable {
        case timeline
        case tasks
        case journal
        case wellness
        case binder
        case circle
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.timeline)

            TaskListView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(Tab.tasks)

            // Journal tab - requires circleId from AppState
            journalTabContent
                .tabItem {
                    Label("Journal", systemImage: "book.closed")
                }
                .tag(Tab.journal)

            WellnessTabView()
                .tabItem {
                    Label("Wellness", systemImage: "heart.text.square")
                }
                .tag(Tab.wellness)
            
            BinderView()
                .tabItem {
                    Label("Binder", systemImage: "folder")
                }
                .tag(Tab.binder)
            
            CircleSettingsView()
                .tabItem {
                    Label("Circle", systemImage: "person.2")
                }
                .tag(Tab.circle)
        }
        .overlay(alignment: .bottom) {
            NewHandoffButton()
                .padding(.bottom, 60)
        }
    }

    // MARK: - Journal Tab Content

    @ViewBuilder
    private var journalTabContent: some View {
        if let circleId = appState.currentCircleId {
            JournalListView(
                circleId: circleId,
                patientId: appState.currentPatientId,
                journalService: dependencyContainer.journalService
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Select a Care Circle")
                    .font(.headline)
                Text("Choose a circle to view the journal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - New Handoff Button

struct NewHandoffButton: View {
    @State private var showingNewHandoff = false
    
    var body: some View {
        Button {
            showingNewHandoff = true
        } label: {
            Label("New Handoff", systemImage: "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: Capsule())
                .shadow(radius: 4)
        }
        .sheet(isPresented: $showingNewHandoff) {
            NewHandoffView()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
