import Foundation
import WatchConnectivity
import CryptoKit
import UIKit
import OSLog

// MARK: - Watch Session Manager (iPhone Side)

private let logger = Logger(subsystem: "com.curaknot.app", category: "WatchSessionManager")

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = WatchSessionManager()

    // MARK: - Published Properties

    @Published var isWatchPaired = false
    @Published var isWatchAppInstalled = false
    @Published var isReachable = false
    @Published var pendingVoiceDrafts: [URL] = []

    // MARK: - Private Properties

    private var session: WCSession?
    private let fileManager = FileManager.default

    // Idempotency tracking for task completions (CA2 fix)
    // Uses Array for insertion-order tracking + Set for O(1) lookup = actual LRU behavior
    private var processedCompletionIdsOrder: [String] = []
    private var processedCompletionIdsSet = Set<String>()
    private let maxProcessedIds = 100

    // MARK: - Security (SA2 fix)

    /// Shared secret for subscription token signing
    /// Note: In production, this should be derived from user credentials or stored in Keychain
    private var subscriptionSigningSecret: String {
        // Use a device-specific secret derived from a stable identifier
        // For now, use a hardcoded value that should be replaced with proper key derivation
        "CuraKnot-Watch-Subscription-Secret-\(UIDevice.current.identifierForVendor?.uuidString ?? "default")"
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else {
            logger.warning("WatchConnectivity not supported on this device")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Subscription Status

    /// Send subscription status to Watch via applicationContext (survives app termination)
    /// Includes cryptographically signed token for verification (SA2 security fix)
    func sendSubscriptionStatus(_ plan: String) {
        guard let session = session, session.activationState == .activated else {
            logger.warning("WCSession not activated")
            return
        }

        // Generate signed subscription token (SA2 security fix)
        let signedToken = generateSignedSubscriptionToken(plan: plan)

        // SECURITY: Do NOT send the signing secret over WatchConnectivity.
        // The Watch app should derive the same secret independently using
        // identifierForVendor or a shared Keychain group (App Group).
        let context: [String: Any] = [
            "subscription_plan": plan,
            "subscription_token": signedToken,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            try session.updateApplicationContext(context)
            logger.info("Sent signed subscription status to Watch: \(plan, privacy: .public)")
        } catch {
            logger.error("Failed to update application context: \(error.localizedDescription)")
        }
    }

    /// Generate a cryptographically signed subscription token (SA2 security fix)
    private func generateSignedSubscriptionToken(plan: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let dataToSign = "\(plan)|\(timestamp)"

        let keyData = Data(subscriptionSigningSecret.utf8)
        let messageData = Data(dataToSign.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        let signature = Data(hmac).base64EncodedString()

        return "\(plan)|\(timestamp)|\(signature)"
    }

    // MARK: - Cache Data Sync

    /// Send cache data to Watch for offline access
    func sendCacheData(_ data: WatchCacheData) {
        guard let session = session, session.activationState == .activated else {
            logger.warning("WCSession not activated")
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)

            if session.isReachable {
                // Send immediately if reachable, with fallback to queued delivery
                session.sendMessageData(encoded, replyHandler: nil) { [weak self] error in
                    logger.error("Failed to send cache data: \(error.localizedDescription), queueing for retry")
                    // Queue for delivery via transferUserInfo as fallback
                    self?.session?.transferUserInfo(["cache_data": encoded])
                }
                logger.info("Sent cache data to Watch (immediate)")
            } else {
                // Queue for delivery when Watch becomes available
                session.transferUserInfo(["cache_data": encoded])
                logger.info("Queued cache data for Watch delivery")
            }
        } catch {
            logger.error("Failed to encode cache data: \(error.localizedDescription)")
        }
    }

    /// Request Watch to sync (useful when app becomes active)
    func requestSync() {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "type": "sync_request",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            logger.error("Failed to send sync request: \(error.localizedDescription)")
        }
    }

    // MARK: - Clear Watch Cache (on subscription downgrade)

    func sendClearCacheCommand() {
        guard let session = session, session.activationState == .activated else { return }

        let context: [String: Any] = [
            "subscription_plan": "FREE",
            "clear_cache": true,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            try session.updateApplicationContext(context)
            logger.info("Sent clear cache command to Watch")
        } catch {
            logger.error("Failed to send clear cache command: \(error.localizedDescription)")
        }
    }

    // MARK: - Voice Draft Processing

    private func processVoiceDraft(at url: URL, metadata: [String: Any]?) {
        guard let metadata = metadata,
              let draftMetadata = WatchDraftMetadata(from: metadata) else {
            logger.warning("Invalid voice draft metadata")
            return
        }

        // Move file to documents directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let voiceDraftsDir = documentsPath.appendingPathComponent("WatchVoiceDrafts", isDirectory: true)

        do {
            try fileManager.createDirectory(at: voiceDraftsDir, withIntermediateDirectories: true)

            // Use milliseconds + UUID suffix to avoid collision on rapid recordings (DB1-Bug5)
            let timestamp = Int(draftMetadata.createdAt.timeIntervalSince1970 * 1000)
            let uuid = UUID().uuidString.prefix(8)
            let destinationURL = voiceDraftsDir.appendingPathComponent("draft_\(timestamp)_\(uuid).m4a")

            try fileManager.moveItem(at: url, to: destinationURL)

            Task { @MainActor in
                self.pendingVoiceDrafts.append(destinationURL)
            }

            // Post notification for app to handle
            NotificationCenter.default.post(
                name: .watchVoiceDraftReceived,
                object: nil,
                userInfo: [
                    "url": destinationURL,
                    "metadata": draftMetadata
                ]
            )

            logger.info("Received voice draft from Watch: \(destinationURL.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("Failed to process voice draft: \(error.localizedDescription)")
        }
    }

    // MARK: - Task Completion Handling

    private func handleTaskCompletion(_ data: Data) {
        guard let completion = try? JSONDecoder().decode(WatchTaskCompletion.self, from: data) else {
            logger.error("Failed to decode task completion")
            return
        }

        // Idempotency check to prevent duplicate processing (CA2 fix)
        guard !processedCompletionIdsSet.contains(completion.taskId) else {
            logger.debug("Ignoring duplicate task completion: \(completion.taskId, privacy: .public)")
            return
        }

        // Track processed ID with true LRU eviction (oldest-first via Array order)
        processedCompletionIdsOrder.append(completion.taskId)
        processedCompletionIdsSet.insert(completion.taskId)
        if processedCompletionIdsOrder.count > maxProcessedIds {
            let oldest = processedCompletionIdsOrder.removeFirst()
            processedCompletionIdsSet.remove(oldest)
        }

        // Post notification for app to handle
        NotificationCenter.default.post(
            name: .watchTaskCompleted,
            object: nil,
            userInfo: [
                "taskId": completion.taskId,
                "completedAt": completion.completedAt,
                "completionNote": completion.completionNote as Any
            ]
        )

        logger.info("Received task completion from Watch: \(completion.taskId, privacy: .public)")
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error = error {
                logger.error("WCSession activation failed: \(error.localizedDescription)")
                return
            }

            self.isWatchPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable

            logger.info("WCSession activated: paired=\(session.isPaired), installed=\(session.isWatchAppInstalled)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        logger.debug("WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        logger.debug("WCSession deactivated")
        // Reactivate for switching to new Watch
        Task { @MainActor in
            self.activate()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            logger.debug("Watch reachability changed: \(session.isReachable)")

            if session.isReachable {
                // Good opportunity to sync
                self.requestSync()
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            logger.debug("Watch state changed: paired=\(session.isPaired), installed=\(session.isWatchAppInstalled)")
        }
    }

    // MARK: - Receive File (Voice Drafts)

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // CRITICAL: Copy file synchronously - URL only valid during this callback (CA1 fix)
        let tempDir = FileManager.default.temporaryDirectory
        let tempCopy = tempDir.appendingPathComponent(UUID().uuidString + ".m4a")
        let metadata = file.metadata

        do {
            // Validate source file exists and has content (CA2 fix)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            guard fileSize > 0 else {
                logger.warning("Received empty file: \(file.fileURL.lastPathComponent, privacy: .public)")
                return
            }

            // Copy synchronously before delegate returns
            try FileManager.default.copyItem(at: file.fileURL, to: tempCopy)

            Task { @MainActor in
                self.processVoiceDraft(at: tempCopy, metadata: metadata)
            }
        } catch {
            logger.error("Failed to copy received file: \(error.localizedDescription)")
        }
    }

    // MARK: - Receive Message (Task Completions, etc.)

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard let type = message["type"] as? String else { return }

            switch type {
            case "task_completed":
                if let data = message["data"] as? Data {
                    self.handleTaskCompletion(data)
                }
            case "sync_request":
                // Watch is requesting fresh data
                NotificationCenter.default.post(name: .watchSyncRequested, object: nil)
            default:
                logger.warning("Unknown message type: \(type, privacy: .public)")
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        // Handle raw data messages if needed
        logger.debug("Received message data: \(messageData.count) bytes")
    }

    // MARK: - Receive User Info (Queued data)

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            if let type = userInfo["type"] as? String, type == "task_completed",
               let data = userInfo["data"] as? Data {
                self.handleTaskCompletion(data)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchVoiceDraftReceived = Notification.Name("watchVoiceDraftReceived")
    static let watchTaskCompleted = Notification.Name("watchTaskCompleted")
    static let watchSyncRequested = Notification.Name("watchSyncRequested")
}
