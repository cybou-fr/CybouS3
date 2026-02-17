import XCTest
@testable import SwiftS3

final class CybKMSTests: XCTestCase {
    var kmsService: CybKMSService!
    var tempDir: String!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        kmsService = try await CybKMSService(region: "us-east-1", keyStorePath: tempDir + "/kms.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    func testCreateKey() async throws {
        let metadata = try await kmsService.createKey(description: "Test key")
        XCTAssertEqual(metadata.keyUsage, .encryptDecrypt)
        XCTAssertEqual(metadata.keyState, .enabled)
        XCTAssertEqual(metadata.keySpec, .symmetricDefault)
        XCTAssertNotNil(metadata.keyId)
        XCTAssertTrue(metadata.arn.contains("arn:aws:kms:us-east-1"))
    }

    func testEncryptDecrypt() async throws {
        // Create a key
        let keyMetadata = try await kmsService.createKey(description: "Test encryption key")
        let keyId = keyMetadata.keyId

        // Test data
        let plaintext = "Hello, CybKMS!".data(using: .utf8)!

        // Encrypt
        let encryptResult = try await kmsService.encrypt(plaintext: plaintext, keyId: keyId)
        XCTAssertEqual(encryptResult.keyId, keyId)
        XCTAssertNotEqual(encryptResult.ciphertextBlob, plaintext)

        // Decrypt
        let decryptResult = try await kmsService.decrypt(ciphertextBlob: encryptResult.ciphertextBlob)
        XCTAssertEqual(decryptResult.plaintext, plaintext)
        XCTAssertEqual(decryptResult.keyId, keyId)
    }

    func testEncryptDecryptWithContext() async throws {
        // Create a key
        let keyMetadata = try await kmsService.createKey(description: "Test key with context")
        let keyId = keyMetadata.keyId

        // Test data
        let plaintext = "Sensitive data".data(using: .utf8)!
        let context = ["purpose": "testing", "environment": "unit-test"]

        // Encrypt with context
        let encryptResult = try await kmsService.encrypt(
            plaintext: plaintext,
            keyId: keyId,
            encryptionContext: context
        )

        // Decrypt with same context
        let decryptResult = try await kmsService.decrypt(
            ciphertextBlob: encryptResult.ciphertextBlob,
            encryptionContext: context
        )
        XCTAssertEqual(decryptResult.plaintext, plaintext)
    }

    func testKeyNotFound() async throws {
        let plaintext = "Test".data(using: .utf8)!

        do {
            _ = try await kmsService.encrypt(plaintext: plaintext, keyId: "non-existent-key")
            XCTFail("Expected error for non-existent key")
        } catch let error as KMSError {
            XCTAssertEqual(error, KMSError.notFoundException("Key 'non-existent-key' not found"))
        }
    }

    func testListKeys() async throws {
        // Initially no keys
        var keys = try await kmsService.listKeys()
        XCTAssertEqual(keys.count, 0)

        // Create a key
        _ = try await kmsService.createKey(description: "First key")
        keys = try await kmsService.listKeys()
        XCTAssertEqual(keys.count, 1)

        // Create another key
        _ = try await kmsService.createKey(description: "Second key")
        keys = try await kmsService.listKeys()
        XCTAssertEqual(keys.count, 2)
    }

    func testDescribeKey() async throws {
        let createdKey = try await kmsService.createKey(description: "Test describe")
        let describedKey = try await kmsService.describeKey(keyId: createdKey.keyId)

        XCTAssertEqual(describedKey.keyId, createdKey.keyId)
        XCTAssertEqual(describedKey.arn, createdKey.arn)
        XCTAssertEqual(describedKey.description, "Test describe")
    }

    func testKeyStateManagement() async throws {
        let key = try await kmsService.createKey(description: "State test")
        XCTAssertEqual(key.keyState, .enabled)

        // Disable key
        try await kmsService.disableKey(keyId: key.keyId)
        let disabledKey = try await kmsService.describeKey(keyId: key.keyId)
        XCTAssertEqual(disabledKey.keyState, .disabled)

        // Enable key
        try await kmsService.enableKey(keyId: key.keyId)
        let enabledKey = try await kmsService.describeKey(keyId: key.keyId)
        XCTAssertEqual(enabledKey.keyState, .enabled)
    }

    func testPersistence() async throws {
        // Create a key with first service instance
        let key1 = try await kmsService.createKey(description: "Persistent key")
        let keyId = key1.keyId

        // Create a new service instance (simulating restart)
        let kmsService2 = try await CybKMSService(region: "us-east-1", keyStorePath: tempDir + "/kms.json")

        // Key should still exist
        let key2 = try await kmsService2.describeKey(keyId: keyId)
        XCTAssertEqual(key2.keyId, keyId)
        XCTAssertEqual(key2.description, "Persistent key")

        // Should be able to encrypt/decrypt with the persisted key
        let plaintext = "Persistent test".data(using: .utf8)!
        let encrypted = try await kmsService2.encrypt(plaintext: plaintext, keyId: keyId)
        let decrypted = try await kmsService2.decrypt(ciphertextBlob: encrypted.ciphertextBlob)
        XCTAssertEqual(decrypted.plaintext, plaintext)
    }
}