import XCTest
@testable import CybKMS
import Crypto

final class KMSCoreTests: XCTestCase {
    var keyStore: KMSKeyStore!
    var operations: KMSOperations!

    override func setUp() async throws {
        keyStore = try await KMSKeyStore(persistencePath: nil) // In-memory
        operations = KMSOperations(keyStore: keyStore)
    }

    override func tearDown() async throws {
        // Clean up if needed
    }

    // MARK: - Basic Type Tests

    func testBasicImport() throws {
        // Basic test to ensure the module imports correctly
        XCTAssertTrue(true)
    }

    func testKMSErrorEquatable() throws {
        let error1 = KMSError.notFoundException("test")
        let error2 = KMSError.notFoundException("test")
        let error3 = KMSError.notFoundException("different")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testKMSEncryptionAlgorithm() throws {
        let algo = KMSEncryptionAlgorithm.symmetricDefault
        XCTAssertEqual(algo, .symmetricDefault)
        XCTAssertEqual(algo.rawValue, "SYMMETRIC_DEFAULT")
    }

    func testKMSKeyUsage() throws {
        let usage = KMSKeyUsage.encryptDecrypt
        XCTAssertEqual(usage, .encryptDecrypt)
        XCTAssertEqual(usage.rawValue, "ENCRYPT_DECRYPT")
    }

    func testKMSKeyState() throws {
        let state = KMSKeyState.enabled
        XCTAssertEqual(state, .enabled)
        XCTAssertEqual(state.rawValue, "Enabled")
    }

    func testKMSKeySpec() throws {
        let spec = KMSKeySpec.symmetricDefault
        XCTAssertEqual(spec, .symmetricDefault)
        XCTAssertEqual(spec.rawValue, "SYMMETRIC_DEFAULT")
    }

    // MARK: - Key Operations Tests

    func testCreateKey() async throws {
        let key = try await operations.createKey(description: "Test Key", keyUsage: .encryptDecrypt)

        XCTAssertNotNil(key.keyId)
        XCTAssertEqual(key.description, "Test Key")
        XCTAssertEqual(key.keyUsage, .encryptDecrypt)
        XCTAssertEqual(key.keyState, .enabled)
        XCTAssertTrue(key.enabled)
        XCTAssertEqual(key.keySpec, .symmetricDefault)
    }

    func testEncryptDecrypt() async throws {
        let key = try await operations.createKey()
        let plaintext = "Hello, World!".data(using: .utf8)!

        let encryptResult = try await operations.encrypt(plaintext: plaintext, keyId: key.keyId)
        XCTAssertEqual(encryptResult.keyId, key.keyId)
        XCTAssertNotEqual(encryptResult.ciphertextBlob, plaintext)

        let decryptResult = try await operations.decrypt(ciphertextBlob: encryptResult.ciphertextBlob)
        XCTAssertEqual(decryptResult.plaintext, plaintext)
        XCTAssertEqual(decryptResult.keyId, key.keyId)
    }

    func testListKeys() async throws {
        let initialCount = await keyStore.listKeys().count
        let key1 = try await operations.createKey(description: "Key 1")
        let key2 = try await operations.createKey(description: "Key 2")

        let keys = await keyStore.listKeys()
        XCTAssertEqual(keys.count, initialCount + 2)

        let keyIds = Set(keys.map { $0.keyId })
        XCTAssertTrue(keyIds.contains(key1.keyId))
        XCTAssertTrue(keyIds.contains(key2.keyId))
    }

    func testDescribeKey() async throws {
        let createdKey = try await operations.createKey(description: "Test Key")
        let describedKey = try await operations.describeKey(keyId: createdKey.keyId)

        XCTAssertEqual(describedKey.keyId, createdKey.keyId)
        XCTAssertEqual(describedKey.description, "Test Key")
    }

    func testEnableDisableKey() async throws {
        let key = try await operations.createKey()

        // Initially enabled
        var describedKey = try await operations.describeKey(keyId: key.keyId)
        XCTAssertEqual(describedKey.keyState, .enabled)
        XCTAssertTrue(describedKey.enabled)

        // Disable
        try await operations.disableKey(keyId: key.keyId)
        describedKey = try await operations.describeKey(keyId: key.keyId)
        XCTAssertEqual(describedKey.keyState, .disabled)
        XCTAssertFalse(describedKey.enabled)

        // Enable
        try await operations.enableKey(keyId: key.keyId)
        describedKey = try await operations.describeKey(keyId: key.keyId)
        XCTAssertEqual(describedKey.keyState, .enabled)
        XCTAssertTrue(describedKey.enabled)
    }

    func testScheduleKeyDeletion() async throws {
        let key = try await operations.createKey()
        try await operations.scheduleKeyDeletion(keyId: key.keyId)

        let describedKey = try await operations.describeKey(keyId: key.keyId)
        XCTAssertEqual(describedKey.keyState, .pendingDeletion)
        XCTAssertFalse(describedKey.enabled)
    }

    // MARK: - Error Handling Tests

    func testDescribeNonExistentKey() async throws {
        do {
            _ = try await operations.describeKey(keyId: "non-existent")
            XCTFail("Expected error for non-existent key")
        } catch let error as KMSError {
            XCTAssertEqual(error, .notFoundException("Key 'non-existent' not found"))
        }
    }

    func testEncryptWithDisabledKey() async throws {
        let key = try await operations.createKey()
        try await operations.disableKey(keyId: key.keyId)

        let plaintext = "Test data".data(using: .utf8)!

        do {
            _ = try await operations.encrypt(plaintext: plaintext, keyId: key.keyId)
            XCTFail("Expected error when encrypting with disabled key")
        } catch let error as KMSError {
            XCTAssertEqual(error, .keyUnavailableException("Key '\(key.keyId)' is not enabled"))
        }
    }

    // MARK: - Key ARN Tests

    func testKeyArnFormat() async throws {
        let key = try await operations.createKey()
        XCTAssertTrue(key.arn.hasPrefix("arn:cyb:kms:local:000000000000:key/"))
        XCTAssertTrue(key.arn.hasSuffix(key.keyId))
    }
}