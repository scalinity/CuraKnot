import Foundation
import CryptoKit
import Security
import os.log

// MARK: - Calendar Security Manager

/// Handles HMAC integrity verification and PHI encryption for calendar sync operations
/// SECURITY: This manager provides defense-in-depth for calendar data flows
final class CalendarSecurityManager {
    // MARK: - Singleton

    static let shared = CalendarSecurityManager()

    // MARK: - Logging

    private static let logger = Logger(subsystem: "com.curaknot", category: "CalendarSecurity")

    // MARK: - Keychain Keys

    private let hmacKeyId = "calendar_hmac_key"
    private let encryptionKeyId = "calendar_encryption_key"
    private let keychainService = "com.curaknot.app.calendar"

    // MARK: - Cached Keys (thread-safe via serial queue)

    private let keyQueue = DispatchQueue(label: "com.curaknot.calendar.security.keys")
    private var _hmacKey: SymmetricKey?
    private var _encryptionKey: SymmetricKey?

    // MARK: - Initialization

    private init() {
        // Initialize keys on first use
        _ = getOrCreateHMACKey()
        _ = getOrCreateEncryptionKey()
    }

    // MARK: - HMAC Integrity Verification

    /// Compute HMAC-SHA256 checksum for data integrity verification during sync
    /// SECURITY: Ensures data wasn't tampered with during local storage or transit
    func computeChecksum(for event: CalendarEventChecksumData) -> String {
        let key = getOrCreateHMACKey()

        // Create a deterministic string from event data
        let dataString = [
            event.id,
            event.title,
            event.description ?? "",
            String(event.startAt.timeIntervalSince1970),
            String(event.endAt?.timeIntervalSince1970 ?? 0),
            event.location ?? "",
            String(event.allDay)
        ].joined(separator: "|")

        let dataToSign = Data(dataString.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: dataToSign, using: key)
        return Data(hmac).base64EncodedString()
    }

    /// Verify HMAC checksum for a calendar event
    /// Returns true if checksum matches, false if tampered or no checksum exists
    func verifyChecksum(for event: CalendarEventChecksumData, expectedChecksum: String?) -> Bool {
        guard let expected = expectedChecksum, !expected.isEmpty else {
            // No checksum to verify - log for monitoring
            Self.logger.warning("No checksum present for event \(event.id, privacy: .public)")
            return false
        }

        let computed = computeChecksum(for: event)

        // Constant-time comparison to prevent timing attacks
        guard expected.count == computed.count else {
            Self.logger.error("Checksum length mismatch for event \(event.id, privacy: .public)")
            return false
        }

        var result: UInt8 = 0
        for (a, b) in zip(expected.utf8, computed.utf8) {
            result |= a ^ b
        }

        if result != 0 {
            Self.logger.error("Checksum verification failed for event \(event.id, privacy: .public) - possible tampering")
        }

        return result == 0
    }

    // MARK: - Conflict Data Encryption

    /// Encrypt conflict data JSON before storing in database
    /// SECURITY: Conflict data may contain PHI (titles, descriptions) that should be encrypted at rest
    func encryptConflictData(_ plaintext: String) -> String? {
        guard !plaintext.isEmpty else { return nil }

        let key = getOrCreateEncryptionKey()
        let plaintextData = Data(plaintext.utf8)

        do {
            let sealedBox = try AES.GCM.seal(plaintextData, using: key)
            guard let combined = sealedBox.combined else {
                Self.logger.error("Failed to get combined sealed box data")
                return nil
            }
            return combined.base64EncodedString()
        } catch {
            Self.logger.error("Failed to encrypt conflict data: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Decrypt conflict data JSON when reading from database
    func decryptConflictData(_ ciphertext: String) -> String? {
        guard !ciphertext.isEmpty else { return nil }

        guard let ciphertextData = Data(base64Encoded: ciphertext) else {
            Self.logger.error("Failed to decode base64 ciphertext")
            return nil
        }

        let key = getOrCreateEncryptionKey()

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertextData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            Self.logger.error("Failed to decrypt conflict data: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Key Management

    /// Get or create HMAC signing key from Keychain
    private func getOrCreateHMACKey() -> SymmetricKey {
        keyQueue.sync {
            if let cached = _hmacKey {
                return cached
            }

            // Try to load from Keychain
            if let keyData = loadFromKeychain(key: hmacKeyId) {
                let key = SymmetricKey(data: keyData)
                _hmacKey = key
                return key
            }

            // Generate new key
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }

            if saveToKeychain(key: hmacKeyId, data: keyData) {
                Self.logger.info("Generated new HMAC key for calendar integrity verification")
            } else {
                Self.logger.error("Failed to save HMAC key to Keychain")
            }

            _hmacKey = key
            return key
        }
    }

    /// Get or create AES-GCM encryption key from Keychain
    private func getOrCreateEncryptionKey() -> SymmetricKey {
        keyQueue.sync {
            if let cached = _encryptionKey {
                return cached
            }

            // Try to load from Keychain
            if let keyData = loadFromKeychain(key: encryptionKeyId) {
                let key = SymmetricKey(data: keyData)
                _encryptionKey = key
                return key
            }

            // Generate new key
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }

            if saveToKeychain(key: encryptionKeyId, data: keyData) {
                Self.logger.info("Generated new encryption key for conflict data")
            } else {
                Self.logger.error("Failed to save encryption key to Keychain")
            }

            _encryptionKey = key
            return key
        }
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(key: String, data: Data) -> Bool {
        // Delete existing item first
        deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
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

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Key Rotation (for future use)

    /// Rotate encryption key - call this if key compromise is suspected
    /// WARNING: This will invalidate all existing encrypted conflict data
    func rotateEncryptionKey() {
        keyQueue.sync {
            deleteFromKeychain(key: encryptionKeyId)
            _encryptionKey = nil
        }
        _ = getOrCreateEncryptionKey()
        Self.logger.warning("Encryption key rotated - existing encrypted data is now unrecoverable")
    }

    /// Rotate HMAC key - call this if key compromise is suspected
    /// WARNING: This will invalidate all existing checksums
    func rotateHMACKey() {
        keyQueue.sync {
            deleteFromKeychain(key: hmacKeyId)
            _hmacKey = nil
        }
        _ = getOrCreateHMACKey()
        Self.logger.warning("HMAC key rotated - existing checksums are now invalid")
    }
}

// MARK: - Checksum Data Protocol

/// Protocol for data needed to compute HMAC checksum
protocol CalendarEventChecksumData {
    var id: String { get }
    var title: String { get }
    var description: String? { get }
    var startAt: Date { get }
    var endAt: Date? { get }
    var location: String? { get }
    var allDay: Bool { get }
}
