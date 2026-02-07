import Foundation
import CryptoKit

// MARK: - Encryption Service

/// Service for encrypting/decrypting sensitive wellness data using AES-256-GCM.
/// Notes field is encrypted at rest to protect user privacy.
///
/// **WARNING: DATA LOSS RISK ON DEVICE CHANGE**
/// The encryption key is stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
/// meaning it is NOT included in iCloud Keychain backups or device transfers. If the user
/// switches devices, resets their device, or restores from a non-encrypted backup, all
/// previously encrypted notes will become permanently unreadable.
///
/// TODO: Migrate key storage to use `kSecAttrAccessibleAfterFirstUnlock` (without
/// `ThisDeviceOnly`) or implement iCloud Keychain sharing via a shared App Group
/// keychain to enable key recovery across devices. This is required before production
/// launch to prevent silent data loss.
final class EncryptionService {

    // MARK: - Types

    struct EncryptedData {
        let ciphertext: String  // Base64 encoded
        let nonce: String       // Base64 encoded
        let tag: String         // Base64 encoded
    }

    enum EncryptionError: LocalizedError {
        case keyGenerationFailed
        case encryptionFailed
        case decryptionFailed
        case invalidData
        case keyNotFound

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed:
                return "Failed to generate encryption key"
            case .encryptionFailed:
                return "Failed to encrypt data"
            case .decryptionFailed:
                return "Failed to decrypt data"
            case .invalidData:
                return "Invalid encrypted data format"
            case .keyNotFound:
                return "Encryption key not found"
            }
        }
    }

    // MARK: - Singleton

    static let shared = EncryptionService()

    // MARK: - Private Properties

    private let keychainService = "com.curaknot.wellness"
    private let keychainAccount = "notes-encryption-key"

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Encrypt plaintext notes using AES-256-GCM
    func encrypt(_ plaintext: String) throws -> EncryptedData {
        let key = try getOrCreateKey()
        let plaintextData = Data(plaintext.utf8)
        let nonce = AES.GCM.Nonce()

        let sealedBox = try AES.GCM.seal(plaintextData, using: key, nonce: nonce)

        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        // Extract components
        let nonceData = Data(nonce)
        let tagData = sealedBox.tag
        let ciphertextData = sealedBox.ciphertext

        return EncryptedData(
            ciphertext: ciphertextData.base64EncodedString(),
            nonce: nonceData.base64EncodedString(),
            tag: tagData.base64EncodedString()
        )
    }

    /// Decrypt encrypted notes using AES-256-GCM
    func decrypt(ciphertext: String, nonce: String, tag: String) throws -> String {
        let key = try getOrCreateKey()

        guard let ciphertextData = Data(base64Encoded: ciphertext),
              let nonceData = Data(base64Encoded: nonce),
              let tagData = Data(base64Encoded: tag) else {
            throw EncryptionError.invalidData
        }

        let aesNonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: aesNonce, ciphertext: ciphertextData, tag: tagData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }

        return plaintext
    }

    /// Decrypt from EncryptedData struct
    func decrypt(_ encrypted: EncryptedData) throws -> String {
        try decrypt(ciphertext: encrypted.ciphertext, nonce: encrypted.nonce, tag: encrypted.tag)
    }

    // MARK: - Key Management

    /// Get existing key or create new one
    private func getOrCreateKey() throws -> SymmetricKey {
        if let existingKey = try loadKey() {
            return existingKey
        }
        return try createAndStoreKey()
    }

    /// Generate a new AES-256 key and store in Keychain
    private func createAndStoreKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        try storeKey(key)
        return key
    }

    /// Store key in Keychain
    private func storeKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keyGenerationFailed
        }
    }

    /// Load key from Keychain
    private func loadKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let keyData = result as? Data else {
            throw EncryptionError.keyNotFound
        }

        return SymmetricKey(data: keyData)
    }

    /// Delete stored key (for testing or reset)
    func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
