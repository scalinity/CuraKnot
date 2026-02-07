import SwiftUI
import Network

// MARK: - Network Monitor

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    @Published var connectionType: ConnectionType = .unknown
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = self?.getConnectionType(path) ?? .unknown
            }
        }
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
    
    private func getConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        }
        return .unknown
    }
}

// MARK: - Offline Banner View

struct OfflineBannerView: View {
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var syncStatus: SyncStatusObserver
    
    var body: some View {
        if !networkMonitor.isConnected {
            HStack {
                Image(systemName: "wifi.slash")
                Text("You're offline")
                Spacer()
                if syncStatus.pendingChanges > 0 {
                    Text("\(syncStatus.pendingChanges) pending")
                        .font(.caption)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange)
        }
    }
}

// MARK: - Sync Status Indicator

struct SyncStatusIndicator: View {
    @ObservedObject var syncStatus: SyncStatusObserver
    
    var body: some View {
        HStack(spacing: 4) {
            statusIcon
            
            if syncStatus.status == .syncing {
                Text("Syncing...")
                    .font(.caption)
            }
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch syncStatus.status {
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
        case .conflict:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.gray)
        }
    }
}

// MARK: - Staleness Indicator

struct StalenessIndicator: View {
    let lastSyncTime: Date?
    
    var staleness: Staleness {
        guard let lastSync = lastSyncTime else { return .unknown }
        let interval = Date().timeIntervalSince(lastSync)
        
        if interval < 60 {
            return .fresh
        } else if interval < 300 {
            return .recent
        } else if interval < 3600 {
            return .stale
        } else {
            return .veryStale
        }
    }
    
    enum Staleness {
        case fresh      // < 1 minute
        case recent     // 1-5 minutes
        case stale      // 5-60 minutes
        case veryStale  // > 1 hour
        case unknown
        
        var color: Color {
            switch self {
            case .fresh: return .green
            case .recent: return .green.opacity(0.7)
            case .stale: return .orange
            case .veryStale: return .red
            case .unknown: return .gray
            }
        }
        
        var icon: String {
            switch self {
            case .fresh, .recent: return "checkmark.circle"
            case .stale: return "clock"
            case .veryStale: return "exclamationmark.clock"
            case .unknown: return "questionmark.circle"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: staleness.icon)
                .foregroundStyle(staleness.color)
            
            if let lastSync = lastSyncTime {
                Text("Updated \(lastSync, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Conflict Resolution View

struct ConflictResolutionView: View {
    let conflicts: [String]
    let onResolve: (String, ConflictChoice) -> Void
    
    enum ConflictChoice {
        case keepLocal
        case useServer
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(conflicts, id: \.self) { conflictId in
                    ConflictRow(
                        conflictId: conflictId,
                        onResolve: { choice in
                            onResolve(conflictId, choice)
                        }
                    )
                }
            }
            .navigationTitle("Sync Conflicts")
        }
    }
}

struct ConflictRow: View {
    let conflictId: String
    let onResolve: (ConflictResolutionView.ConflictChoice) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conflict: \(conflictId)")
                .font(.headline)
            
            Text("This item was modified both locally and on the server.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Button("Keep Mine") {
                    onResolve(.keepLocal)
                }
                .buttonStyle(.bordered)
                
                Button("Use Server") {
                    onResolve(.useServer)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    VStack {
        OfflineBannerView(
            networkMonitor: NetworkMonitor(),
            syncStatus: SyncStatusObserver()
        )
        
        StalenessIndicator(lastSyncTime: Date().addingTimeInterval(-120))
    }
}
