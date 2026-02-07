import Foundation

// MARK: - Conflict Resolution

enum ConflictResolutionStrategy {
    case serverWins      // Server version always wins
    case clientWins      // Local version always wins
    case newerWins       // Newer timestamp wins
    case merge           // Attempt to merge changes
    case askUser         // Present conflict to user
}

struct SyncConflict<T: Identifiable> {
    let localVersion: T
    let serverVersion: T
    let conflictType: ConflictType
    
    enum ConflictType {
        case update        // Both updated the same record
        case deleteUpdate  // One deleted, one updated
        case create        // Rare: both created same ID
    }
}

struct ConflictResolution<T> {
    let resolvedValue: T
    let strategy: ConflictResolutionStrategy
}

// MARK: - Conflict Resolver

actor ConflictResolver {
    // MARK: - Properties
    
    private let defaultStrategy: ConflictResolutionStrategy
    private var pendingConflicts: [String: Any] = [:]
    
    // MARK: - Initialization
    
    init(defaultStrategy: ConflictResolutionStrategy = .serverWins) {
        self.defaultStrategy = defaultStrategy
    }
    
    // MARK: - Resolution Methods
    
    func resolve<T: SyncableRecord>(
        conflict: SyncConflict<T>,
        strategy: ConflictResolutionStrategy? = nil
    ) -> ConflictResolution<T> {
        let effectiveStrategy = strategy ?? entityStrategy(for: T.self)
        
        switch effectiveStrategy {
        case .serverWins:
            return ConflictResolution(
                resolvedValue: conflict.serverVersion,
                strategy: .serverWins
            )
            
        case .clientWins:
            return ConflictResolution(
                resolvedValue: conflict.localVersion,
                strategy: .clientWins
            )
            
        case .newerWins:
            let localUpdated = (conflict.localVersion as? Timestamped)?.updatedAt ?? Date.distantPast
            let serverUpdated = (conflict.serverVersion as? Timestamped)?.updatedAt ?? Date.distantPast
            
            let winner = localUpdated > serverUpdated ? conflict.localVersion : conflict.serverVersion
            return ConflictResolution(
                resolvedValue: winner,
                strategy: .newerWins
            )
            
        case .merge:
            if let merged = merge(local: conflict.localVersion, server: conflict.serverVersion) {
                return ConflictResolution(resolvedValue: merged, strategy: .merge)
            }
            // Fall back to server wins if merge fails
            return ConflictResolution(resolvedValue: conflict.serverVersion, strategy: .serverWins)
            
        case .askUser:
            // Store for later user resolution
            pendingConflicts[String(describing: conflict.localVersion.id)] = conflict
            // Default to server wins until user resolves
            return ConflictResolution(resolvedValue: conflict.serverVersion, strategy: .askUser)
        }
    }
    
    // MARK: - Entity-Specific Strategies
    
    private func entityStrategy<T>(for type: T.Type) -> ConflictResolutionStrategy {
        // Different entities may have different default strategies
        switch String(describing: type) {
        case "Handoff":
            // Handoffs that are published should use server
            // Drafts should preserve local
            return .serverWins
            
        case "CareTask":
            // Tasks should generally use server for completion status
            return .serverWins
            
        case "BinderItem":
            // Binder items: newer wins to preserve latest edits
            return .newerWins
            
        default:
            return defaultStrategy
        }
    }
    
    // MARK: - Merge Logic
    
    private func merge<T: SyncableRecord>(local: T, server: T) -> T? {
        // Type-specific merge logic would go here
        // For now, we don't support merging
        return nil
    }
    
    // MARK: - Pending Conflicts
    
    func getPendingConflicts() -> [String] {
        Array(pendingConflicts.keys)
    }
    
    func resolveManually<T>(conflictId: String, resolution: T) {
        pendingConflicts.removeValue(forKey: conflictId)
    }
    
    func getConflict<T>(id: String) -> SyncConflict<T>? {
        pendingConflicts[id] as? SyncConflict<T>
    }
}

// MARK: - Protocols

protocol SyncableRecord: Identifiable, Codable {
    var id: String { get }
}

protocol Timestamped {
    var createdAt: Date { get }
    var updatedAt: Date { get }
}

// MARK: - Version Tracking

struct EntityVersion: Codable {
    let entityType: String
    let entityId: String
    let version: Int
    let serverUpdatedAt: Date
    let localUpdatedAt: Date
}

actor VersionTracker {
    private var versions: [String: EntityVersion] = [:]
    
    func recordVersion(
        entityType: String,
        entityId: String,
        version: Int,
        serverUpdatedAt: Date
    ) {
        let key = "\(entityType):\(entityId)"
        versions[key] = EntityVersion(
            entityType: entityType,
            entityId: entityId,
            version: version,
            serverUpdatedAt: serverUpdatedAt,
            localUpdatedAt: Date()
        )
    }
    
    func getVersion(entityType: String, entityId: String) -> EntityVersion? {
        let key = "\(entityType):\(entityId)"
        return versions[key]
    }
    
    func hasConflict(
        entityType: String,
        entityId: String,
        serverVersion: Int
    ) -> Bool {
        guard let tracked = getVersion(entityType: entityType, entityId: entityId) else {
            return false
        }
        return tracked.version != serverVersion
    }
}

// MARK: - Sync Status

enum SyncStatus: String {
    case idle
    case syncing
    case conflict
    case error
    case offline
}

@MainActor
final class SyncStatusObserver: ObservableObject {
    @Published var status: SyncStatus = .idle
    @Published var lastSyncTime: Date?
    @Published var pendingChanges: Int = 0
    @Published var conflictCount: Int = 0
    @Published var isOnline: Bool = true
    
    func update(
        status: SyncStatus,
        pendingChanges: Int = 0,
        conflictCount: Int = 0
    ) {
        self.status = status
        self.pendingChanges = pendingChanges
        self.conflictCount = conflictCount
        
        if status == .idle {
            lastSyncTime = Date()
        }
    }
}
