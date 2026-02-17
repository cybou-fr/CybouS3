import Foundation
import Hummingbird

/// KMS API Controller - AWS KMS API-compatible HTTP endpoints
struct KMSController {
    let operations: KMSOperations

    /// Create key endpoint
    func createKey(_ request: Request, context: some RequestContext) async throws -> KMSKeyMetadata {
        let input: CreateKeyInput
        do {
            input = try await request.decode(as: CreateKeyInput.self, context: context)
        } catch {
            input = CreateKeyInput() // Default values
        }

        return try await operations.createKey(
            description: input.description,
            keyUsage: input.keyUsage ?? .encryptDecrypt
        )
    }

    /// Describe key endpoint
    func describeKey(_ request: Request, context: some RequestContext) async throws -> KMSKeyMetadata {
        let input = try await request.decode(as: DescribeKeyInput.self, context: context)
        return try await operations.describeKey(keyId: input.keyId)
    }

    /// List keys endpoint
    func listKeys(_ request: Request, context: some RequestContext) async throws -> ListKeysOutput {
        let keys = try await operations.listKeys()
        return ListKeysOutput(keys: keys)
    }

    /// Encrypt endpoint
    func encrypt(_ request: Request, context: some RequestContext) async throws -> KMSEncryptResult {
        let input = try await request.decode(as: EncryptInput.self, context: context)
        return try await operations.encrypt(
            plaintext: input.plaintext,
            keyId: input.keyId,
            encryptionAlgorithm: input.encryptionAlgorithm ?? .symmetricDefault,
            encryptionContext: input.encryptionContext
        )
    }

    /// Decrypt endpoint
    func decrypt(_ request: Request, context: some RequestContext) async throws -> KMSDecryptResult {
        let input = try await request.decode(as: DecryptInput.self, context: context)
        return try await operations.decrypt(
            ciphertextBlob: input.ciphertextBlob,
            encryptionAlgorithm: input.encryptionAlgorithm ?? .symmetricDefault,
            encryptionContext: input.encryptionContext,
            keyId: input.keyId
        )
    }

    /// Enable key endpoint
    func enableKey(_ request: Request, context: some RequestContext) async throws -> KMSKeyMetadata {
        let input = try await request.decode(as: EnableKeyInput.self, context: context)
        try await operations.enableKey(keyId: input.keyId)
        return try await operations.describeKey(keyId: input.keyId)
    }

    /// Disable key endpoint
    func disableKey(_ request: Request, context: some RequestContext) async throws -> KMSKeyMetadata {
        let input = try await request.decode(as: DisableKeyInput.self, context: context)
        try await operations.disableKey(keyId: input.keyId)
        return try await operations.describeKey(keyId: input.keyId)
    }

    /// Schedule key deletion endpoint
    func scheduleKeyDeletion(_ request: Request, context: some RequestContext) async throws -> ScheduleKeyDeletionOutput {
        let input = try await request.decode(as: ScheduleKeyDeletionInput.self, context: context)
        try await operations.scheduleKeyDeletion(keyId: input.keyId)
        return ScheduleKeyDeletionOutput(
            keyId: input.keyId,
            deletionDate: Date().addingTimeInterval(TimeInterval(input.pendingWindowInDays ?? 7) * 24 * 60 * 60)
        )
    }
}

// MARK: - API Input/Output Types

struct CreateKeyInput: Decodable {
    let description: String?
    let keyUsage: KMSKeyUsage?
    let keySpec: KMSKeySpec?

    init(description: String? = nil, keyUsage: KMSKeyUsage? = nil, keySpec: KMSKeySpec? = nil) {
        self.description = description
        self.keyUsage = keyUsage
        self.keySpec = keySpec
    }
}

struct DescribeKeyInput: Decodable {
    let keyId: String
}

struct ListKeysOutput: Encodable {
    let keys: [KMSKeyMetadata]
    let nextMarker: String?
    let truncated: Bool

    init(keys: [KMSKeyMetadata], nextMarker: String? = nil, truncated: Bool = false) {
        self.keys = keys
        self.nextMarker = nextMarker
        self.truncated = truncated
    }
}

struct EncryptInput: Decodable {
    let keyId: String
    let plaintext: Data
    let encryptionAlgorithm: KMSEncryptionAlgorithm?
    let encryptionContext: [String: String]?
    let grantTokens: [String]?
}

struct DecryptInput: Decodable {
    let ciphertextBlob: Data
    let encryptionAlgorithm: KMSEncryptionAlgorithm?
    let keyId: String?
    let encryptionContext: [String: String]?
    let grantTokens: [String]?
}

struct EnableKeyInput: Decodable {
    let keyId: String
}

struct DisableKeyInput: Decodable {
    let keyId: String
}

struct ScheduleKeyDeletionInput: Decodable {
    let keyId: String
    let pendingWindowInDays: Int?
}

struct ScheduleKeyDeletionOutput: Encodable {
    let keyId: String
    let deletionDate: Date
    let keyState: KMSKeyState = .pendingDeletion
}

// MARK: - Route Registration

extension RouterMethods {
    /// Register KMS API routes
    func registerKMSRoutes(controller: KMSController) {
        // Key Management
        post("/CreateKey", use: controller.createKey)
        post("/DescribeKey", use: controller.describeKey)
        post("/ListKeys", use: controller.listKeys)

        // Cryptographic Operations
        post("/Encrypt", use: controller.encrypt)
        post("/Decrypt", use: controller.decrypt)

        // Key State Management
        post("/EnableKey", use: controller.enableKey)
        post("/DisableKey", use: controller.disableKey)
        post("/ScheduleKeyDeletion", use: controller.scheduleKeyDeletion)
    }
}