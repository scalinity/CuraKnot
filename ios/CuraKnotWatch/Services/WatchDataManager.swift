import Foundation
import WidgetKit
import CryptoKit
import OSLog

// MARK: - Watch Data Manager

private let logger = Logger(subsystem: "com.curaknot.app.watchos", category: "WatchDataManager")

@MainActor
final class WatchDataManager: ObservableObject {
    // MARK: - Singleton

    static let shared = WatchDataManager()

    // MARK: - Published Properties

    @Published var emergencyCard: WatchEmergencyCard?
    @Published var todayTasks: [WatchTask] = []
    @Published var recentHandoffs: [WatchHandoff] = []
    @Published var patients: [WatchPatient] = []
    @Published var currentPatientId: String?

    // MARK: - Cached Computed Properties (CA3 performance fix)

    @Published private(set) var nextTask: WatchTask?

    // MARK: - Cache Configuration

    private static let maxCacheSizeBytes = 1_000_000  // 1MB max for Watch storage
    private static let emergencyCardPriority = 1      // Never evict
    private static let todayTasksPriority = 2
    private static let recentHandoffsPriority = 3     // Evict first if needed

    // MARK: - UserDefaults Keys

    private let subscriptionKey = "subscription_status"
    private let emergencyCardKey = "cached_emergency_card"
    private let todayTasksKey = "cached_today_tasks"
    private let recentHandoffsKey = "cached_recent_handoffs"
    private let patientsKey = "cached_patients"
    private let currentPatientKey = "current_patient_id"
    private let lastSyncKey = "last_sync_timestamp"
    private let cacheSizeKey = "current_cache_size_bytes"

    // Incremental cache size tracking (CA3 fix - avoid 4 reads per write)
    private var cacheSizes: [String: Int] = [:]

    // App Group for complication data (DB1-Bug2 fix)
    private let complicationSuite = UserDefaults(suiteName: "group.com.curaknot.app")

    // Cached formatter to avoid repeated allocation (CA3 fix)
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Staleness

    var dataAge: TimeInterval {
        guard let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date else {
            return .infinity
        }
        return Date().timeIntervalSince(lastSync)
    }

    var isStale: Bool {
        dataAge > 3600  // 1 hour
    }

    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    var formattedDataAge: String {
        let age = dataAge
        if age == .infinity {
            return "Never synced"
        }
        // Use cached formatter (CA3 performance fix)
        return Self.relativeDateFormatter.localizedString(for: Date().addingTimeInterval(-age), relativeTo: Date())
    }

    // MARK: - Accessors

    // nextTask is now a @Published property updated via updateComputedProperties()

    var lastHandoff: WatchHandoff? {
        recentHandoffs.first
    }

    // MARK: - Update Computed Properties (CA3 performance fix)

    private func updateComputedProperties() {
        // Pre-compute nextTask once on data update instead of O(n log n) on every access
        nextTask = todayTasks
            .filter { $0.isOpen }
            .min { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    var cachedSubscriptionStatus: String {
        // Use verified subscription with TTL enforcement (SA2 security fix)
        return WatchSecurityManager.shared.getVerifiedSubscriptionStatus()
    }

    var hasWatchAccess: Bool {
        // Use verified subscription check with TTL enforcement (SA2 security fix)
        return WatchSecurityManager.shared.hasVerifiedWatchAccess
    }

    /// Update subscription status with signed token (called from WatchConnectivityHandler)
    /// For backwards compatibility, also accepts plain status string
    func updateSubscriptionStatus(_ status: String, signedToken: String? = nil, sharedSecret: String? = nil) {
        if let token = signedToken, let secret = sharedSecret {
            // Verify and store signed token (SA2 security fix)
            if WatchSecurityManager.shared.verifyAndStoreSubscriptionToken(token, sharedSecret: secret) {
                logger.info("Verified and stored signed subscription token")
            } else {
                logger.warning("Failed to verify subscription token, falling back to plain status")
                // Fallback to legacy storage
                UserDefaults.standard.set(status, forKey: subscriptionKey)
            }
        } else {
            // Legacy: store plain status (for backwards compatibility during migration)
            UserDefaults.standard.set(status, forKey: subscriptionKey)
        }
    }

    var currentPatient: WatchPatient? {
        guard let patientId = currentPatientId else { return patients.first }
        return patients.first { $0.id == patientId } ?? patients.first
    }

    // MARK: - Initialization

    private init() {
        initializeCacheSizes()  // Initialize incremental tracking (CA3 fix)
        loadFromCache()
        enforceDataRetention()  // SA3 security fix
    }

    // MARK: - Data Retention (SA3 Security Fix)

    /// Enforce data retention policies
    private func enforceDataRetention() {
        WatchSecurityManager.shared.enforceDataRetention()
    }

    // MARK: - Cache Operations

    func updateFromSync(_ data: WatchCacheData) {
        // Store with priority-based eviction
        cacheEmergencyCard(data.emergencyCard)
        cacheTodayTasks(data.todayTasks)
        cacheRecentHandoffs(data.recentHandoffs)
        cachePatients(data.patients)

        // Update state
        currentPatientId = data.currentPatientId
        UserDefaults.standard.set(data.currentPatientId, forKey: currentPatientKey)
        UserDefaults.standard.set(Date(), forKey: lastSyncKey)
        UserDefaults.standard.set(data.subscriptionPlan, forKey: subscriptionKey)

        // Refresh published properties
        loadFromCache()

        // Update complications with new data (DB1-Bug2 fix)
        updateComplications()
    }

    func loadFromCache() {
        emergencyCard = loadCached(forKey: emergencyCardKey)
        todayTasks = loadCached(forKey: todayTasksKey) ?? []
        recentHandoffs = loadCached(forKey: recentHandoffsKey) ?? []
        patients = loadCached(forKey: patientsKey) ?? []
        currentPatientId = UserDefaults.standard.string(forKey: currentPatientKey)

        // Update computed properties (CA3 performance fix)
        updateComputedProperties()
    }

    // MARK: - Private Cache Methods

    private func cacheEmergencyCard(_ card: WatchEmergencyCard?) {
        guard let card = card else {
            UserDefaults.standard.removeObject(forKey: emergencyCardKey)
            return
        }
        saveToCache(card, forKey: emergencyCardKey)
    }

    private func cacheTodayTasks(_ tasks: [WatchTask]) {
        if tasks.isEmpty {
            UserDefaults.standard.removeObject(forKey: todayTasksKey)
        } else {
            saveToCache(tasks, forKey: todayTasksKey)
        }
    }

    private func cacheRecentHandoffs(_ handoffs: [WatchHandoff]) {
        if handoffs.isEmpty {
            UserDefaults.standard.removeObject(forKey: recentHandoffsKey)
        } else {
            // Limit to 5 most recent
            let limited = Array(handoffs.prefix(5))
            saveToCache(limited, forKey: recentHandoffsKey)
        }
    }

    private func cachePatients(_ patientList: [WatchPatient]) {
        if patientList.isEmpty {
            UserDefaults.standard.removeObject(forKey: patientsKey)
        } else {
            saveToCache(patientList, forKey: patientsKey)
        }
    }

    private func saveToCache<T: Encodable>(_ value: T, forKey key: String, encrypt: Bool = true) {
        guard let jsonData = try? JSONEncoder().encode(value) else { return }

        // Encrypt PHI data at rest (SA3 security fix)
        let dataToStore: Data
        if encrypt, let encryptedData = WatchSecurityManager.shared.encrypt(jsonData) {
            dataToStore = encryptedData
        } else {
            // Fallback to unencrypted if encryption fails (log warning)
            logger.warning("Storing unencrypted data for key: \(key, privacy: .public)")
            dataToStore = jsonData
        }

        // Incremental cache size tracking (CA3 fix - avoid 4 reads per write)
        let oldSize = cacheSizes[key] ?? 0
        let newTotal = currentCacheSize - oldSize + dataToStore.count

        // If over limit, evict lower priority items
        if newTotal > Self.maxCacheSizeBytes {
            evictLowPriorityItems(neededBytes: dataToStore.count)
        }

        UserDefaults.standard.set(dataToStore, forKey: key)
        cacheSizes[key] = dataToStore.count
        currentCacheSize = cacheSizes.values.reduce(0, +)
    }

    private func loadCached<T: Decodable>(forKey key: String, encrypted: Bool = true) -> T? {
        guard let storedData = UserDefaults.standard.data(forKey: key) else { return nil }

        // Decrypt PHI data (SA3 security fix)
        let jsonData: Data
        if encrypted, let decryptedData = WatchSecurityManager.shared.decrypt(storedData) {
            jsonData = decryptedData
        } else {
            // Fallback: try to decode directly (for unencrypted legacy data)
            jsonData = storedData
        }

        return try? JSONDecoder().decode(T.self, from: jsonData)
    }

    // MARK: - Cache Size Management

    private var currentCacheSize: Int {
        get { UserDefaults.standard.integer(forKey: cacheSizeKey) }
        set { UserDefaults.standard.set(newValue, forKey: cacheSizeKey) }
    }

    private func evictLowPriorityItems(neededBytes: Int) {
        var freedBytes = 0
        // Eviction order: handoffs first, then tasks. Never evict emergency card.
        let evictionOrder = [recentHandoffsKey, todayTasksKey]

        for key in evictionOrder {
            guard freedBytes < neededBytes else { break }

            // Use incremental tracking instead of re-reading (CA3 fix)
            if let existingSize = cacheSizes[key], existingSize > 0 {
                freedBytes += existingSize
                UserDefaults.standard.removeObject(forKey: key)
                cacheSizes[key] = 0
                logger.info("Watch cache: Evicted \(key, privacy: .public) to free \(existingSize) bytes")
            }
        }
    }

    /// Initialize cache sizes from UserDefaults on first load
    private func initializeCacheSizes() {
        for key in [emergencyCardKey, todayTasksKey, recentHandoffsKey, patientsKey] {
            if let data = UserDefaults.standard.data(forKey: key) {
                cacheSizes[key] = data.count
            }
        }
        currentCacheSize = cacheSizes.values.reduce(0, +)
    }

    // MARK: - Clear Cache

    func clearNonEssentialCache() {
        UserDefaults.standard.removeObject(forKey: todayTasksKey)
        UserDefaults.standard.removeObject(forKey: recentHandoffsKey)
        todayTasks = []
        recentHandoffs = []
        recalculateCacheSize()
    }

    func clearAllCache() {
        UserDefaults.standard.removeObject(forKey: emergencyCardKey)
        UserDefaults.standard.removeObject(forKey: todayTasksKey)
        UserDefaults.standard.removeObject(forKey: recentHandoffsKey)
        UserDefaults.standard.removeObject(forKey: patientsKey)
        UserDefaults.standard.removeObject(forKey: currentPatientKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)

        emergencyCard = nil
        todayTasks = []
        recentHandoffs = []
        patients = []
        currentPatientId = nil

        recalculateCacheSize()
    }

    // MARK: - Voice Recordings

    /// Clear old transferred recordings (excludes active/recent recordings - CA1 fix)
    func clearTransferredRecordings(excludeURL activeURL: URL? = nil) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        // Only delete files older than 5 minutes (likely already transferred)
        let fiveMinutesAgo = Date().addingTimeInterval(-300)

        do {
            let recordings = try fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.creationDateKey]
            ).filter { $0.pathExtension == "m4a" && $0 != activeURL }

            var clearedCount = 0
            for recording in recordings {
                let values = try recording.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = values.creationDate, creationDate < fiveMinutesAgo {
                    try fileManager.removeItem(at: recording)
                    clearedCount += 1
                }
            }
            if clearedCount > 0 {
                logger.info("Cleared \(clearedCount) old transferred recordings")
            }
        } catch {
            logger.error("Failed to clear recordings: \(error.localizedDescription)")
        }
    }

    // MARK: - Task Operations

    func markTaskCompleted(_ taskId: String, note: String? = nil) {
        // Update local state
        if let index = todayTasks.firstIndex(where: { $0.id == taskId }) {
            todayTasks.remove(at: index)
            // Re-cache the updated list
            cacheTodayTasks(todayTasks)
            // Update computed properties and complications
            updateComputedProperties()
            updateComplications()
        }

        // Send to iPhone
        let completion = WatchTaskCompletion(
            taskId: taskId,
            completedAt: Date(),
            completionNote: note
        )
        WatchConnectivityHandler.shared.sendTaskCompletion(completion)
    }

    // MARK: - Patient Selection

    func selectPatient(_ patientId: String) {
        currentPatientId = patientId
        UserDefaults.standard.set(patientId, forKey: currentPatientKey)
    }

    // MARK: - Complication Data (DB1-Bug2 fix)

    /// Update complication data in shared App Group UserDefaults
    func updateComplications() {
        guard let suite = complicationSuite else { return }

        // Update next task complication
        if let task = nextTask {
            let complicationTask = ComplicationTask(title: task.title, dueAt: task.dueAt)
            if let data = try? JSONEncoder().encode(complicationTask) {
                suite.set(data, forKey: "complication_next_task")
            }
        } else {
            suite.removeObject(forKey: "complication_next_task")
        }

        // Update last handoff complication
        if let handoff = lastHandoff {
            let complicationHandoff = ComplicationHandoff(
                title: handoff.title,
                summary: handoff.summary,
                publishedAt: handoff.publishedAt,
                createdByName: handoff.createdByName
            )
            if let data = try? JSONEncoder().encode(complicationHandoff) {
                suite.set(data, forKey: "complication_last_handoff")
            }
        } else {
            suite.removeObject(forKey: "complication_last_handoff")
        }

        // Update emergency card complication
        if let card = emergencyCard {
            let complicationEmergency = ComplicationEmergency(
                patientInitials: card.displayInitials,
                hasCard: true
            )
            if let data = try? JSONEncoder().encode(complicationEmergency) {
                suite.set(data, forKey: "complication_emergency")
            }
        } else {
            suite.removeObject(forKey: "complication_emergency")
        }

        // Request complication refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Complication Data Models (for encoding to shared UserDefaults)

struct ComplicationTask: Codable {
    let title: String
    let dueAt: Date?
}

struct ComplicationHandoff: Codable {
    let title: String
    let summary: String?
    let publishedAt: Date?
    let createdByName: String
}

struct ComplicationEmergency: Codable {
    let patientInitials: String
    let hasCard: Bool
}
