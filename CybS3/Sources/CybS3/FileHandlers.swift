import Foundation
import CybS3Lib
import NIOCore

/// Input/output types for file operations
struct ListFilesInput {
    let bucketName: String
    let prefix: String?
    let delimiter: String?
    let vaultName: String?
}

struct ListFilesOutput {
    let objects: [S3Object]
    let success: Bool
    let message: String
}

struct GetFileInput {
    let bucketName: String
    let key: String
    let localPath: String?
    let vaultName: String?
    let progressCallback: ((Int) -> Void)?
}

struct GetFileOutput {
    let success: Bool
    let message: String
    let bytesDownloaded: Int
    let fileSize: Int64?
}

struct PutFileInput {
    let bucketName: String
    let localPath: String
    let remoteKey: String
    let dryRun: Bool
    let vaultName: String?
}

struct PutFileOutput {
    let success: Bool
    let message: String
    let bytesUploaded: Int64?
    let encryptedSize: Int64?
}

struct DeleteFileInput {
    let bucketName: String
    let key: String
    let force: Bool
    let vaultName: String?
}

struct DeleteFileOutput {
    let success: Bool
    let message: String
}

struct CopyFileInput {
    let bucketName: String
    let sourceKey: String
    let destKey: String
    let vaultName: String?
}

struct CopyFileOutput {
    let success: Bool
    let message: String
}

/// Service protocols for file operations
protocol FileOperationsServiceProtocol {
    func listFiles(input: ListFilesInput) async throws -> ListFilesOutput
    func getFile(input: GetFileInput) async throws -> GetFileOutput
    func putFile(input: PutFileInput) async throws -> PutFileOutput
    func deleteFile(input: DeleteFileInput) async throws -> DeleteFileOutput
    func copyFile(input: CopyFileInput) async throws -> CopyFileOutput
}

/// Default implementation using existing S3Client
class DefaultFileOperationsService: FileOperationsServiceProtocol {
    private struct ClientInfo {
        let client: S3Client
        let dataKey: SymmetricKey
        let config: EncryptedConfig
        let vaultName: String?
        let bucketName: String
    }

    private func createClient(bucket: String, vault: String?) throws -> ClientInfo {
        // Create a minimal GlobalOptions for client creation
        let options = GlobalOptions(
            vault: vault,
            accessKey: nil,
            secretKey: nil,
            endpoint: nil,
            region: nil,
            bucket: bucket
        )

        let (client, dataKey, config, vaultName, _) = try GlobalOptions.createClient(options, overrideBucket: bucket)

        return ClientInfo(
            client: client,
            dataKey: dataKey,
            config: config,
            vaultName: vaultName,
            bucketName: bucket
        )
    }
    func listFiles(input: ListFilesInput) async throws -> ListFilesOutput {
        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        defer { Task { try? await clientInfo.client.shutdown() } }

        let objects = try await clientInfo.client.listObjects(prefix: input.prefix, delimiter: input.delimiter)

        return ListFilesOutput(
            objects: objects,
            success: true,
            message: "Found \(objects.count) object(s)"
        )
    }

    func getFile(input: GetFileInput) async throws -> GetFileOutput {
        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        defer { Task { try? await clientInfo.client.shutdown() } }

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

        return GetFileOutput(
            success: true,
            message: "Downloaded \(input.key) to \(local)",
            bytesDownloaded: totalBytes,
            fileSize: fileSize
        )
    }

    func putFile(input: PutFileInput) async throws -> PutFileOutput {
        let fileURL = URL(fileURLWithPath: input.localPath)
        guard FileManager.default.fileExists(atPath: input.localPath) else {
            throw FileOperationError.fileNotFound(input.localPath)
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
        defer { Task { try? await clientInfo.client.shutdown() } }

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

        return PutFileOutput(
            success: true,
            message: "Uploaded \(input.localPath) as \(input.remoteKey)",
            bytesUploaded: fileSize,
            encryptedSize: encryptedSize
        )
    }

    func deleteFile(input: DeleteFileInput) async throws -> DeleteFileOutput {
        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        defer { Task { try? await clientInfo.client.shutdown() } }

        try await clientInfo.client.deleteObject(key: input.key)

        return DeleteFileOutput(
            success: true,
            message: "Deleted \(input.key)"
        )
    }

    func copyFile(input: CopyFileInput) async throws -> CopyFileOutput {
        let clientInfo = try createClient(bucket: input.bucketName, vault: input.vaultName)
        defer { Task { try? await clientInfo.client.shutdown() } }

        try await clientInfo.client.copyObject(sourceKey: input.sourceKey, destKey: input.destKey)

        return CopyFileOutput(
            success: true,
            message: "Copied '\(input.sourceKey)' to '\(input.destKey)'"
        )
    }
}

/// File operation errors
enum FileOperationError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

/// Command handlers using the service layer
struct ListFilesHandler: CommandHandler {
    typealias Input = ListFilesInput
    typealias Output = ListFilesOutput

    let fileService: FileOperationsServiceProtocol

    func handle(input: ListFilesInput) async throws -> ListFilesOutput {
        try await fileService.listFiles(input: input)
    }
}

struct GetFileHandler: CommandHandler {
    typealias Input = GetFileInput
    typealias Output = GetFileOutput

    let fileService: FileOperationsServiceProtocol

    func handle(input: GetFileInput) async throws -> GetFileOutput {
        try await fileService.getFile(input: input)
    }
}

struct PutFileHandler: CommandHandler {
    typealias Input = PutFileInput
    typealias Output = PutFileOutput

    let fileService: FileOperationsServiceProtocol

    func handle(input: PutFileInput) async throws -> PutFileOutput {
        try await fileService.putFile(input: input)
    }
}

struct DeleteFileHandler: CommandHandler {
    typealias Input = DeleteFileInput
    typealias Output = DeleteFileOutput

    let fileService: FileOperationsServiceProtocol

    func handle(input: DeleteFileInput) async throws -> DeleteFileOutput {
        try await fileService.deleteFile(input: input)
    }
}

struct CopyFileHandler: CommandHandler {
    typealias Input = CopyFileInput
    typealias Output = CopyFileOutput

    let fileService: FileOperationsServiceProtocol

    func handle(input: CopyFileInput) async throws -> CopyFileOutput {
        try await fileService.copyFile(input: input)
    }
}

/// Dependency container for file services
class FileServices {
    static let shared = FileServices()

    lazy var fileOperationsService: FileOperationsServiceProtocol = DefaultFileOperationsService()
}