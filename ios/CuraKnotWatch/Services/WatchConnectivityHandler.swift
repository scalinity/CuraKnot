import Foundation
import WatchConnectivity
import OSLog

// MARK: - Watch Connectivity Handler (Watch Side)

private let logger = Logger(subsystem: "com.curaknot.app.watchos", category: "WatchConnectivityHandler")

@MainActor
final class WatchConnectivityHandler: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = WatchConnectivityHandler()

    // MARK: - Published Properties

    @Published var subscriptionPlan: String = "FREE"
    @Published var isPhoneReachable = false
    @Published var lastSyncDate: Date?

    // MARK: - Private Properties

    private var session: WCSession?
    private let pendingCompletionsKey = "pending_task_completions"

    // MARK: - Retry Queue

    private let maxPendingCompletions = 50  // Prevent unbounded queue growth (SA1 fix)

    // In-memory cache to avoid repeated JSON decode/encode (CA3 fix)
    private var _pendingCompletionsCache: [WatchTaskCompletion]?

    private var pendingCompletions: [WatchTaskCompletion] {
        get {
            if let cached = _pendingCompletionsCache {
                return cached
            }
            guard let data = UserDefaults.standard.data(forKey: pendingCompletionsKey),
                  let completions = try? JSONDecoder().decode([WatchTaskCompletion].self, from: data) else {
                _pendingCompletionsCache = []
                return []
            }
            _pendingCompletionsCache = completions
            return completions
        }
        set {
            _pendingCompletionsCache = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: pendingCompletionsKey)
            }
        }
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else {
            logger.warning("WatchConnectivity not supported")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Voice Recording Transfer

    /// Transfer voice recording to iPhone
    func transferVoiceRecording(url: URL, metadata: WatchDraftMetadata) {
        guard let session = session, session.activationState == .activated else {
            logger.warning("WCSession not activated")
            return
        }

        session.transferFile(url, metadata: metadata.dictionary)
        logger.info("Queued voice recording for transfer: \(url.lastPathComponent, privacy: .public)")
    }

    // MARK: - Task Completion

    /// Send task completion to iPhone
    func sendTaskCompletion(_ completion: WatchTaskCompletion) {
        guard let session = session, session.activationState == .activated else {
            logger.warning("WCSession not activated, queuing completion")
            queueCompletionForRetry(completion)
            return
        }

        do {
            let data = try JSONEncoder().encode(completion)

            if session.isReachable {
                let message: [String: Any] = [
                    "type": "task_completed",
                    "data": data
                ]
                session.sendMessage(message, replyHandler: nil) { [weak self] error in
                    logger.error("Failed to send task completion: \(error.localizedDescription)")
                    // Queue for retry on failure
                    self?.queueCompletionForRetry(completion)
                }
            } else {
                // Queue for delivery via transferUserInfo
                session.transferUserInfo([
                    "type": "task_completed",
                    "data": data
                ])
            }

            logger.info("Sent task completion: \(completion.taskId, privacy: .public)")
        } catch {
            logger.error("Failed to encode task completion: \(error.localizedDescription)")
            queueCompletionForRetry(completion)
        }
    }

    /// Queue a failed completion for retry
    private func queueCompletionForRetry(_ completion: WatchTaskCompletion) {
        var pending = pendingCompletions
        // Avoid duplicates
        if !pending.contains(where: { $0.taskId == completion.taskId }) {
            // Enforce maximum queue size to prevent unbounded growth (SA1 fix)
            if pending.count >= maxPendingCompletions {
                pending.removeFirst()
                logger.warning("Pending completions queue at limit, dropped oldest item")
            }
            pending.append(completion)
            pendingCompletions = pending
            logger.debug("Queued task completion for retry: \(completion.taskId, privacy: .public)")
        }
    }

    /// Retry sending pending task completions
    func retryPendingCompletions() {
        let pending = pendingCompletions
        guard !pending.isEmpty else { return }

        logger.info("Retrying \(pending.count) pending task completions")

        // Clear the queue first to avoid duplicates
        pendingCompletions = []

        for completion in pending {
            sendTaskCompletion(completion)
        }
    }

    // MARK: - Sync Request

    /// Request sync from iPhone
    func requestSync() {
        guard let session = session, session.isReachable else {
            logger.debug("iPhone not reachable for sync request")
            return
        }

        let message: [String: Any] = [
            "type": "sync_request",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            logger.error("Failed to send sync request: \(error.localizedDescription)")
        }
    }

    // MARK: - Subscription Check
    // Note: Use WatchDataManager.shared.hasWatchAccess as the single source of truth

    var hasWatchAccess: Bool {
        WatchDataManager.shared.hasWatchAccess
    }

    // MARK: - Cache Subscription Status

    /// Cache subscription status with optional signed token verification (SA2 security fix)
    func cacheSubscriptionStatus(_ status: String, signedToken: String? = nil, sharedSecret: String? = nil) {
        // Delegate to WatchDataManager as single source of truth
        WatchDataManager.shared.updateSubscriptionStatus(status, signedToken: signedToken, sharedSecret: sharedSecret)
        subscriptionPlan = WatchDataManager.shared.cachedSubscriptionStatus
    }

    func loadCachedSubscriptionStatus() {
        subscriptionPlan = WatchDataManager.shared.cachedSubscriptionStatus
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityHandler: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            logger.error("WCSession activation failed: \(error.localizedDescription)")
            return
        }

        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            self.loadCachedSubscriptionStatus()
        }

        logger.info("WCSession activated on Watch")
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable

            if session.isReachable {
                // Request sync when phone becomes reachable
                self.requestSync()
                // Retry any pending task completions
                self.retryPendingCompletions()
            }
        }
    }

    // MARK: - Receive Application Context

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            // Defensive validation of context data
            guard !applicationContext.isEmpty else {
                logger.debug("Received empty application context, ignoring")
                return
            }

            // Handle subscription status with signed token verification (SA2 security fix)
            if let plan = applicationContext["subscription_plan"] as? String {
                // Validate plan is a known value
                let validPlans = ["FREE", "PLUS", "FAMILY"]
                guard validPlans.contains(plan) else {
                    logger.warning("Received unknown subscription plan '\(plan, privacy: .public)', defaulting to FREE")
                    self.cacheSubscriptionStatus("FREE", signedToken: nil, sharedSecret: nil)
                    return
                }

                // Try to verify signed token (SA2 security fix)
                if let signedToken = applicationContext["subscription_token"] as? String,
                   let sharedSecret = applicationContext["signing_secret"] as? String {
                    self.cacheSubscriptionStatus(plan, signedToken: signedToken, sharedSecret: sharedSecret)
                    logger.info("Received and verified signed subscription status: \(plan, privacy: .public)")
                } else {
                    // Fallback for legacy (unsigned) subscription updates
                    self.cacheSubscriptionStatus(plan, signedToken: nil, sharedSecret: nil)
                    logger.info("Received unsigned subscription status (legacy): \(plan, privacy: .public)")
                }
            }

            // Handle clear cache command
            if let clearCache = applicationContext["clear_cache"] as? Bool, clearCache {
                WatchDataManager.shared.clearNonEssentialCache()
                logger.info("Cleared Watch cache on subscription downgrade")
            }
        }
    }

    // MARK: - Receive Message Data (Cache Updates)

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        // Defensive check for empty data
        guard !messageData.isEmpty else {
            logger.debug("Received empty message data, ignoring")
            return
        }

        do {
            let cacheData = try JSONDecoder().decode(WatchCacheData.self, from: messageData)

            Task { @MainActor in
                WatchDataManager.shared.updateFromSync(cacheData)
                self.subscriptionPlan = cacheData.subscriptionPlan
                self.lastSyncDate = Date()
                logger.info("Received cache data from iPhone (\(messageData.count) bytes)")
            }
        } catch {
            logger.error("Failed to decode cache data: \(error.localizedDescription)")
        }
    }

    // MARK: - Receive User Info (Queued cache updates)

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // Defensive check for empty user info
        guard !userInfo.isEmpty else {
            logger.debug("Received empty user info, ignoring")
            return
        }

        if let cacheData = userInfo["cache_data"] as? Data, !cacheData.isEmpty {
            do {
                let data = try JSONDecoder().decode(WatchCacheData.self, from: cacheData)

                Task { @MainActor in
                    WatchDataManager.shared.updateFromSync(data)
                    self.subscriptionPlan = data.subscriptionPlan
                    self.lastSyncDate = Date()
                    logger.info("Received queued cache data from iPhone (\(cacheData.count) bytes)")
                }
            } catch {
                logger.error("Failed to decode queued cache data: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - File Transfer Complete

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            logger.error("File transfer failed: \(error.localizedDescription)")
        } else {
            // Delete local file after successful transfer
            let url = fileTransfer.file.fileURL
            try? FileManager.default.removeItem(at: url)
            logger.info("File transfer complete, deleted local file")
        }
    }
}
