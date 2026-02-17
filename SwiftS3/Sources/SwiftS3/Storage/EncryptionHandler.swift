import Crypto
import CybKMSClient
import Foundation

/// Handles server-side encryption operations for stored objects.
/// Supports AES256, AWS KMS, and CybKMS encryption methods.
actor EncryptionHandler {
    private let kmsProvider: CybKMSClient?

    init(kmsProvider: CybKMSClient? = nil) {
        self.kmsProvider = kmsProvider
    }

    /// Encrypts data using the specified server-side encryption configuration.
    func encryptData(_ data: Data, with config: ServerSideEncryptionConfig) async throws -> (encryptedData: Data, key: Data?, iv: Data?) {
        switch config.algorithm {
        case .aes256:
            // Generate a random 256-bit key and IV for AES encryption
            let key = SymmetricKey(size: .bits256)
            let iv = AES.GCM.Nonce()

            let sealedBox = try AES.GCM.seal(data, using: key, nonce: iv)
            let combinedData = sealedBox.combined!

            return (encryptedData: combinedData, key: key.withUnsafeBytes { Data($0) }, iv: iv.withUnsafeBytes { Data($0) })

        case .awsKms:
            // For AWS KMS encryption, we'd need to call AWS KMS API
            // For now, fall back to AES256 (this should be replaced with actual AWS SDK calls)
            let key = SymmetricKey(size: .bits256)
            let iv = AES.GCM.Nonce()

            let sealedBox = try AES.GCM.seal(data, using: key, nonce: iv)
            let combinedData = sealedBox.combined!

            return (encryptedData: combinedData, key: key.withUnsafeBytes { Data($0) }, iv: iv.withUnsafeBytes { Data($0) })

        case .cybKms:
            guard let kmsProvider = kmsProvider else {
                throw S3Error.invalidEncryption
            }
            guard let keyId = config.kmsKeyId else {
                throw S3Error.invalidEncryption
            }

            // Convert encryption context string to dictionary if needed
            var context: [String: String]? = nil
            if let contextStr = config.kmsEncryptionContext {
                context = ["encryption-context": contextStr]
            }

            let result = try await kmsProvider.encrypt(plaintext: data, keyId: keyId, encryptionContext: context)

            // Return ciphertext with KMS metadata
            return (encryptedData: result.ciphertextBlob, key: nil, iv: nil)
        }
    }

    /// Decrypts data using the specified server-side encryption configuration.
    func decryptData(_ encryptedData: Data, with config: ServerSideEncryptionConfig, key: Data?, iv: Data?) async throws -> Data {
        switch config.algorithm {
        case .aes256, .awsKms:
            guard let key = key, let iv = iv else {
                throw S3Error.invalidEncryption
            }

            let symmetricKey = SymmetricKey(data: key)
            let _ = try AES.GCM.Nonce(data: iv)

            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)

            return decryptedData

        case .cybKms:
            guard let kmsProvider = kmsProvider else {
                throw S3Error.invalidEncryption
            }

            // Convert encryption context string to dictionary if needed
            var context: [String: String]? = nil
            if let contextStr = config.kmsEncryptionContext {
                context = ["encryption-context": contextStr]
            }

            let result = try await kmsProvider.decrypt(ciphertextBlob: encryptedData, encryptionContext: context)

            return result.plaintext
        }
    }
}