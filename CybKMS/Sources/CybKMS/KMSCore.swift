import AsyncHTTPClient
import Crypto
import Foundation
import Hummingbird
import Logging
import SQLiteNIO
import _NIOFileSystem

/// CybKMS - Standalone AWS KMS API-compatible server
/// Pure Swift implementation providing enterprise-grade key management

// MARK: - KMS API Types (AWS-compatible)

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
public struct KMSKeyMetadata: Codable, Sendable {
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
public enum KMSError: Error, Codable {
    case notFoundException(String)
    case accessDeniedException(String)
    case invalidKeyUsageException(String)
    case keyUnavailableException(String)
    case invalidCiphertextException(String)
    case throttlingException
    case internalException(String)
    case invalidGrantTokenException(String)
    case invalidKeyIdException(String)

    private enum CodingKeys: String, CodingKey {
        case type, message
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notFoundException(let message):
            try container.encode("NotFoundException", forKey: .type)
            try container.encode(message, forKey: .message)
        case .accessDeniedException(let message):
            try container.encode("AccessDeniedException", forKey: .type)
            try container.encode(message, forKey: .message)
        case .invalidKeyUsageException(let message):
            try container.encode("InvalidKeyUsageException", forKey: .type)
            try container.encode(message, forKey: .message)
        case .keyUnavailableException(let message):
            try container.encode("KeyUnavailableException", forKey: .type)
            try container.encode(message, forKey: .message)
        case .invalidCiphertextException(let message):
            try container.encode("InvalidCiphertextException", forKey: .type)
            try container.encode(message, forKey: .message)
        case .throttlingException:
            try container.encode("ThrottlingException", forKey: .type)
            try container.encode("Request throttled", forKey: .message)
        case .internalException(let message):
            try container.encode("InternalException", forKey: .type)
            try container.encode(message, forKey: .message)
        case .invalidGrantTokenException(let message):
            try container.encode("InvalidGrantTokenException", forKey: .type)
            try container.encode(message, forKey: .message)
        case .invalidKeyIdException(let message):
            try container.encode("InvalidKeyIdException", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let message = try container.decode(String.self, forKey: .message)

        switch type {
        case "NotFoundException":
            self = .notFoundException(message)
        case "AccessDeniedException":
            self = .accessDeniedException(message)
        case "InvalidKeyUsageException":
            self = .invalidKeyUsageException(message)
        case "KeyUnavailableException":
            self = .keyUnavailableException(message)
        case "InvalidCiphertextException":
            self = .invalidCiphertextException(message)
        case "ThrottlingException":
            self = .throttlingException
        case "InternalException":
            self = .internalException(message)
        case "InvalidGrantTokenException":
            self = .invalidGrantTokenException(message)
        case "InvalidKeyIdException":
            self = .invalidKeyIdException(message)
        default:
            self = .internalException("Unknown error type: \(type)")
        }
    }
}

// MARK: - Key Storage

/// In-memory key storage with persistence
actor KMSKeyStore {
    private var keys: [String: KMSKeyEntry] = [:]
    private let persistencePath: String?
    private let logger = Logger(label: "CybKMS.KeyStore")

    init(persistencePath: String? = nil) async throws {
        self.persistencePath = persistencePath
        if let path = persistencePath {
            try await loadKeys(from: path)
        }
    }

    func createKey(description: String? = nil, keyUsage: KMSKeyUsage = .encryptDecrypt) async throws -> KMSKeyMetadata {
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

        if let path = persistencePath {
            try await saveKeys(to: path)
        }

        logger.info("Created new KMS key", metadata: ["keyId": keyId])
        return keyEntry.metadata
    }

    func getKey(_ keyId: String) throws -> KMSKeyEntry {
        guard let keyEntry = keys[keyId] else {
            throw KMSError.notFoundException("Key '\(keyId)' not found")
        }
        return keyEntry
    }

    func listKeys() -> [KMSKeyMetadata] {
        return keys.values.map { $0.metadata }
    }

    func updateKeyState(_ keyId: String, state: KMSKeyState) async throws {
        guard var keyEntry = keys[keyId] else {
            throw KMSError.notFoundException("Key '\(keyId)' not found")
        }

        keyEntry.metadata = KMSKeyMetadata(
            keyId: keyEntry.metadata.keyId,
            arn: keyEntry.metadata.arn,
            description: keyEntry.metadata.description,
            keyUsage: keyEntry.metadata.keyUsage,
            keyState: state,
            keySpec: keyEntry.metadata.keySpec,
            creationDate: keyEntry.metadata.creationDate,
            enabled: state == .enabled
        )

        keys[keyId] = keyEntry

        if let path = persistencePath {
            try await saveKeys(to: path)
        }

        logger.info("Updated key state", metadata: ["keyId": keyId, "state": state.rawValue])
    }

    func deleteKey(_ keyId: String) async throws {
        guard keys[keyId] != nil else {
            throw KMSError.notFoundException("Key '\(keyId)' not found")
        }

        keys.removeValue(forKey: keyId)

        if let path = persistencePath {
            try await saveKeys(to: path)
        }

        logger.info("Deleted KMS key", metadata: ["keyId": keyId])
    }

    private func generateKeyId() -> String {
        return UUID().uuidString.lowercased()
    }

    private func generateKeyArn(keyId: String) -> String {
        return "arn:cyb:kms:local:000000000000:key/\(keyId)"
    }

    private func loadKeys(from path: String) async throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return // No existing keystore
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let keyStore = try decoder.decode([String: KMSKeyEntry].self, from: data)
        keys = keyStore
        logger.info("Loaded keys from persistence", metadata: ["count": "\(keys.count)"])
    }

    private func saveKeys(to path: String) async throws {
        let url = URL(fileURLWithPath: path)
        let encoder = JSONEncoder()
        let data = try encoder.encode(keys)
        try data.write(to: url)
        logger.debug("Saved keys to persistence", metadata: ["count": "\(keys.count)"])
    }
}

/// Internal key entry structure
struct KMSKeyEntry: Codable {
    let keyId: String
    let arn: String
    let keyData: Data
    var metadata: KMSKeyMetadata
}

// MARK: - KMS Operations

/// Core KMS operations
actor KMSOperations {
    private let keyStore: KMSKeyStore
    private let logger = Logger(label: "CybKMS.Operations")

    init(keyStore: KMSKeyStore) {
        self.keyStore = keyStore
    }

    func encrypt(plaintext: Data, keyId: String, encryptionAlgorithm: KMSEncryptionAlgorithm = .symmetricDefault,
                 encryptionContext: [String: String]? = nil) async throws -> KMSEncryptResult {
        let keyEntry = try keyStore.getKey(keyId)

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

        logger.debug("Encrypted data", metadata: ["keyId": keyId, "size": "\(plaintext.count)"])

        return KMSEncryptResult(
            ciphertextBlob: ciphertextBlob,
            keyId: keyEntry.metadata.keyId,
            arn: keyEntry.metadata.arn,
            encryptionAlgorithm: encryptionAlgorithm
        )
    }

    func decrypt(ciphertextBlob: Data, encryptionAlgorithm: KMSEncryptionAlgorithm = .symmetricDefault,
                 encryptionContext: [String: String]? = nil, keyId: String? = nil) async throws -> KMSDecryptResult {
        // If keyId is provided, use it directly
        if let specifiedKeyId = keyId {
            let keyEntry = try keyStore.getKey(specifiedKeyId)

            guard keyEntry.metadata.enabled && keyEntry.metadata.keyState == .enabled else {
                throw KMSError.keyUnavailableException("Key '\(specifiedKeyId)' is not enabled")
            }

            let symmetricKey = SymmetricKey(data: keyEntry.keyData)
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertextBlob)
            let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

            logger.debug("Decrypted data", metadata: ["keyId": specifiedKeyId, "size": "\(plaintext.count)"])

            return KMSDecryptResult(
                plaintext: plaintext,
                keyId: keyEntry.metadata.keyId,
                arn: keyEntry.metadata.arn,
                encryptionAlgorithm: encryptionAlgorithm
            )
        }

        // Otherwise, try all keys (this is not efficient for production)
        var lastError: Error?

        for (_, keyEntry) in await keyStore.listKeys().map({ ($0.keyId, try! keyStore.getKey($0.keyId)) }) {
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

                logger.debug("Decrypted data", metadata: ["keyId": keyEntry.metadata.keyId, "size": "\(plaintext.count)"])

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

    func describeKey(keyId: String) async throws -> KMSKeyMetadata {
        let keyEntry = try keyStore.getKey(keyId)
        return keyEntry.metadata
    }

    func listKeys() async throws -> [KMSKeyMetadata] {
        return keyStore.listKeys()
    }

    func createKey(description: String? = nil, keyUsage: KMSKeyUsage = .encryptDecrypt) async throws -> KMSKeyMetadata {
        return try await keyStore.createKey(description: description, keyUsage: keyUsage)
    }

    func enableKey(keyId: String) async throws {
        try await keyStore.updateKeyState(keyId, state: .enabled)
    }

    func disableKey(keyId: String) async throws {
        try await keyStore.updateKeyState(keyId, state: .disabled)
    }

    func scheduleKeyDeletion(keyId: String) async throws {
        try await keyStore.updateKeyState(keyId, state: .pendingDeletion)
    }
}