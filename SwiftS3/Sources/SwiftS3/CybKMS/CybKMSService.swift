import Crypto
import Foundation

/// CybKMS - Pure Swift implementation of AWS KMS API-compatible key management
/// Provides server-side encryption capabilities without external dependencies

// MARK: - KMS API Types (AWS-compatible)

/// Result of a KMS encrypt operation
public struct KMSEncryptResult: Sendable {
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
public struct KMSDecryptResult: Sendable {
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

/// KMS encryption algorithms
public enum KMSEncryptionAlgorithm: String, Codable, Sendable {
    case symmetricDefault = "SYMMETRIC_DEFAULT"
}

/// KMS key specification
public enum KMSKeySpec: String, Codable, Sendable {
    case symmetricDefault = "SYMMETRIC_DEFAULT"
}

/// KMS key usage
public enum KMSKeyUsage: String, Codable, Sendable {
    case encryptDecrypt = "ENCRYPT_DECRYPT"
}

/// KMS key state
public enum KMSKeyState: String, Codable, Sendable {
    case enabled = "Enabled"
    case disabled = "Disabled"
    case pendingDeletion = "PendingDeletion"
    case pendingImport = "PendingImport"
    case unavailable = "Unavailable"
}

/// KMS key metadata
public struct KMSKeyMetadata: Sendable, Codable {
    public let keyId: String
    public let arn: String
    public let description: String?
    public let keyUsage: KMSKeyUsage
    public let keyState: KMSKeyState
    public let keySpec: KMSKeySpec
    public let creationDate: Date
    public let enabled: Bool

    public init(keyId: String, arn: String, description: String? = nil, keyUsage: KMSKeyUsage = .encryptDecrypt,
                keyState: KMSKeyState = .enabled, keySpec: KMSKeySpec = .symmetricDefault,
                creationDate: Date = Date(), enabled: Bool = true) {
        self.keyId = keyId
        self.arn = arn
        self.description = description
        self.keyUsage = keyUsage
        self.keyState = keyState
        self.keySpec = keySpec
        self.creationDate = creationDate
        self.enabled = enabled
    }
}

/// KMS error types (AWS-compatible)
public enum KMSError: Error, LocalizedError, Equatable {
    case notFoundException(String)
    case accessDeniedException(String)
    case invalidKeyUsageException(String)
    case keyUnavailableException(String)
    case invalidCiphertextException(String)
    case throttlingException
    case internalException(String)
    case invalidGrantTokenException(String)
    case invalidKeyIdException(String)

    public var errorDescription: String? {
        switch self {
        case .notFoundException(let message):
            return "KMS key not found: \(message)"
        case .accessDeniedException(let message):
            return "Access denied to KMS key: \(message)"
        case .invalidKeyUsageException(let message):
            return "Invalid key usage: \(message)"
        case .keyUnavailableException(let message):
            return "Key unavailable: \(message)"
        case .invalidCiphertextException(let message):
            return "Invalid ciphertext: \(message)"
        case .throttlingException:
            return "KMS request throttled"
        case .internalException(let message):
            return "Internal KMS error: \(message)"
        case .invalidGrantTokenException(let message):
            return "Invalid grant token: \(message)"
        case .invalidKeyIdException(let message):
            return "Invalid key ID: \(message)"
        }
    }
}

// MARK: - CybKMS Service

/// Pure Swift KMS-compatible key management service
/// Stores keys locally and provides AWS KMS API-compatible operations
public actor CybKMSService {
    private var keys: [String: KMSKeyEntry] = [:]
    private let keyStorePath: String
    private let region: String

    /// Initialize CybKMS service
    /// - Parameters:
    ///   - region: AWS region (for ARN generation)
    ///   - keyStorePath: Path to store key metadata (optional, defaults to in-memory)
    public init(region: String = "us-east-1", keyStorePath: String? = nil) async throws {
        self.region = region
        self.keyStorePath = keyStorePath ?? ""

        if let path = keyStorePath {
            try await loadKeyStore(from: path)
        }
    }

    // MARK: - Key Management

    /// Create a new KMS key
    public func createKey(description: String? = nil, keyUsage: KMSKeyUsage = .encryptDecrypt) async throws -> KMSKeyMetadata {
        let keyId = generateKeyId()
        let arn = generateKeyArn(keyId: keyId)

        // Generate a new 256-bit AES key
        let keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }

        let keyEntry = KMSKeyEntry(
            keyId: keyId,
            arn: arn,
            keyData: keyData,
            metadata: KMSKeyMetadata(
                keyId: keyId,
                arn: arn,
                description: description,
                keyUsage: keyUsage,
                creationDate: Date()
            )
        )

        keys[keyId] = keyEntry

        if !keyStorePath.isEmpty {
            try await saveKeyStore(to: keyStorePath)
        }

        return keyEntry.metadata
    }

    /// Describe a KMS key
    public func describeKey(keyId: String) async throws -> KMSKeyMetadata {
        guard let keyEntry = keys[keyId] else {
            throw KMSError.notFoundException("Key '\(keyId)' not found")
        }
        return keyEntry.metadata
    }

    /// List KMS keys
    public func listKeys() async throws -> [KMSKeyMetadata] {
        return keys.values.map { $0.metadata }
    }

    /// Delete a KMS key (schedule for deletion)
    public func scheduleKeyDeletion(keyId: String, pendingWindowInDays: Int = 7) async throws {
        guard var keyEntry = keys[keyId] else {
            throw KMSError.notFoundException("Key '\(keyId)' not found")
        }

        // Mark key as pending deletion
        keyEntry.metadata = KMSKeyMetadata(
            keyId: keyEntry.metadata.keyId,
            arn: keyEntry.metadata.arn,
            description: keyEntry.metadata.description,
            keyUsage: keyEntry.metadata.keyUsage,
            keyState: .pendingDeletion,
            keySpec: keyEntry.metadata.keySpec,
            creationDate: keyEntry.metadata.creationDate,
            enabled: false
        )

        keys[keyId] = keyEntry

        if !keyStorePath.isEmpty {
            try await saveKeyStore(to: keyStorePath)
        }
    }

    /// Enable a KMS key
    public func enableKey(keyId: String) async throws {
        guard var keyEntry = keys[keyId] else {
            throw KMSError.notFoundException("Key '\(keyId)' not found")
        }

        keyEntry.metadata = KMSKeyMetadata(
            keyId: keyEntry.metadata.keyId,
            arn: keyEntry.metadata.arn,
            description: keyEntry.metadata.description,
            keyUsage: keyEntry.metadata.keyUsage,
            keyState: .enabled,
            keySpec: keyEntry.metadata.keySpec,
            creationDate: keyEntry.metadata.creationDate,
            enabled: true
        )

        keys[keyId] = keyEntry

        if !keyStorePath.isEmpty {
            try await saveKeyStore(to: keyStorePath)
        }
    }

    /// Disable a KMS key
    public func disableKey(keyId: String) async throws {
        guard var keyEntry = keys[keyId] else {
            throw KMSError.notFoundException("Key '\(keyId)' not found")
        }

        keyEntry.metadata = KMSKeyMetadata(
            keyId: keyEntry.metadata.keyId,
            arn: keyEntry.metadata.arn,
            description: keyEntry.metadata.description,
            keyUsage: keyEntry.metadata.keyUsage,
            keyState: .disabled,
            keySpec: keyEntry.metadata.keySpec,
            creationDate: keyEntry.metadata.creationDate,
            enabled: false
        )

        keys[keyId] = keyEntry

        if !keyStorePath.isEmpty {
            try await saveKeyStore(to: keyStorePath)
        }
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
        guard let keyEntry = keys[keyId] else {
            throw KMSError.notFoundException("Key '\(keyId)' not found")
        }

        guard keyEntry.metadata.enabled && keyEntry.metadata.keyState == .enabled else {
            throw KMSError.keyUnavailableException("Key '\(keyId)' is not enabled")
        }

        // Generate a random nonce for AES-GCM
        let nonce = AES.GCM.Nonce()

        // Encrypt the data
        let symmetricKey = SymmetricKey(data: keyEntry.keyData)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonce)

        // Create ciphertext blob: nonce + encrypted data + tag
        let ciphertextBlob = sealedBox.combined!

        return KMSEncryptResult(
            ciphertextBlob: ciphertextBlob,
            keyId: keyEntry.metadata.keyId,
            arn: keyEntry.metadata.arn,
            encryptionAlgorithm: encryptionAlgorithm
        )
    }

    /// Decrypt data using a KMS key
    public func decrypt(
        ciphertextBlob: Data,
        encryptionAlgorithm: KMSEncryptionAlgorithm = .symmetricDefault,
        encryptionContext: [String: String]? = nil,
        grantTokens: [String]? = nil,
        keyId: String? = nil
    ) async throws -> KMSDecryptResult {
        // For CybKMS, we need to determine the key from the ciphertext
        // In a real implementation, we'd store key metadata with the ciphertext
        // For now, we'll try all keys (this is not efficient for production)

        var lastError: Error?

        for (_, keyEntry) in keys {
            if let specifiedKeyId = keyId, specifiedKeyId != keyEntry.metadata.keyId {
                continue
            }

            guard keyEntry.metadata.enabled && keyEntry.metadata.keyState == .enabled else {
                continue
            }

            do {
                let symmetricKey = SymmetricKey(data: keyEntry.keyData)
                let sealedBox = try AES.GCM.SealedBox(combined: ciphertextBlob)
                let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

                return KMSDecryptResult(
                    plaintext: plaintext,
                    keyId: keyEntry.metadata.keyId,
                    arn: keyEntry.metadata.arn,
                    encryptionAlgorithm: encryptionAlgorithm
                )
            } catch {
                lastError = error
                continue
            }
        }

        throw KMSError.invalidCiphertextException("Unable to decrypt ciphertext with available keys")
    }

    // MARK: - Key Aliases

    /// Create an alias for a KMS key
    public func createAlias(aliasName: String, targetKeyId: String) async throws {
        guard keys[targetKeyId] != nil else {
            throw KMSError.notFoundException("Key '\(targetKeyId)' not found")
        }

        // Store alias mapping (simplified - in production would be persistent)
        // For now, we'll just validate the alias format
        guard aliasName.hasPrefix("alias/") else {
            throw KMSError.invalidKeyIdException("Alias name must start with 'alias/'")
        }
    }

    /// Delete an alias
    public func deleteAlias(aliasName: String) async throws {
        // Simplified implementation
        guard aliasName.hasPrefix("alias/") else {
            throw KMSError.invalidKeyIdException("Invalid alias name")
        }
    }

    // MARK: - Private Methods

    private func generateKeyId() -> String {
        // Generate a UUID-like key ID
        return UUID().uuidString.lowercased()
    }

    private func generateKeyArn(keyId: String) -> String {
        return "arn:aws:kms:\(region):123456789012:key/\(keyId)"
    }

    private func loadKeyStore(from path: String) async throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return // No existing keystore
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let keyStore = try decoder.decode([String: KMSKeyEntry].self, from: data)
        keys = keyStore
    }

    private func saveKeyStore(to path: String) async throws {
        let url = URL(fileURLWithPath: path)
        let encoder = JSONEncoder()
        let data = try encoder.encode(keys)
        try data.write(to: url)
    }
}

// MARK: - Private Types

private struct KMSKeyEntry: Codable {
    let keyId: String
    let arn: String
    let keyData: Data
    var metadata: KMSKeyMetadata
}