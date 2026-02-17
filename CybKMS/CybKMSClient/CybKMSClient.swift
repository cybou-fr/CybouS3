import AsyncHTTPClient
import Foundation
import Logging
import NIOCore

/// KMS Key State enumeration
public enum KMSKeyState: String, Codable, Sendable {
    case enabled = "Enabled"
    case disabled = "Disabled"
    case pendingDeletion = "PendingDeletion"
    case pendingImport = "PendingImport"
    case unavailable = "Unavailable"
}

/// KMS encryption algorithms
public enum KMSEncryptionAlgorithm: String, Codable, Sendable {
    case symmetricDefault = "SYMMETRIC_DEFAULT"
}

/// KMS key specification
public enum KMSKeySpec: String, Codable, Sendable {
    case symmetricDefault = "SYMMETRIC_DEFAULT"
    case rsa2048 = "RSA_2048"
    case rsa3072 = "RSA_3072"
    case rsa4096 = "RSA_4096"
    case eccNistP256 = "ECC_NIST_P256"
    case eccNistP384 = "ECC_NIST_P384"
    case eccNistP521 = "ECC_NIST_P521"
}

/// KMS key usage
public enum KMSKeyUsage: String, Codable, Sendable {
    case encryptDecrypt = "ENCRYPT_DECRYPT"
    case signVerify = "SIGN_VERIFY"
    case generateVerifyMac = "GENERATE_VERIFY_MAC"
}

/// KMS key metadata
public struct KMSKeyMetadata: Codable, Sendable {
    public let keyId: String
    public let arn: String
    public let description: String?
    public let keyUsage: KMSKeyUsage
    public let keyState: KMSKeyState
    public let keyManager: String
    public let keySpec: KMSKeySpec
    public let creationDate: Date
    public let enabled: Bool
    public let deletionDate: Date?
    public let validTo: Date?
    public let origin: String
    public let customKeyStoreId: String?
    public let cloudHsmClusterId: String?
    public let expirationModel: String?
    public let keyManagerId: String?
    public let multiRegion: Bool
    public let multiRegionConfiguration: [String: String]?
    public let pendingDeletionWindowInDays: Int?

    public init(
        keyId: String,
        arn: String,
        description: String? = nil,
        keyUsage: KMSKeyUsage,
        keyState: KMSKeyState,
        keyManager: String,
        keySpec: KMSKeySpec,
        creationDate: Date,
        enabled: Bool,
        deletionDate: Date? = nil,
        validTo: Date? = nil,
        origin: String,
        customKeyStoreId: String? = nil,
        cloudHsmClusterId: String? = nil,
        expirationModel: String? = nil,
        keyManagerId: String? = nil,
        multiRegion: Bool = false,
        multiRegionConfiguration: [String: String]? = nil,
        pendingDeletionWindowInDays: Int? = nil
    ) {
        self.keyId = keyId
        self.arn = arn
        self.description = description
        self.keyUsage = keyUsage
        self.keyState = keyState
        self.keyManager = keyManager
        self.keySpec = keySpec
        self.creationDate = creationDate
        self.enabled = enabled
        self.deletionDate = deletionDate
        self.validTo = validTo
        self.origin = origin
        self.customKeyStoreId = customKeyStoreId
        self.cloudHsmClusterId = cloudHsmClusterId
        self.expirationModel = expirationModel
        self.keyManagerId = keyManagerId
        self.multiRegion = multiRegion
        self.multiRegionConfiguration = multiRegionConfiguration
        self.pendingDeletionWindowInDays = pendingDeletionWindowInDays
    }
}

/// KMS error
public struct KMSError: Error, Codable, Sendable {
    public let type: String
    public let message: String
    public let code: String?

    public init(type: String, message: String, code: String? = nil) {
        self.type = type
        self.message = message
        self.code = code
    }
}

/// Result of a KMS encrypt operation
public struct KMSEncryptResult: Codable, Sendable {
    public let ciphertextBlob: Data
    public let keyId: String
    public let arn: String
    public let encryptionAlgorithm: KMSEncryptionAlgorithm

    public init(ciphertextBlob: Data, keyId: String, arn: String, encryptionAlgorithm: KMSEncryptionAlgorithm = .symmetricDefault) {
        self.ciphertextBlob = ciphertextBlob
        self.keyId = keyId
        self.arn = arn
        self.encryptionAlgorithm = encryptionAlgorithm
    }
}

/// Result of a KMS decrypt operation
public struct KMSDecryptResult: Codable, Sendable {
    public let plaintext: Data
    public let keyId: String
    public let arn: String
    public let encryptionAlgorithm: KMSEncryptionAlgorithm

    public init(plaintext: Data, keyId: String, arn: String, encryptionAlgorithm: KMSEncryptionAlgorithm = .symmetricDefault) {
        self.plaintext = plaintext
        self.keyId = keyId
        self.arn = arn
        self.encryptionAlgorithm = encryptionAlgorithm
    }
}

/// CybKMS Client - HTTP client for communicating with CybKMS server
public actor CybKMSClient {
    private let httpClient: HTTPClient
    private let baseURL: URL
    private let logger = Logger(label: "CybKMS.Client")

    /// Initialize CybKMS client
    /// - Parameters:
    ///   - endpoint: URL of the CybKMS server (e.g., "http://localhost:8080")
    public init(endpoint: String) throws {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint URL"])
        }
        self.baseURL = url
        self.httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
    }

    deinit {
        try? httpClient.shutdown()
    }

    // MARK: - Key Management

    /// Create a new KMS key
    public func createKey(description: String? = nil, keyUsage: KMSKeyUsage = .encryptDecrypt) async throws -> KMSKeyMetadata {
        let input = CreateKeyInput(description: description, keyUsage: keyUsage, keySpec: .symmetricDefault)
        return try await post("/CreateKey", body: input)
    }

    /// Describe a KMS key
    public func describeKey(keyId: String) async throws -> KMSKeyMetadata {
        let input = DescribeKeyInput(keyId: keyId)
        return try await post("/DescribeKey", body: input)
    }

    /// List KMS keys
    public func listKeys() async throws -> [KMSKeyMetadata] {
        let output: ListKeysOutput = try await post("/ListKeys", body: EmptyInput())
        return output.keys
    }

    /// Enable a KMS key
    public func enableKey(keyId: String) async throws -> KMSKeyMetadata {
        let input = EnableKeyInput(keyId: keyId)
        return try await post("/EnableKey", body: input)
    }

    /// Disable a KMS key
    public func disableKey(keyId: String) async throws -> KMSKeyMetadata {
        let input = DisableKeyInput(keyId: keyId)
        return try await post("/DisableKey", body: input)
    }

    /// Schedule key deletion
    public func scheduleKeyDeletion(keyId: String, pendingWindowInDays: Int = 7) async throws -> ScheduleKeyDeletionOutput {
        let input = ScheduleKeyDeletionInput(keyId: keyId, pendingWindowInDays: pendingWindowInDays)
        return try await post("/ScheduleKeyDeletion", body: input)
    }

    // MARK: - Cryptographic Operations

    /// Encrypt data using a KMS key
    public func encrypt(
        plaintext: Data,
        keyId: String,
        encryptionAlgorithm: KMSEncryptionAlgorithm = .symmetricDefault,
        encryptionContext: [String: String]? = nil,
        grantTokens: [String]? = nil
    ) async throws -> KMSEncryptResult {
        let input = EncryptInput(
            keyId: keyId,
            plaintext: plaintext,
            encryptionAlgorithm: encryptionAlgorithm,
            encryptionContext: encryptionContext,
            grantTokens: grantTokens
        )
        return try await post("/Encrypt", body: input)
    }

    /// Decrypt data using a KMS key
    public func decrypt(
        ciphertextBlob: Data,
        encryptionAlgorithm: KMSEncryptionAlgorithm = .symmetricDefault,
        encryptionContext: [String: String]? = nil,
        grantTokens: [String]? = nil,
        keyId: String? = nil
    ) async throws -> KMSDecryptResult {
        let input = DecryptInput(
            ciphertextBlob: ciphertextBlob,
            encryptionAlgorithm: encryptionAlgorithm,
            keyId: keyId,
            encryptionContext: encryptionContext,
            grantTokens: grantTokens
        )
        return try await post("/Decrypt", body: input)
    }

    // MARK: - Private Methods

    private func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")

        let jsonData = try JSONEncoder().encode(body)
        request.body = .bytes(ByteBuffer(bytes: jsonData))

        let response = try await httpClient.execute(request, timeout: .seconds(30))

        guard response.status == .ok else {
            // Try to decode error response
            if let errorData = try? await response.body.collect(upTo: 1024 * 1024),
               let error = try? JSONDecoder().decode(KMSError.self, from: Data(errorData.readableBytesView)) {
                throw error
            }
            throw URLError(.badServerResponse)
        }

        let responseData = try await response.body.collect(upTo: 10 * 1024 * 1024) // 10MB limit
        return try JSONDecoder().decode(T.self, from: Data(responseData.readableBytesView))
    }
}

// MARK: - Supporting Types

private struct EmptyInput: Encodable {}

// Input types (duplicated from server for client use)
private struct CreateKeyInput: Encodable {
    let description: String?
    let keyUsage: KMSKeyUsage?
    let keySpec: KMSKeySpec?
}

private struct DescribeKeyInput: Encodable {
    let keyId: String
}

private struct ListKeysOutput: Decodable {
    let keys: [KMSKeyMetadata]
}

private struct EncryptInput: Encodable {
    let keyId: String
    let plaintext: Data
    let encryptionAlgorithm: KMSEncryptionAlgorithm?
    let encryptionContext: [String: String]?
    let grantTokens: [String]?
}

private struct DecryptInput: Encodable {
    let ciphertextBlob: Data
    let encryptionAlgorithm: KMSEncryptionAlgorithm?
    let keyId: String?
    let encryptionContext: [String: String]?
    let grantTokens: [String]?
}

private struct EnableKeyInput: Encodable {
    let keyId: String
}

private struct DisableKeyInput: Encodable {
    let keyId: String
}

private struct ScheduleKeyDeletionInput: Encodable {
    let keyId: String
    let pendingWindowInDays: Int?
}

/// Output for scheduling key deletion
public struct ScheduleKeyDeletionOutput: Decodable {
    public let keyId: String
    public let deletionDate: Date
    public let keyState: KMSKeyState
}