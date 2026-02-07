import Foundation
import CryptoKit
import OSLog
import Security

// MARK: - Watch Security Manager (SA2 & SA3 Security Fixes)

private let logger = Logger(subsystem: "com.curaknot.app.watchos", category: "WatchSecurityManager")

// MARK: - Keychain Helper

private enum KeychainHelper {
    private static let service = "com.curaknot.app.watchos"

    static func save(key: String, data: Data) -> Bool {
        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

/// Handles PHI encryption at rest and subscription token verification
@MainActor
final class WatchSecurityManager {
    // MARK: - Singleton

    static let shared = WatchSecurityManager()

    // MARK: - Configuration

    /// Subscription token TTL (24 hours) - after this, treat as FREE until re-verified
    private static let subscriptionTTL: TimeInterval = 24 * 60 * 60

    /// Data retention period (30 days) - clear data older than this
    private static let dataRetentionPeriod: TimeInterval = 30 * 24 * 60 * 60

    // MARK: - Keys

    private let encryptionKeyKey = "watch_encryption_key"
    private let subscriptionTokenKey = "subscription_token"
    private let subscriptionTimestampKey = "subscription_timestamp"
    private let subscriptionSignatureKey = "subscription_signature"

    // MARK: - Cached Key

    private var _encryptionKey: SymmetricKey?

    // MARK: - Initialization

    private init() {
        // Generate or retrieve encryption key on init
        _ = getOrCreateEncryptionKey()
    }

    // MARK: - Encryption Key Management

    /// Get or create the device-local encryption key stored in Keychain
    /// Uses Keychain for secure storage (SA3 security fix - migrated from UserDefaults)
    private func getOrCreateEncryptionKey() -> SymmetricKey {
        if let cached = _encryptionKey {
            return cached
        }

        // Try to load from Keychain first
        if let keyData = KeychainHelper.load(key: encryptionKeyKey) {
            let key = SymmetricKey(data: keyData)
            _encryptionKey = key
            return key
        }

        // Migration: Check for legacy key in UserDefaults and migrate to Keychain
        if let legacyKeyData = UserDefaults.standard.data(forKey: encryptionKeyKey) {
            let key = SymmetricKey(data: legacyKeyData)
            // Migrate to Keychain
            if KeychainHelper.save(key: encryptionKeyKey, data: legacyKeyData) {
                // Remove from UserDefaults after successful migration
                UserDefaults.standard.removeObject(forKey: encryptionKeyKey)
                logger.info("Migrated encryption key from UserDefaults to Keychain")
            }
            _encryptionKey = key
            return key
        }

        // Generate new key and store in Keychain
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        if !KeychainHelper.save(key: encryptionKeyKey, data: keyData) {
            logger.error("Failed to save encryption key to Keychain")
        }
        _encryptionKey = key
        return key
    }

    // MARK: - PHI Encryption (SA3)

    /// Encrypt sensitive data before storing
    func encrypt(_ data: Data) -> Data? {
        let key = getOrCreateEncryptionKey()

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            logger.error("Encryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Decrypt sensitive data when reading
    func decrypt(_ encryptedData: Data) -> Data? {
        let key = getOrCreateEncryptionKey()

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        } catch {
            logger.error("Decryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Encrypt and encode a Codable object
    func encryptObject<T: Encodable>(_ object: T) -> Data? {
        guard let jsonData = try? JSONEncoder().encode(object) else {
            return nil
        }
        return encrypt(jsonData)
    }

    /// Decrypt and decode a Codable object
    func decryptObject<T: Decodable>(_ type: T.Type, from encryptedData: Data) -> T? {
        guard let decryptedData = decrypt(encryptedData) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: decryptedData)
    }

    // MARK: - Subscription Token Verification (SA2)

    /// Verify and store a signed subscription token from iPhone
    /// Token format: plan|timestamp|signature
    func verifyAndStoreSubscriptionToken(_ token: String, sharedSecret: String) -> Bool {
        let components = token.split(separator: "|")
        guard components.count == 3,
              let timestamp = Double(components[1]) else {
            logger.warning("Invalid subscription token format")
            return false
        }

        let plan = String(components[0])
        let signature = String(components[2])

        // Verify signature
        let dataToSign = "\(plan)|\(Int(timestamp))"
        let expectedSignature = computeHMAC(data: dataToSign, key: sharedSecret)

        guard signature == expectedSignature else {
            logger.warning("Invalid subscription token signature")
            return false
        }

        // Verify timestamp is recent (within 24 hours in past, 5 minutes in future)
        let tokenDate = Date(timeIntervalSince1970: timestamp)
        let now = Date()
        let maxAge: TimeInterval = 24 * 60 * 60  // 24 hours
        let maxFuture: TimeInterval = 5 * 60     // 5 minutes

        guard now.timeIntervalSince(tokenDate) < maxAge,
              tokenDate.timeIntervalSince(now) < maxFuture else {
            logger.warning("Subscription token timestamp out of range")
            return false
        }

        // Store verified subscription
        UserDefaults.standard.set(plan, forKey: subscriptionTokenKey)
        UserDefaults.standard.set(timestamp, forKey: subscriptionTimestampKey)
        UserDefaults.standard.set(signature, forKey: subscriptionSignatureKey)

        return true
    }

    /// Get current subscription status with TTL validation
    func getVerifiedSubscriptionStatus() -> String {
        guard let plan = UserDefaults.standard.string(forKey: subscriptionTokenKey),
              let timestamp = UserDefaults.standard.object(forKey: subscriptionTimestampKey) as? Double else {
            return "FREE"
        }

        // Check TTL
        let tokenDate = Date(timeIntervalSince1970: timestamp)
        let age = Date().timeIntervalSince(tokenDate)

        if age > Self.subscriptionTTL {
            logger.info("Subscription token expired (age: \(Int(age / 3600))h), defaulting to FREE")
            return "FREE"
        }

        return plan
    }

    /// Check if subscription has Watch access with TTL enforcement
    var hasVerifiedWatchAccess: Bool {
        let plan = getVerifiedSubscriptionStatus()
        return plan == "PLUS" || plan == "FAMILY"
    }

    /// Compute HMAC-SHA256 signature
    private func computeHMAC(data: String, key: String) -> String {
        let keyData = Data(key.utf8)
        let messageData = Data(data.utf8)

        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        return Data(hmac).base64EncodedString()
    }

    // MARK: - Token Generation (for iPhone side)

    /// Generate a signed subscription token (call this on iPhone side)
    static func generateSubscriptionToken(plan: String, sharedSecret: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let dataToSign = "\(plan)|\(timestamp)"

        let keyData = Data(sharedSecret.utf8)
        let messageData = Data(dataToSign.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        let signature = Data(hmac).base64EncodedString()

        return "\(plan)|\(timestamp)|\(signature)"
    }

    // MARK: - Data Retention (SA3)

    /// Clear data older than retention period
    func enforceDataRetention() {
        let retentionCutoff = Date().addingTimeInterval(-Self.dataRetentionPeriod)

        // Clear old handoffs (handled by WatchDataManager with lastSyncDate check)
        // Clear old voice recordings
        clearOldRecordings(olderThan: retentionCutoff)

        logger.info("Data retention policy enforced")
    }

    private func clearOldRecordings(olderThan cutoffDate: Date) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory

        do {
            let recordings = try fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.creationDateKey]
            ).filter { $0.pathExtension == "m4a" }

            for recording in recordings {
                let values = try recording.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = values.creationDate, creationDate < cutoffDate {
                    try fileManager.removeItem(at: recording)
                    logger.debug("Deleted old recording: \(recording.lastPathComponent, privacy: .public)")
                }
            }
        } catch {
            logger.error("Failed to clear old recordings: \(error.localizedDescription)")
        }
    }

    // MARK: - Secure Clear (for logout/downgrade)

    /// Securely clear all cached PHI data
    func secureClearAllData() {
        // Generate new encryption key to invalidate any existing encrypted data
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        // Store new key in Keychain (overwriting old)
        if !KeychainHelper.save(key: encryptionKeyKey, data: keyData) {
            logger.error("Failed to save new encryption key to Keychain during secure clear")
        }
        _encryptionKey = newKey

        // Also remove any legacy UserDefaults key
        UserDefaults.standard.removeObject(forKey: encryptionKeyKey)

        // Clear subscription token
        UserDefaults.standard.removeObject(forKey: subscriptionTokenKey)
        UserDefaults.standard.removeObject(forKey: subscriptionTimestampKey)
        UserDefaults.standard.removeObject(forKey: subscriptionSignatureKey)

        logger.info("Securely cleared all Watch data")
    }
}

// MARK: - Secure Cache Keys

extension WatchSecurityManager {
    /// Keys for encrypted cache (use these instead of plain keys)
    enum SecureCacheKey: String {
        case emergencyCard = "secure_emergency_card"
        case todayTasks = "secure_today_tasks"
        case recentHandoffs = "secure_recent_handoffs"
        case patients = "secure_patients"
    }
}
