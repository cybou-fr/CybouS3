import ArgumentParser
import AsyncHTTPClient
import CybS3Lib
import Foundation
import NIOCore

/// File management commands
struct FileCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "files",
        abstract: "Manage files in S3 buckets",
        subcommands: [
            List.self,
            Get.self,
            Put.self,
            Delete.self,
            Copy.self,
        ]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List files in a bucket"
        )

        @OptionGroup var options: GlobalOptions

        @Option(name: .shortAndLong, help: "Filter by prefix (folder path)")
        var prefix: String?

        @Option(name: .shortAndLong, help: "Delimiter for grouping (e.g., '/')")
        var delimiter: String?

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        func run() async throws {
            var bucketName: String
            if let b = options.bucket {
                bucketName = b
            } else {
                bucketName = try InteractionService.promptForBucket()
            }
            let (client, _, _, vaultName, _) = try GlobalOptions.createClient(
                options, overrideBucket: bucketName)
            defer { Task { try? await client.shutdown() } }

            if !json {
                print("Using vault: \(vaultName ?? "default") and bucket: \(bucketName)")
                if let prefix = prefix {
                    print("Filtering by prefix: \(prefix)")
                }
            }

            let objects = try await client.listObjects(prefix: prefix, delimiter: delimiter)

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601

                struct FileInfo: Encodable {
                    let key: String
                    let size: Int
                    let lastModified: Date
                    let isDirectory: Bool
                }

                struct FilesOutput: Encodable {
                    let objects: [FileInfo]
                    let count: Int
                }

                let fileInfos = objects.map { obj in
                    FileInfo(key: obj.key, size: obj.size, lastModified: obj.lastModified, isDirectory: obj.isDirectory)
                }
                let output = FilesOutput(objects: fileInfos, count: objects.count)
                let data = try encoder.encode(output)
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                if objects.isEmpty {
                    print("No objects found.")
                } else {
                    print("\nFound \(objects.count) object(s):")
                    print(String(repeating: "-", count: 60))
                    for object in objects {
                        print(object)
                    }
                }
            }
        }
    }

    struct Copy: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "copy",
            abstract: "Copy a file within S3"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Source file key")
        var sourceKey: String

        @Argument(help: "Destination file key")
        var destKey: String

        func run() async throws {
            var bucketName: String
            if let b = options.bucket {
                bucketName = b
            } else {
                bucketName = try InteractionService.promptForBucket()
            }
            let (client, _, _, vaultName, _) = try GlobalOptions.createClient(
                options, overrideBucket: bucketName)
            defer { Task { try? await client.shutdown() } }
            print("Using vault: \(vaultName ?? "default") and bucket: \(bucketName)")

            try await client.copyObject(sourceKey: sourceKey, destKey: destKey)
            print("✅ Copied '\(sourceKey)' to '\(destKey)'")
        }
    }

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Download a file from a bucket"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Remote file key")
        var key: String

        @Argument(help: "Local file path")
        var localPath: String?

        func run() async throws {
            var bucketName: String
            if let b = options.bucket {
                bucketName = b
            } else {
                bucketName = try InteractionService.promptForBucket()
            }
            let (client, dataKey, _, vaultName, _) = try GlobalOptions.createClient(
                options, overrideBucket: bucketName)
            defer { Task { try? await client.shutdown() } }
            print("Using vault: \(vaultName ?? "default") and bucket: \(bucketName)")
            let local = localPath ?? key
            let outputPath = local
            let outputURL = URL(fileURLWithPath: outputPath)

            _ = FileManager.default.createFile(atPath: outputPath, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: outputURL)
            defer { try? fileHandle.close() }

            // Get file size for progress bar
            let fileSize = try await client.getObjectSize(key: key) ?? 0
            let progressBar = ConsoleUI.ProgressBar(title: "Downloading \(key)")

            let encryptedStream = try await client.getObjectStream(key: key)
            let decryptedStream = StreamingEncryption.DecryptedStream(
                upstream: encryptedStream, key: dataKey)

            var totalBytes = 0

            for try await chunk in decryptedStream {
                totalBytes += chunk.count

                if fileSize > 0 {
                    progressBar.update(progress: Double(totalBytes) / Double(fileSize))
                } else {
                    // Indeterminate progress if size unknown
                    let mb = Double(totalBytes) / 1024 / 1024
                    print(String(format: "\rDownloaded: %.2f MB", mb), terminator: "")
                }

                if #available(macOS 10.15.4, *) {
                    try fileHandle.seekToEnd()
                } else {
                    fileHandle.seekToEndOfFile()
                }
                fileHandle.write(chunk)
            }

            if fileSize > 0 {
                progressBar.complete()
            } else {
                print()
            }

            print("Downloaded \(key) to \(local)")
        }
    }

    struct Put: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "put",
            abstract: "Upload a file to a bucket"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Local file path")
        var localPath: String

        @Argument(help: "Remote file key")
        var key: String?

        @Flag(name: .long, help: "Show what would be uploaded without actually uploading")
        var dryRun: Bool = false

        func run() async throws {
            var bucketName: String
            if let b = options.bucket {
                bucketName = b
            } else {
                bucketName = try InteractionService.promptForBucket()
            }

            let fileURL = URL(fileURLWithPath: localPath)
            guard FileManager.default.fileExists(atPath: localPath) else {
                ConsoleUI.error("File not found: \(localPath)")
                throw ExitCode.failure
            }

            let remoteKey = key ?? (localPath as NSString).lastPathComponent

            let fileSize =
                try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
                ?? 0

            // Calculate encrypted size using the helper
            let encryptedSize = StreamingEncryption.encryptedSize(plaintextSize: fileSize)

            // Dry-run mode
            if dryRun {
                print()
                ConsoleUI.header("Dry Run - Upload Preview")
                ConsoleUI.keyValue("Source:", localPath)
                ConsoleUI.keyValue("Destination:", "s3://\(bucketName)/\(remoteKey)")
                ConsoleUI.keyValue("Original size:", formatBytes(Int(fileSize)))
                ConsoleUI.keyValue("Encrypted size:", formatBytes(Int(encryptedSize)))
                ConsoleUI.keyValue("Overhead:", formatBytes(Int(encryptedSize - fileSize)))
                print()
                ConsoleUI.success("No changes made (dry-run mode)")
                return
            }

            let (client, dataKey, _, vaultName, _) = try GlobalOptions.createClient(
                options, overrideBucket: bucketName)
            defer { Task { try? await client.shutdown() } }
            print("Using vault: \(vaultName ?? "default") and bucket: \(bucketName)")

            let progressBar = ConsoleUI.ProgressBar(title: "Uploading \(remoteKey)")

            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }

            // Track bytes read. Using a class to allow capture in closure.
            class ProgressTracker: @unchecked Sendable {
                var totalBytes: Int64 = 0
            }
            let tracker = ProgressTracker()

            // Custom AsyncSequence to report progress
            let progressStream = FileHandleAsyncSequence(
                fileHandle: fileHandle,
                chunkSize: StreamingEncryption.chunkSize,
                progress: { bytesRead in
                    tracker.totalBytes += Int64(bytesRead)
                    progressBar.update(progress: Double(tracker.totalBytes) / Double(fileSize))
                }
            )

            // Encrypt using INTERNAL Data Key
            let encryptedStream = StreamingEncryption.EncryptedStream(
                upstream: progressStream, key: dataKey)

            let uploadStream = encryptedStream.map { ByteBuffer(data: $0) }

            try await client.putObject(
                key: remoteKey, stream: uploadStream, length: encryptedSize)

            progressBar.complete()
            ConsoleUI.success("Uploaded \(localPath) as \(remoteKey)")
        }

        private func formatBytes(_ bytes: Int) -> String {
            let units = ["B", "KB", "MB", "GB", "TB"]
            var size = Double(bytes)
            var unitIndex = 0

            while size >= 1024 && unitIndex < units.count - 1 {
                size /= 1024
                unitIndex += 1
            }

            return String(format: "%.2f %@", size, units[unitIndex])
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a file from a bucket"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "File key to delete")
        var key: String

        @Flag(name: .shortAndLong, help: "Force delete without confirmation")
        var force: Bool = false

        func run() async throws {
            var bucketName: String
            if let b = options.bucket {
                bucketName = b
            } else {
                bucketName = try InteractionService.promptForBucket()
            }

            if !force {
                ConsoleUI.warning("You are about to delete '\(key)' from bucket '\(bucketName)'.")
                guard InteractionService.confirm(message: "Are you sure?", defaultValue: false) else {
                    ConsoleUI.info("Operation cancelled.")
                    return
                }
            }

            let (client, _, _, vaultName, _) = try GlobalOptions.createClient(
                options, overrideBucket: bucketName)
            defer { Task { try? await client.shutdown() } }
            ConsoleUI.dim("Using vault: \(vaultName ?? "default") and bucket: \(bucketName)")
            try await client.deleteObject(key: key)
            ConsoleUI.success("Deleted \(key)")
        }
    }
}