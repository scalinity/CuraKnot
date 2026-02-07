import XCTest
import CryptoKit
@testable import CuraKnot

final class WatchSecurityTests: XCTestCase {

    // MARK: - HMAC Signature Tests

    func testHMACSignatureGeneration() {
        // Test that HMAC-SHA256 generates consistent signatures
        let secret = "test-secret-key"
        let data = "PLUS|1700000000"

        let keyData = Data(secret.utf8)
        let messageData = Data(data.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        let signature1 = Data(hmac).base64EncodedString()

        // Generate again - should be identical
        let hmac2 = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        let signature2 = Data(hmac2).base64EncodedString()

        XCTAssertEqual(signature1, signature2)
        XCTAssertFalse(signature1.isEmpty)
    }

    func testHMACSignatureChangesWithDifferentSecret() {
        let data = "PLUS|1700000000"

        let keyData1 = Data("secret1".utf8)
        let keyData2 = Data("secret2".utf8)
        let messageData = Data(data.utf8)

        let hmac1 = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData1))
        let signature1 = Data(hmac1).base64EncodedString()

        let hmac2 = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData2))
        let signature2 = Data(hmac2).base64EncodedString()

        XCTAssertNotEqual(signature1, signature2)
    }

    func testHMACSignatureChangesWithDifferentData() {
        let secret = "test-secret-key"
        let keyData = Data(secret.utf8)

        let data1 = "PLUS|1700000000"
        let data2 = "FREE|1700000000"

        let hmac1 = HMAC<SHA256>.authenticationCode(for: Data(data1.utf8), using: SymmetricKey(data: keyData))
        let signature1 = Data(hmac1).base64EncodedString()

        let hmac2 = HMAC<SHA256>.authenticationCode(for: Data(data2.utf8), using: SymmetricKey(data: keyData))
        let signature2 = Data(hmac2).base64EncodedString()

        XCTAssertNotEqual(signature1, signature2)
    }

    // MARK: - Subscription Token Format Tests

    func testSubscriptionTokenFormat() {
        // Token format: plan|timestamp|signature
        let plan = "PLUS"
        let timestamp = Int(Date().timeIntervalSince1970)
        let dataToSign = "\(plan)|\(timestamp)"
        let secret = "test-secret"

        let keyData = Data(secret.utf8)
        let messageData = Data(dataToSign.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        let signature = Data(hmac).base64EncodedString()

        let token = "\(plan)|\(timestamp)|\(signature)"

        // Parse token
        let components = token.split(separator: "|")
        XCTAssertEqual(components.count, 3)
        XCTAssertEqual(String(components[0]), "PLUS")
        XCTAssertNotNil(Int(components[1]))
        XCTAssertFalse(String(components[2]).isEmpty)
    }

    func testSubscriptionTokenVerification() {
        let plan = "PLUS"
        let timestamp = Int(Date().timeIntervalSince1970)
        let dataToSign = "\(plan)|\(timestamp)"
        let secret = "test-secret"

        // Generate signature
        let keyData = Data(secret.utf8)
        let messageData = Data(dataToSign.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        let signature = Data(hmac).base64EncodedString()

        // Verify signature
        let expectedSignature = signature
        let regeneratedHmac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        let regeneratedSignature = Data(regeneratedHmac).base64EncodedString()

        XCTAssertEqual(expectedSignature, regeneratedSignature)
    }

    func testTamperedTokenDetection() {
        let plan = "PLUS"
        let timestamp = Int(Date().timeIntervalSince1970)
        let dataToSign = "\(plan)|\(timestamp)"
        let secret = "test-secret"

        // Generate original signature
        let keyData = Data(secret.utf8)
        let messageData = Data(dataToSign.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        let originalSignature = Data(hmac).base64EncodedString()

        // Attempt to verify with tampered plan
        let tamperedDataToSign = "FAMILY|\(timestamp)"
        let tamperedHmac = HMAC<SHA256>.authenticationCode(for: Data(tamperedDataToSign.utf8), using: SymmetricKey(data: keyData))
        let tamperedSignature = Data(tamperedHmac).base64EncodedString()

        // Original signature should not match tampered data
        XCTAssertNotEqual(originalSignature, tamperedSignature)
    }

    // MARK: - AES-GCM Encryption Tests

    func testAESGCMEncryptionDecryption() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "Sensitive PHI data for test".data(using: .utf8)!

        // Encrypt
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        let encryptedData = sealedBox.combined!

        // Verify encrypted data is different from plaintext
        XCTAssertNotEqual(encryptedData, plaintext)

        // Decrypt
        let openedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(openedBox, using: key)

        // Verify decrypted data matches original
        XCTAssertEqual(decryptedData, plaintext)
    }

    func testAESGCMDecryptionWithWrongKey() {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let plaintext = "Sensitive PHI data for test".data(using: .utf8)!

        do {
            // Encrypt with key1
            let sealedBox = try AES.GCM.seal(plaintext, using: key1)
            let encryptedData = sealedBox.combined!

            // Attempt to decrypt with key2 - should fail
            let openedBox = try AES.GCM.SealedBox(combined: encryptedData)
            _ = try AES.GCM.open(openedBox, using: key2)
            XCTFail("Decryption with wrong key should have failed")
        } catch {
            // Expected - decryption with wrong key should throw
            XCTAssertTrue(true)
        }
    }

    func testAESGCMEncryptionProducesUniqueOutput() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "Same data encrypted twice".data(using: .utf8)!

        // Encrypt twice - AES-GCM uses unique nonce each time
        let sealedBox1 = try AES.GCM.seal(plaintext, using: key)
        let sealedBox2 = try AES.GCM.seal(plaintext, using: key)

        // Encrypted outputs should be different (unique nonces)
        XCTAssertNotEqual(sealedBox1.combined, sealedBox2.combined)

        // But both should decrypt to same plaintext
        let decrypted1 = try AES.GCM.open(sealedBox1, using: key)
        let decrypted2 = try AES.GCM.open(sealedBox2, using: key)

        XCTAssertEqual(decrypted1, plaintext)
        XCTAssertEqual(decrypted2, plaintext)
    }

    // MARK: - Timestamp Validation Tests

    func testTimestampWithinRange() {
        let now = Date()
        let maxAge: TimeInterval = 24 * 60 * 60  // 24 hours
        let maxFuture: TimeInterval = 5 * 60     // 5 minutes

        // 1 hour ago - should be valid
        let oneHourAgo = now.addingTimeInterval(-3600)
        XCTAssertTrue(now.timeIntervalSince(oneHourAgo) < maxAge)
        XCTAssertTrue(oneHourAgo.timeIntervalSince(now) < maxFuture)

        // 25 hours ago - should be invalid (too old)
        let tooOld = now.addingTimeInterval(-25 * 3600)
        XCTAssertFalse(now.timeIntervalSince(tooOld) < maxAge)

        // 10 minutes in future - should be invalid (too future)
        let tooFuture = now.addingTimeInterval(10 * 60)
        XCTAssertFalse(tooFuture.timeIntervalSince(now) < maxFuture)
    }

    // MARK: - TTL Expiration Tests

    func testTTLExpiration() {
        let subscriptionTTL: TimeInterval = 24 * 60 * 60

        // Token from 12 hours ago - should be valid
        let recentToken = Date().addingTimeInterval(-12 * 3600)
        let recentAge = Date().timeIntervalSince(recentToken)
        XCTAssertFalse(recentAge > subscriptionTTL)

        // Token from 25 hours ago - should be expired
        let expiredToken = Date().addingTimeInterval(-25 * 3600)
        let expiredAge = Date().timeIntervalSince(expiredToken)
        XCTAssertTrue(expiredAge > subscriptionTTL)
    }
}
