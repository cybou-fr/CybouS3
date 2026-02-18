import Foundation
import Crypto

/// Input for file upload operations
public struct FileUploadInput {
    public let bucketName: String
    public let localPath: String
    public let remoteKey: String
    public let dryRun: Bool
    public let vaultName: String?

    public init(bucketName: String, localPath: String, remoteKey: String, dryRun: Bool = false, vaultName: String?) {
        self.bucketName = bucketName
        self.localPath = localPath
        self.remoteKey = remoteKey
        self.dryRun = dryRun
        self.vaultName = vaultName
    }
}

/// Output for file upload operations
public struct FileUploadOutput {
    public let success: Bool
    public let message: String
    public let bytesUploaded: Int64?
    public let encryptedSize: Int64?
    public let checksum: String?

    public init(success: Bool, message: String, bytesUploaded: Int64? = nil, encryptedSize: Int64? = nil, checksum: String? = nil) {
        self.success = success
        self.message = message
        self.bytesUploaded = bytesUploaded
        self.encryptedSize = encryptedSize
        self.checksum = checksum
    }
}

/// Protocol for S3 client operations needed by file handlers
public protocol FileHandlerS3ClientProtocol {
    func putObject(bucket: String, key: String, data: Data, metadata: [String: String]?) async throws
    func getObject(bucket: String, key: String) async throws -> Data
    func deleteObject(bucket: String, key: String) async throws
    func headObject(bucket: String, key: String) async throws -> [String: String]
}

/// Protocol for encryption services used by file handlers
public protocol FileHandlerEncryptionServiceProtocol {
    func encrypt(data: Data) async throws -> (encryptedData: Data, checksum: String)
    func decrypt(data: Data) async throws -> Data
}

/// File upload handler implementing the Command Handler pattern
public struct FileUploadHandler: CommandHandler {
    public typealias Input = FileUploadInput
    public typealias Output = FileUploadOutput

    private let s3Client: FileHandlerS3ClientProtocol
    private let encryptionService: FileHandlerEncryptionServiceProtocol
    private let fileManager: FileManager

    public init(s3Client: FileHandlerS3ClientProtocol, encryptionService: FileHandlerEncryptionServiceProtocol, fileManager: FileManager = .default) {
        self.s3Client = s3Client
        self.encryptionService = encryptionService
        self.fileManager = fileManager
    }

    public func handle(input: FileUploadInput) async throws -> FileUploadOutput {
        // Validate input
        guard fileManager.fileExists(atPath: input.localPath) else {
            return FileUploadOutput(
                success: false,
                message: "Local file does not exist: \(input.localPath)"
            )
        }

        // Get file attributes
        let attributes = try fileManager.attributesOfItem(atPath: input.localPath)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Dry run mode
        if input.dryRun {
            return FileUploadOutput(
                success: true,
                message: "Dry run: Would upload \(input.localPath) (\(fileSize) bytes) to \(input.bucketName)/\(input.remoteKey)",
                bytesUploaded: fileSize
            )
        }

        do {
            // Read file data
            let fileData = try Data(contentsOf: URL(fileURLWithPath: input.localPath))

            // Encrypt the data
            let (encryptedData, checksum) = try await encryptionService.encrypt(data: fileData)

            // Prepare metadata
            var metadata: [String: String] = [
                "original-filename": (input.localPath as NSString).lastPathComponent,
                "upload-timestamp": ISO8601DateFormatter().string(from: Date()),
                "file-size": String(fileSize),
                "checksum": checksum
            ]

            if let vaultName = input.vaultName {
                metadata["vault"] = vaultName
            }

            // Upload to S3
            try await s3Client.putObject(
                bucket: input.bucketName,
                key: input.remoteKey,
                data: encryptedData,
                metadata: metadata
            )

            return FileUploadOutput(
                success: true,
                message: "Successfully uploaded \(input.localPath) to \(input.bucketName)/\(input.remoteKey)",
                bytesUploaded: fileSize,
                encryptedSize: Int64(encryptedData.count),
                checksum: checksum
            )

        } catch let error as FileUploadError {
            return FileUploadOutput(
                success: false,
                message: "Encryption failed: \(error.localizedDescription)"
            )
        } catch let error as S3Error {
            return FileUploadOutput(
                success: false,
                message: "S3 upload failed: \(error.localizedDescription)"
            )
        } catch {
            return FileUploadOutput(
                success: false,
                message: "Upload failed: \(error.localizedDescription)"
            )
        }
    }
}

/// File upload operation error types
public enum FileUploadError: LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keyNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .encryptionFailed(let reason):
            return "Encryption failed: \(reason)"
        case .decryptionFailed(let reason):
            return "Decryption failed: \(reason)"
        case .keyNotFound(let keyId):
            return "Encryption key not found: \(keyId)"
        }
    }
}

/// S3 error types for file operations
public enum FileOperationError: LocalizedError {
    case accessDenied
    case noSuchBucket
    case noSuchKey
    case invalidBucketName
    case invalidObjectName
    case bucketAlreadyExists
    case bucketNotEmpty
    case networkError(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access denied"
        case .noSuchBucket:
            return "The specified bucket does not exist"
        case .noSuchKey:
            return "The specified key does not exist"
        case .invalidBucketName:
            return "Invalid bucket name"
        case .invalidObjectName:
            return "Invalid object name"
        case .bucketAlreadyExists:
            return "Bucket already exists"
        case .bucketNotEmpty:
            return "Bucket is not empty"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .unknown(let reason):
            return "Unknown error: \(reason)"
        }
    }
}