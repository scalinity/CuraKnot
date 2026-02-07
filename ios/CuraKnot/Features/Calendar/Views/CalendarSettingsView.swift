import SwiftUI
import EventKit

// MARK: - Calendar Settings View

struct CalendarSettingsView: View {
    @StateObject private var viewModel: CalendarSettingsViewModel
    @EnvironmentObject var appState: AppState

    init(calendarSyncService: CalendarSyncService, appleProvider: AppleCalendarProvider) {
        _viewModel = StateObject(wrappedValue: CalendarSettingsViewModel(
            calendarSyncService: calendarSyncService,
            appleProvider: appleProvider,
            circleId: "", // Will be set from appState
            userId: ""
        ))
    }

    var body: some View {
        List {
            // Tier gating banner for FREE users
            if viewModel.accessLevel == .readOnly || viewModel.accessLevel == .none {
                UpgradeBannerSection()
            }

            // Connected calendars
            if viewModel.accessLevel.canSync {
                ConnectedCalendarsSection(viewModel: viewModel)
            }

            // Sync settings
            if viewModel.hasActiveConnection {
                SyncSettingsSection(viewModel: viewModel)
            }

            // iCal Feed
            if viewModel.accessLevel.canGenerateICalFeed {
                ICalFeedSection(viewModel: viewModel)
            }

            // Sync status
            if viewModel.hasActiveConnection {
                SyncStatusSection(viewModel: viewModel)
            }

            // Conflicts
            if viewModel.hasConflicts {
                ConflictsSection(viewModel: viewModel)
            }
        }
        .navigationTitle("Calendar Sync")
        .task {
            // Configure viewModel with IDs from AppState before loading
            if let circleId = appState.currentCircle?.id,
               let userId = appState.currentUser?.id {
                viewModel.configure(circleId: circleId, userId: userId)
            }
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: $viewModel.showAddCalendar) {
            CalendarConnectionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showICalFeed) {
            // ICalFeedView would go here
            Text("iCal Feed Management")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An error occurred")
        }
    }
}

// MARK: - Upgrade Banner Section

private struct UpgradeBannerSection: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    Text("Calendar Sync")
                        .font(.headline)
                }

                Text("Sync your care tasks, shifts, and appointments with your calendar. Available with Plus or Family plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    // Navigate to upgrade
                } label: {
                    Text("Upgrade to Plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Connected Calendars Section

private struct ConnectedCalendarsSection: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        Section {
            if viewModel.connections.isEmpty {
                ContentUnavailableView {
                    Label("No Calendars Connected", systemImage: "calendar")
                } description: {
                    Text("Connect a calendar to sync your care events.")
                } actions: {
                    Button("Add Calendar") {
                        viewModel.showAddCalendar = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.connections) { connection in
                    CalendarConnectionRow(
                        connection: connection,
                        onSync: {
                            Task {
                                await viewModel.syncConnection(connection)
                            }
                        },
                        onDisconnect: {
                            Task {
                                await viewModel.disconnectCalendar(connection)
                            }
                        }
                    )
                }

                if viewModel.canAddConnection {
                    Button {
                        viewModel.showAddCalendar = true
                    } label: {
                        Label("Add Calendar", systemImage: "plus.circle")
                    }
                }
            }
        } header: {
            Text("Connected Calendars")
        } footer: {
            if viewModel.accessLevel == .singleProvider {
                Text("Connect Google Calendar or Outlook with Family plan.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Calendar Connection Row

private struct CalendarConnectionRow: View {
    let connection: CalendarConnection
    let onSync: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Provider icon
            Image(systemName: connection.provider.icon)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayCalendarName)
                    .font(.body)

                HStack(spacing: 4) {
                    SwiftUI.Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(connection.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastSync = connection.lastSyncAt {
                        Text("• \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Menu {
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                    onSync()
                }

                // Settings handled via the main sync settings section
                // No separate per-connection settings view needed for MVP

                Divider()

                Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                    onDisconnect()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch connection.status {
        case .active: return .green
        case .pending: return .orange
        case .error: return .red
        case .revoked: return .secondary
        }
    }
}

// MARK: - Sync Settings Section

private struct SyncSettingsSection: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        Section("Sync Settings") {
            Toggle("Sync Tasks", isOn: $viewModel.syncTasks)
                .onChange(of: viewModel.syncTasks) { _, _ in
                    saveSettingsDebounced()
                }
            Toggle("Sync Shifts", isOn: $viewModel.syncShifts)
                .onChange(of: viewModel.syncShifts) { _, _ in
                    saveSettingsDebounced()
                }
            Toggle("Sync Appointments", isOn: $viewModel.syncAppointments)
                .onChange(of: viewModel.syncAppointments) { _, _ in
                    saveSettingsDebounced()
                }

            Picker("When Conflicts Occur", selection: $viewModel.conflictStrategy) {
                ForEach(ConflictStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayName)
                        .tag(strategy)
                }
            }
            .onChange(of: viewModel.conflictStrategy) { _, _ in
                saveSettingsDebounced()
            }
        }
    }

    private func saveSettingsDebounced() {
        // Save settings after a brief debounce
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            if let connection = viewModel.connections.first(where: { $0.status == .active }) {
                await viewModel.updateSettings(for: connection)
            }
        }
    }
}

// MARK: - iCal Feed Section

private struct ICalFeedSection: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        Section {
            Button {
                viewModel.showICalFeed = true
            } label: {
                HStack {
                    Label("iCal Feed URL", systemImage: "link")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Subscribe")
        } footer: {
            Text("Generate a URL to subscribe from any calendar app.")
        }
    }
}

// MARK: - Sync Status Section

private struct SyncStatusSection: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        Section("Sync Status") {
            HStack {
                Text("Last Sync")
                Spacer()
                if viewModel.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(viewModel.lastSyncFormatted)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    await viewModel.syncNow()
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing...")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync Now")
                    }
                    Spacer()
                }
            }
            .disabled(viewModel.isSyncing)
        }
    }
}

// MARK: - Conflicts Section

private struct ConflictsSection: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        Section {
            ForEach(viewModel.pendingConflicts) { event in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading) {
                        Text(event.title)
                            .font(.body)
                        Text("Needs resolution")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Resolve") {
                        viewModel.showConflictResolution = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } header: {
            HStack {
                Text("Conflicts")
                Spacer()
                Text("\(viewModel.pendingConflicts.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
            }
        }
    }
}

// MARK: - Calendar Connection Sheet

private struct CalendarConnectionSheet: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Authorization status
                if !viewModel.appleProviderAuthStatus {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.title)
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading) {
                                    Text("Calendar Access Required")
                                        .font(.headline)
                                    Text("CuraKnot needs access to your calendar to sync events.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button("Allow Calendar Access") {
                                Task {
                                    await viewModel.requestCalendarAccess()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Calendar selection
                if viewModel.appleProviderAuthStatus {
                    Section("Select Calendar") {
                        ForEach(viewModel.availableCalendars, id: \.calendarIdentifier) { calendar in
                            Button {
                                viewModel.selectedCalendarId = calendar.calendarIdentifier
                            } label: {
                                HStack {
                                    SwiftUI.Circle()
                                        .fill(Color(cgColor: calendar.cgColor ?? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
                                        .frame(width: 12, height: 12)

                                    Text(calendar.title)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if viewModel.selectedCalendarId == calendar.calendarIdentifier {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }

                    // Create new calendar option
                    Section {
                        Button {
                            // Create new CuraKnot calendar
                        } label: {
                            Label("Create \"CuraKnot\" Calendar", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle("Add Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        Task {
                            await viewModel.connectAppleCalendar()
                        }
                    }
                    .disabled(viewModel.selectedCalendarId == nil)
                }
            }
        }
    }
}

// MARK: - Preview

// Preview wrapper to handle MainActor initialization
private struct CalendarSettingsPreview: View {
    @StateObject private var container = PreviewDependencyContainer()

    var body: some View {
        NavigationStack {
            CalendarSettingsView(
                calendarSyncService: container.calendarSyncService,
                appleProvider: container.appleProvider
            )
            .environmentObject(AppState())
        }
    }
}

@MainActor
private class PreviewDependencyContainer: ObservableObject {
    let databaseManager = DatabaseManager()
    lazy var supabaseClient = SupabaseClient(url: URL(string: "http://localhost")!, anonKey: "")
    lazy var syncCoordinator = SyncCoordinator(databaseManager: databaseManager, supabaseClient: supabaseClient)
    let appleProvider = AppleCalendarProvider()
    lazy var calendarSyncService = CalendarSyncService(
        databaseManager: databaseManager,
        supabaseClient: supabaseClient,
        syncCoordinator: syncCoordinator,
        appleProvider: appleProvider
    )
}

#Preview {
    CalendarSettingsPreview()
}
