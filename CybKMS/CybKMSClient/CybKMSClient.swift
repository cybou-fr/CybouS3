import AsyncHTTPClient
import Foundation
import Logging
import NIOCore

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
        let input = CreateKeyInput(description: description, keyUsage: keyUsage)
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
        request.body = .bytes(ByteBuffer(data: jsonData))

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

// Re-export types from KMSCore for client usage
public typealias KMSEncryptResult = CybKMS.KMSEncryptResult
public typealias KMSDecryptResult = CybKMS.KMSDecryptResult
public typealias KMSEncryptionAlgorithm = CybKMS.KMSEncryptionAlgorithm
public typealias KMSKeySpec = CybKMS.KMSKeySpec
public typealias KMSKeyUsage = CybKMS.KMSKeyUsage
public typealias KMSKeyState = CybKMS.KMSKeyState
public typealias KMSKeyMetadata = CybKMS.KMSKeyMetadata
public typealias KMSError = CybKMS.KMSError

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

private struct ScheduleKeyDeletionOutput: Decodable {
    let keyId: String
    let deletionDate: Date
    let keyState: KMSKeyState
}