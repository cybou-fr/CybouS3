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

            let input = ListFilesInput(
                bucketName: bucketName,
                prefix: prefix,
                delimiter: delimiter,
                vaultName: options.vault
            )

            let handler = ListFilesHandler(fileService: FileServices.shared.fileOperationsService)
            let result = try await handler.handle(input: input)

            if !json {
                print("Using vault: \(options.vault ?? "default") and bucket: \(bucketName)")
                if let prefix = prefix {
                    print("Filtering by prefix: \(prefix)")
                }
            }

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

                let fileInfos = result.objects.map { obj in
                    FileInfo(key: obj.key, size: obj.size, lastModified: obj.lastModified, isDirectory: obj.isDirectory)
                }
                let output = FilesOutput(objects: fileInfos, count: result.objects.count)
                let data = try encoder.encode(output)
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                if result.objects.isEmpty {
                    print("No objects found.")
                } else {
                    print("\nFound \(result.objects.count) object(s):")
                    print(String(repeating: "-", count: 60))
                    for object in result.objects {
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

            let input = CopyFileInput(
                bucketName: bucketName,
                sourceKey: sourceKey,
                destKey: destKey,
                vaultName: options.vault
            )

            let handler = CopyFileHandler(fileService: FileServices.shared.fileOperationsService)
            let result = try await handler.handle(input: input)

            if result.success {
                ConsoleUI.success(result.message)
            } else {
                ConsoleUI.error(result.message)
                throw ExitCode.failure
            }
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

            print("Using vault: \(options.vault ?? "default") and bucket: \(bucketName)")

            let progressBar = ConsoleUI.ProgressBar(title: "Downloading \(key)")

            let input = GetFileInput(
                bucketName: bucketName,
                key: key,
                localPath: localPath,
                vaultName: options.vault,
                progressCallback: { totalBytes in
                    // Update progress bar if we have file size
                    // The callback will be called with total bytes downloaded
                    // For now, we'll use indeterminate progress
                    let mb = Double(totalBytes) / 1024 / 1024
                    print(String(format: "\rDownloaded: %.2f MB", mb), terminator: "")
                }
            )

            let handler = GetFileHandler(fileService: FileServices.shared.fileOperationsService)
            let result = try await handler.handle(input: input)

            if result.fileSize != nil && result.fileSize! > 0 {
                progressBar.update(progress: Double(result.bytesDownloaded) / Double(result.fileSize!))
                progressBar.complete()
            } else {
                print() // New line after indeterminate progress
            }

            print(result.message)
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

            print("Using vault: \(options.vault ?? "default") and bucket: \(bucketName)")

            let progressBar = ConsoleUI.ProgressBar(title: "Uploading \(remoteKey)")

            let input = PutFileInput(
                bucketName: bucketName,
                localPath: localPath,
                remoteKey: remoteKey,
                dryRun: dryRun,
                vaultName: options.vault
            )

            let handler = PutFileHandler(fileService: FileServices.shared.fileOperationsService)
            let result = try await handler.handle(input: input)

            progressBar.complete()
            ConsoleUI.success(result.message)
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

            let input = DeleteFileInput(
                bucketName: bucketName,
                key: key,
                force: force,
                vaultName: options.vault
            )

            let handler = DeleteFileHandler(fileService: FileServices.shared.fileOperationsService)
            let result = try await handler.handle(input: input)

            if result.success {
                ConsoleUI.success(result.message)
            } else {
                ConsoleUI.error(result.message)
                throw ExitCode.failure
            }
        }
    }
}