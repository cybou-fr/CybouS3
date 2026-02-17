import XCTest
@testable import SwiftS3

final class ServerSideEncryptionTests: XCTestCase {
    var storage: FileSystemStorage!
    var tempDir: String!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        storage = try await FileSystemStorage(rootPath: tempDir, testMode: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    func testCybKMSEncryption() async throws {
        // TODO: Update test to use CybKMSClient with test server endpoint
        // This test was using the legacy embedded CybKMS service which has been removed
        throw XCTSkip("Test needs to be updated to use standalone CybKMS server")

        // Create encryption config for CybKMS
        let config = ServerSideEncryptionConfig(
            algorithm: .cybKms,
            kmsKeyId: keyId,
            kmsEncryptionContext: "test-context"
        )

        // Encrypt data
        let (encryptedData, key, iv) = try await storage.encryptData(testData, with: config)

        // Verify encryption worked (data should be different)
        XCTAssertNotEqual(encryptedData, testData)
        // For CybKMS, key and iv should be nil since KMS handles the key
        XCTAssertNil(key)
        XCTAssertNil(iv)

        // Decrypt data
        let decryptedData = try await storage.decryptData(encryptedData, with: config, key: key, iv: iv)

        // Verify decryption worked
        XCTAssertEqual(decryptedData, testData)
    }

    func testAES256Encryption() async throws {
        // Test data
        let testData = "Hello, AES256 Server-Side Encryption!".data(using: .utf8)!

        // Create encryption config for AES256
        let config = ServerSideEncryptionConfig(algorithm: .aes256)

        // Encrypt data
        let (encryptedData, key, iv) = try await storage.encryptData(testData, with: config)

        // Verify encryption worked
        XCTAssertNotEqual(encryptedData, testData)
        XCTAssertNotNil(key)
        XCTAssertNotNil(iv)

        // Decrypt data
        let decryptedData = try await storage.decryptData(encryptedData, with: config, key: key, iv: iv)

        // Verify decryption worked
        XCTAssertEqual(decryptedData, testData)
    }

    func testMultipleCybKMSKeys() async throws {
        // TODO: Update test to use CybKMSClient with test server endpoint
        // This test was using the legacy embedded CybKMS service which has been removed
        throw XCTSkip("Test needs to be updated to use standalone CybKMS server")

        let testData1 = "Data encrypted with key 1".data(using: .utf8)!
        let testData2 = "Data encrypted with key 2".data(using: .utf8)!

        // Encrypt with different CybKMS keys
        let config1 = ServerSideEncryptionConfig(algorithm: .cybKms, kmsKeyId: key1Metadata.keyId)
        let config2 = ServerSideEncryptionConfig(algorithm: .cybKms, kmsKeyId: key2Metadata.keyId)

        let (encrypted1, _, _) = try await storage.encryptData(testData1, with: config1)
        let (encrypted2, _, _) = try await storage.encryptData(testData2, with: config2)

        // Data encrypted with different keys should be different
        XCTAssertNotEqual(encrypted1, encrypted2)

        // But should decrypt correctly with respective keys
        let decrypted1 = try await storage.decryptData(encrypted1, with: config1, key: nil, iv: nil)
        let decrypted2 = try await storage.decryptData(encrypted2, with: config2, key: nil, iv: nil)

        XCTAssertEqual(decrypted1, testData1)
        XCTAssertEqual(decrypted2, testData2)
    }

    func testCybKMSEncryptionContext() async throws {
        // TODO: Update test to use CybKMSClient with test server endpoint
        // This test was using the legacy embedded CybKMS service which has been removed
        throw XCTSkip("Test needs to be updated to use standalone CybKMS server")

        let testData = "Data with encryption context".data(using: .utf8)!

        // Encrypt with context
        let configWithContext = ServerSideEncryptionConfig(
            algorithm: .cybKms,
            kmsKeyId: keyMetadata.keyId,
            kmsEncryptionContext: "bucket=mybucket&object=myobject"
        )

        let (encryptedData, _, _) = try await storage.encryptData(testData, with: configWithContext)

        // Decrypt with same context
        let decryptedData = try await storage.decryptData(encryptedData, with: configWithContext, key: nil, iv: nil)
        XCTAssertEqual(decryptedData, testData)
    }
}