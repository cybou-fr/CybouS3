import Foundation
import Foundation
import NIOCore
import Crypto

/// Input/output types for file operations
public struct ListFilesInput {
    public let bucketName: String
    public let prefix: String?
    public let delimiter: String?
    public let vaultName: String?

    public init(bucketName: String, prefix: String?, delimiter: String?, vaultName: String?) {
        self.bucketName = bucketName
        self.prefix = prefix
        self.delimiter = delimiter
        self.vaultName = vaultName
    }
}

public struct ListFilesOutput {
    public let objects: [S3Object]
    public let success: Bool
    public let message: String
}

public struct GetFileInput {
    public let bucketName: String
    public let key: String
    public let localPath: String?
    public let vaultName: String?
    public let progressCallback: ((Int) -> Void)?

    public init(bucketName: String, key: String, localPath: String?, vaultName: String?, progressCallback: ((Int) -> Void)?) {
        self.bucketName = bucketName
        self.key = key
        self.localPath = localPath
        self.vaultName = vaultName
        self.progressCallback = progressCallback
    }
}

public struct GetFileOutput {
    public let success: Bool
    public let message: String
    public let bytesDownloaded: Int
    public let fileSize: Int64?
}

public struct PutFileInput {
    public let bucketName: String
    public let localPath: String
    public let remoteKey: String
    public let dryRun: Bool
    public let vaultName: String?

    public init(bucketName: String, localPath: String, remoteKey: String, dryRun: Bool, vaultName: String?) {
        self.bucketName = bucketName
        self.localPath = localPath
        self.remoteKey = remoteKey
        self.dryRun = dryRun
        self.vaultName = vaultName
    }
}

public struct PutFileOutput {
    public let success: Bool
    public let message: String
    public let bytesUploaded: Int64?
    public let encryptedSize: Int64?
}

public struct DeleteFileInput {
    public let bucketName: String
    public let key: String
    public let force: Bool
    public let vaultName: String?

    public init(bucketName: String, key: String, force: Bool, vaultName: String?) {
        self.bucketName = bucketName
        self.key = key
        self.force = force
        self.vaultName = vaultName
    }
}

public struct DeleteFileOutput {
    public let success: Bool
    public let message: String
}

public struct CopyFileInput {
    public let bucketName: String
    public let sourceKey: String
    public let destKey: String
    public let vaultName: String?

    public init(bucketName: String, sourceKey: String, destKey: String, vaultName: String?) {
        self.bucketName = bucketName
        self.sourceKey = sourceKey
        self.destKey = destKey
        self.vaultName = vaultName
    }
}

public struct CopyFileOutput {
    public let success: Bool
    public let message: String
}

/// Service protocols for file operations
public protocol FileOperationsServiceProtocol {
    func listFiles(input: ListFilesInput) async throws -> ListFilesOutput
    func getFile(input: GetFileInput) async throws -> GetFileOutput
    func putFile(input: PutFileInput) async throws -> PutFileOutput
    func deleteFile(input: DeleteFileInput) async throws -> DeleteFileOutput
    func copyFile(input: CopyFileInput) async throws -> CopyFileOutput
}

/// Default implementation using existing S3Client
public class DefaultFileOperationsService: FileOperationsServiceProtocol {
    public init() {}
    private struct ClientInfo {
        let client: S3Client
        let dataKey: SymmetricKey
        let config: EncryptedConfig
        let vaultName: String?
        let bucketName: String
    }

    private func createClient(bucket: String, vault: String?) throws -> ClientInfo {
        // TODO: Refactor to not depend on GlobalOptions
        // For now, create a mock client for compilation
        let mockConfig = EncryptedConfig(
            dataKey: Data(repeating: 0x01, count: 32),
            vaults: [VaultConfig(
                name: vault ?? "default",
                endpoint: "https://mock.endpoint.com",
                accessKey: "mock-key",
                secretKey: "mock-secret",
                region: "us-east-1",
                bucket: bucket
            )],
            settings: AppSettings()
        )
        
        let mockClient = S3Client(
            endpoint: S3Endpoint(host: "mock.endpoint.com", port: 443, useSSL: true),
            accessKey: "mock-key",
            secretKey: "mock-secret",
            bucket: bucket,
            region: "us-east-1"
        )
        
        return ClientInfo(
            client: mockClient,
            dataKey: SymmetricKey(data: Data(repeating: 0x01, count: 32)),
            config: mockConfig,
            vaultName: vault,
            bucketName: bucket
        )
    }
    public func listFiles(input: ListFilesInput) async throws -> ListFilesOutput {
        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        
        do {
            let objects = try await clientInfo.client.listObjects(prefix: input.prefix, delimiter: input.delimiter)
            return ListFilesOutput(
                objects: objects,
                success: true,
                message: "Found \(objects.count) object(s)"
            )
        }
        try? await clientInfo.client.shutdown()
    }

    public func getFile(input: GetFileInput) async throws -> GetFileOutput {
        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        
        do {
            let local = input.localPath ?? input.key
            let outputURL = URL(fileURLWithPath: local)

            _ = FileManager.default.createFile(atPath: local, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: outputURL)
            defer { try? fileHandle.close() }

            // Get file size for progress reporting
            let fileSize = try await clientInfo.client.getObjectSize(key: input.key)

            let encryptedStream = try await clientInfo.client.getObjectStream(key: input.key)
            let decryptedStream = StreamingEncryption.DecryptedStream(
                upstream: encryptedStream, key: clientInfo.dataKey)

            var totalBytes = 0

            for try await chunk in decryptedStream {
                totalBytes += chunk.count
                input.progressCallback?(totalBytes)

                if #available(macOS 10.15.4, *) {
                    try fileHandle.seekToEnd()
                } else {
                    fileHandle.seekToEndOfFile()
                }
                fileHandle.write(chunk)
            }

            let result = GetFileOutput(
                success: true,
                message: "Downloaded \(input.key) to \(local)",
                bytesDownloaded: totalBytes,
                fileSize: fileSize.map { Int64($0) }
            )
            return result
        } catch {
            try? await clientInfo.client.shutdown()
            throw error
        }
        try? await clientInfo.client.shutdown()
    }

    public func putFile(input: PutFileInput) async throws -> PutFileOutput {
        let fileURL = URL(fileURLWithPath: input.localPath)
        guard FileManager.default.fileExists(atPath: input.localPath) else {
            throw FileHandlerError.fileNotFound(input.localPath)
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
        let encryptedSize = StreamingEncryption.encryptedSize(plaintextSize: fileSize)

        if input.dryRun {
            return PutFileOutput(
                success: true,
                message: "Dry run - no changes made",
                bytesUploaded: nil,
                encryptedSize: encryptedSize
            )
        }

        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        
        do {

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        // Custom AsyncSequence to track progress
        let progressStream = FileHandleAsyncSequence(
            fileHandle: fileHandle,
            chunkSize: StreamingEncryption.chunkSize,
            progress: { _ in } // Progress handled by caller
        )

        // Encrypt using INTERNAL Data Key
        let encryptedStream = StreamingEncryption.EncryptedStream(
            upstream: progressStream, key: clientInfo.dataKey)

        let uploadStream = encryptedStream.map { ByteBuffer(data: $0) }

        try await clientInfo.client.putObject(
            key: input.remoteKey, stream: uploadStream, length: encryptedSize)

        let result = PutFileOutput(
            success: true,
            message: "Uploaded \(input.localPath) as \(input.remoteKey)",
            bytesUploaded: fileSize,
            encryptedSize: encryptedSize
        )
        return result
        } catch {
            try? await clientInfo.client.shutdown()
            throw error
        }
        try? await clientInfo.client.shutdown()
    }

    public func deleteFile(input: DeleteFileInput) async throws -> DeleteFileOutput {
        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        
        do {
            try await clientInfo.client.deleteObject(key: input.key)

            let result = DeleteFileOutput(
                success: true,
                message: "Deleted \(input.key)"
            )
            return result
        } catch {
            try? await clientInfo.client.shutdown()
            throw error
        }
        try? await clientInfo.client.shutdown()
    }

    public func copyFile(input: CopyFileInput) async throws -> CopyFileOutput {
        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        
        do {
            try await clientInfo.client.copyObject(sourceKey: input.sourceKey, destKey: input.destKey)

            let result = CopyFileOutput(
                success: true,
                message: "Copied '\(input.sourceKey)' to '\(input.destKey)'"
            )
            return result
        } catch {
            try? await clientInfo.client.shutdown()
            throw error
        }
        try? await clientInfo.client.shutdown()
    }
}

/// File operation errors
enum FileHandlerError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

/// Command handlers using the service layer
public struct ListFilesHandler: CommandHandler {
    public typealias Input = ListFilesInput
    public typealias Output = ListFilesOutput

    public let fileService: FileOperationsServiceProtocol

    public init(fileService: FileOperationsServiceProtocol) {
        self.fileService = fileService
    }

    public func handle(input: ListFilesInput) async throws -> ListFilesOutput {
        try await fileService.listFiles(input: input)
    }
}

public struct GetFileHandler: CommandHandler {
    public typealias Input = GetFileInput
    public typealias Output = GetFileOutput

    public let fileService: FileOperationsServiceProtocol

    public init(fileService: FileOperationsServiceProtocol) {
        self.fileService = fileService
    }

    public func handle(input: GetFileInput) async throws -> GetFileOutput {
        try await fileService.getFile(input: input)
    }
}

public struct PutFileHandler: CommandHandler {
    public typealias Input = PutFileInput
    public typealias Output = PutFileOutput

    public let fileService: FileOperationsServiceProtocol

    public init(fileService: FileOperationsServiceProtocol) {
        self.fileService = fileService
    }

    public func handle(input: PutFileInput) async throws -> PutFileOutput {
        try await fileService.putFile(input: input)
    }
}

public struct DeleteFileHandler: CommandHandler {
    public typealias Input = DeleteFileInput
    public typealias Output = DeleteFileOutput

    public let fileService: FileOperationsServiceProtocol

    public init(fileService: FileOperationsServiceProtocol) {
        self.fileService = fileService
    }

    public func handle(input: DeleteFileInput) async throws -> DeleteFileOutput {
        try await fileService.deleteFile(input: input)
    }
}

public struct CopyFileHandler: CommandHandler {
    public typealias Input = CopyFileInput
    public typealias Output = CopyFileOutput

    public let fileService: FileOperationsServiceProtocol

    public init(fileService: FileOperationsServiceProtocol) {
        self.fileService = fileService
    }

    public func handle(input: CopyFileInput) async throws -> CopyFileOutput {
        try await fileService.copyFile(input: input)
    }
}

/// Dependency container for file services
public class FileServices {
    @MainActor
    public static let shared = FileServices()

    public lazy var fileOperationsService: FileOperationsServiceProtocol = DefaultFileOperationsService()
}