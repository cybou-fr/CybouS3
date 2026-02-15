import ArgumentParser
import AsyncHTTPClient
import Crypto
import CybS3Lib
import Foundation
import NIO
import SwiftBIP39

/// Global options available to all subcommands.
struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Vault name")
    var vault: String?

    @Option(name: .shortAndLong, help: "S3 endpoint URL")
    var endpoint: String?

    @Option(name: .shortAndLong, help: "Access key")
    var accessKey: String?

    @Option(name: .shortAndLong, help: "Secret key")
    var secretKey: String?

    @Option(name: .shortAndLong, help: "Bucket name")
    var bucket: String?

    @Option(name: .shortAndLong, help: "Region")
    var region: String?

    @Flag(name: .long, inversion: .prefixedNo, help: "Use SSL")
    var ssl: Bool = true

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Enable server-side encryption (SSE-KMS)")
    var sseKms: Bool = false

    @Option(name: .long, help: "KMS key ID for server-side encryption")
    var kmsKeyId: String?

    /// Creates a configured `S3Client`, resolving settings from CLI args, Environment variables, and the persisted Configuration.
    ///
    /// This method performs the following steps:
    /// 1. Prompts for the Master Key (Mnemonic) to unlock the encrypted configuration.
    /// 2. Loads the encrypted configuration and derives the Data Key.
    /// 3. Resolves S3 settings (Endpoint, Credentials, Region) with the hierarchy: CLI Args > Env Vars > Config.
    ///
    /// - Important: The caller is responsible for calling `client.shutdown()` when done to release HTTP resources.
    ///   Use `defer { try? await client.shutdown() }` after obtaining the client.
    static func createClient(_ options: GlobalOptions, overrideBucket: String? = nil) throws -> (
        S3Client, SymmetricKey, EncryptedConfig, String?, String?
    ) {
        // 1. Get Mnemonic (Environment > Keychain > Prompt)
        let mnemonic: [String]

        if let envMnemonic = ProcessInfo.processInfo.environment["CYBS3_MNEMONIC"] {
            mnemonic = envMnemonic.components(separatedBy: .whitespacesAndNewlines).filter {
                !$0.isEmpty
            }
        } else if let storedMnemonic = KeychainService.load() {
            // Determine if this is an interactive context or if we should be silent?
            // For now, if it's in Keychain, we use it transparently.
            mnemonic = storedMnemonic
        } else {
            mnemonic = try InteractionService.promptForMnemonic(
                purpose: "unlock configuration (or run 'cybs3 login' first)")
        }

        // 2. Load Config & Data Key
        let (config, dataKey) = try StorageService.load(mnemonic: mnemonic)

        // 3. Determine vault settings
        let vaultConfig: VaultConfig?
        if let vaultName = options.vault {
            guard let v = config.vaults.first(where: { $0.name == vaultName }) else {
                print(
                    "Vault '\(vaultName)' not found. Available vaults: \(config.vaults.map { $0.name }.joined(separator: ", "))"
                )
                throw ExitCode.failure
            }
            vaultConfig = v
        } else if let activeName = config.activeVaultName,
            let v = config.vaults.first(where: { $0.name == activeName })
        {
            vaultConfig = v
        } else {
            vaultConfig = nil  // use global settings
        }

        // 4. Resolve S3 settings
        // Hierarchy: CLI Args -> Env Vars -> Vault -> Config Settings

        let envAccessKey = ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"]
        let envSecretKey = ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"]
        let envRegion = ProcessInfo.processInfo.environment["AWS_REGION"]
        let envBucket = ProcessInfo.processInfo.environment["AWS_BUCKET"]

        let finalAccessKey =
            options.accessKey ?? envAccessKey ?? vaultConfig?.accessKey ?? config.settings
            .defaultAccessKey ?? ""
        let finalSecretKey =
            options.secretKey ?? envSecretKey ?? vaultConfig?.secretKey ?? config.settings
            .defaultSecretKey ?? ""

        // Default region logic
        let configRegion = vaultConfig?.region ?? config.settings.defaultRegion
        let finalRegion =
            options.region != nil ? options.region! : (envRegion ?? configRegion ?? "us-east-1")

        let finalBucket =
            overrideBucket ?? envBucket ?? vaultConfig?.bucket ?? config.settings.defaultBucket

        // Endpoint logic
        var host = vaultConfig?.endpoint ?? config.settings.defaultEndpoint ?? "s3.amazonaws.com"
        if let e = options.endpoint {
            host = e
        }

        // Parse host/port/ssl from string
        let endpointString = host.contains("://") ? host : "https://\(host)"
        guard let url = URL(string: endpointString) else {
            throw ExitCode.failure  // Invalid URL
        }

        let s3Endpoint = S3Endpoint(
            host: url.host ?? host,
            port: url.port ?? (url.scheme == "http" ? 80 : 443),
            useSSL: url.scheme == "https"
        )

        let client = S3Client(
            endpoint: s3Endpoint,
            accessKey: finalAccessKey,
            secretKey: finalSecretKey,
            bucket: finalBucket,
            region: finalRegion,
            sseKms: options.sseKms,
            kmsKeyId: options.kmsKeyId
        )

        return (client, dataKey, config, vaultConfig?.name, finalBucket)
    }
}

/// The main entry point for the CybS3 Command Line Interface.
///
/// CybS3 provides an S3-compatible object storage browser with client-side encryption capabilities.
@main
/// The main entry point for the CybS3 Command Line Interface.
///
/// CybS3 provides an S3-compatible object storage browser with client-side encryption capabilities.
struct CybS3CLI: AsyncParsableCommand {
}

extension CybS3CLI {
    static let configuration = CommandConfiguration(
        commandName: "cybs3",
        abstract: "S3 Compatible Object Storage Browser",
        subcommands: [
            Buckets.self,
            Files.self,
            Folders.self,
            Config.self,
            Health.self,
            Login.self,
            Logout.self,
            Keys.self,
            Performance.self,
            Server.self,
            Test.self,
            Vaults.self,
        ]
    )
}
    
    // MARK: - Login Command (NEW)

    /// Command to log in (store mnemonic in Keychain).
    struct Login: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "login",
            abstract: "Authenticate and store your mnemonic securely in Keychain"
        )

        func run() async throws {
            ConsoleUI.header("Login to CybS3")
            ConsoleUI.info(
                "This will store your mnemonic in the system Keychain for seamless access."
            )
            print()

            do {
                let mnemonic = try InteractionService.promptForMnemonic(purpose: "login")

                // Verify it works by trying to load config
                // If it's a new user, load() creates a new config.
                // If existing user, load() checks if it decrypts.
                _ = try StorageService.load(mnemonic: mnemonic)

                try KeychainService.save(mnemonic: mnemonic)
                ConsoleUI.success("Login successful. Mnemonic stored securely in Keychain.")
                ConsoleUI.dim("You can now run commands without entering your mnemonic.")
            } catch let error as InteractionError {
                CLIError.from(error).printError()
                throw ExitCode.failure
            } catch let error as StorageError {
                CLIError.from(error).printError()
                throw ExitCode.failure
            } catch let error as KeychainError {
                ConsoleUI.error("Keychain error: \(error.localizedDescription)")
                throw ExitCode.failure
            } catch {
                ConsoleUI.error("Login failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Login Command (NEW)

    /// Command to log out (remove mnemonic from Keychain).
    struct Logout: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logout",
            abstract: "Remove your mnemonic from Keychain"
        )

        func run() async throws {
            do {
                try KeychainService.delete()
                ConsoleUI.success("Logout successful. Mnemonic removed from Keychain.")
            } catch KeychainError.itemNotFound {
                ConsoleUI.warning("No active session found. Already logged out.")
            } catch {
                ConsoleUI.error("Logout failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Buckets Command Group

    struct Buckets: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "buckets",
            abstract: "Manage S3 buckets",
            subcommands: [
                Create.self,
                List.self,
            ]
        )

        struct Create: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "create",
                abstract: "Create a new bucket"
            )

            @OptionGroup var options: GlobalOptions

            @Argument(help: "Bucket name")
            var bucketName: String

            func run() async throws {
                do {
                    let (client, _, _, vaultName, _) = try GlobalOptions.createClient(
                        options, overrideBucket: bucketName)
                    defer { Task { try? await client.shutdown() } }
                    ConsoleUI.dim("Using vault: \(vaultName ?? "default")")
                    try await client.createBucket(name: bucketName)
                    ConsoleUI.success("Created bucket: \(bucketName)")
                } catch let error as S3Error {
                    ConsoleUI.error(error.localizedDescription)
                    throw ExitCode.failure
                }
            }
        }
        
        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete",
                abstract: "Delete an empty bucket"
            )

            @OptionGroup var options: GlobalOptions

            @Argument(help: "Bucket name to delete")
            var bucketName: String
            
            @Flag(name: .shortAndLong, help: "Force delete without confirmation")
            var force: Bool = false

            func run() async throws {
                if !force {
                    ConsoleUI.warning("You are about to delete bucket '\(bucketName)'. This cannot be undone.")
                    guard InteractionService.confirm(message: "Are you sure?", defaultValue: false) else {
                        ConsoleUI.info("Operation cancelled.")
                        return
                    }
                }
                
                do {
                    let (client, _, _, vaultName, _) = try GlobalOptions.createClient(options)
                    defer { Task { try? await client.shutdown() } }
                    ConsoleUI.dim("Using vault: \(vaultName ?? "default")")
                    try await client.deleteBucket(name: bucketName)
                    ConsoleUI.success("Deleted bucket: \(bucketName)")
                } catch let error as S3Error {
                    ConsoleUI.error(error.localizedDescription)
                    throw ExitCode.failure
                }
            }
        }

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List all buckets"
            )

            @OptionGroup var options: GlobalOptions
            
            @Flag(name: .long, help: "Output as JSON")
            var json: Bool = false

            func run() async throws {
                let (client, _, _, vaultName, _) = try GlobalOptions.createClient(options)
                defer { Task { try? await client.shutdown() } }
                if !json {
                    print("Using vault: \(vaultName ?? "default")")
                }
                let buckets = try await client.listBuckets()

                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(["buckets": buckets])
                    print(String(data: data, encoding: .utf8) ?? "[]")
                } else {
                    print("Buckets:")
                    for bucket in buckets {
                        print("  \(bucket)")
                    }
                }
            }
        }
    }

    // MARK: - Files Command Group

    struct Files: AsyncParsableCommand {
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

    // MARK: - Config Command

    /// Command to update the local configuration (default region, bucket, keys, etc.).
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "config",
            abstract: "Configure CybS3 settings"
        )

        @Option(name: .shortAndLong, help: "Set access key")
        var accessKey: String?

        @Option(name: .shortAndLong, help: "Set secret key")
        var secretKey: String?

        @Option(name: .shortAndLong, help: "Set default endpoint")
        var endpoint: String?

        @Option(name: .shortAndLong, help: "Set default region")
        var region: String?

        @Option(name: .shortAndLong, help: "Set default bucket")
        var bucket: String?

        func run() async throws {
            // Check keychain first, else prompt
            let mnemonic: [String]
            if let stored = KeychainService.load() {
                mnemonic = stored
            } else {
                mnemonic = try InteractionService.promptForMnemonic(purpose: "update configuration")
            }

            var (config, _) = try StorageService.load(mnemonic: mnemonic)

            var changed = false
            if let accessKey = accessKey {
                config.settings.defaultAccessKey = accessKey
                changed = true
            }
            if let secretKey = secretKey {
                config.settings.defaultSecretKey = secretKey
                changed = true
            }
            if let endpoint = endpoint {
                config.settings.defaultEndpoint = endpoint
                changed = true
            }
            if let region = region {
                config.settings.defaultRegion = region
                changed = true
            }
            if let bucket = bucket {
                config.settings.defaultBucket = bucket
                changed = true
            }

            if changed {
                try StorageService.save(config, mnemonic: mnemonic)
                print("Configuration saved.")
            } else {
                print("No changes made.")
            }
        }
    }

    // MARK: - Health Command

    /// Command to perform system health checks.
    struct Health: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "health",
            abstract: "Perform system health checks",
            subcommands: [Check.self]
        )

        struct Check: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "check",
                abstract: "Run comprehensive system diagnostics"
            )

            @Option(name: .long, help: "Check specific component (encryption, network, storage)")
            var component: String?

            @Flag(name: .long, help: "Verbose output")
            var verbose: Bool = false

            func run() async throws {
                print("🔍 Performing CybS3 health check...")

                let status = await HealthChecker.performHealthCheck()

                print("\n\(status.description)")

                if verbose || !status.isHealthy {
                    print("\n📊 Details:")
                    switch status {
                    case .healthy(let details):
                        for (component, info) in details.sorted(by: { $0.key < $1.key }) {
                            print("  ✅ \(component): \(info)")
                        }
                    case .degraded(let details, let issues), .unhealthy(let details, let issues):
                        for (component, info) in details.sorted(by: { $0.key < $1.key }) {
                            print("  📋 \(component): \(info)")
                        }
                        if !issues.isEmpty {
                            print("\n⚠️ Issues found:")
                            for issue in issues {
                                print("  • \(issue)")
                            }
                        }
                    }
                }

                print("\n💡 For more information, run with --verbose")
            }
        }
    }

    // MARK: - Performance Command

    /// Command to run performance benchmarks.
    struct Performance: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "performance",
            abstract: "Run performance benchmarks",
            subcommands: [Benchmark.self]
        )

        struct Benchmark: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "benchmark",
                abstract: "Run comprehensive performance tests"
            )

            @Option(name: .long, help: "Test duration in seconds")
            var duration: Int = 30

            @Option(name: .long, help: "Number of concurrent operations")
            var concurrency: Int = 4

            @Option(name: .long, help: "File size for tests (KB)")
            var fileSize: Int = 1024

            @Flag(name: .long, help: "Run against SwiftS3 server")
            var swiftS3: Bool = false

            @Option(name: .long, help: "SwiftS3 server endpoint")
            var endpoint: String = "http://127.0.0.1:8080"

            @Option(name: .long, help: "Test bucket for SwiftS3")
            var bucket: String = "benchmark-bucket"

            func run() async throws {
                if swiftS3 {
                    print("🏃 Running CybS3 performance benchmarks against SwiftS3...")
                    print("   Endpoint: \(endpoint)")
                    print("   Bucket: \(bucket)")
                    print("   Duration: \(duration)s")
                    print("   Concurrency: \(concurrency)")
                    print("   File size: \(fileSize)KB")

                    // Start SwiftS3 if not running
                    let serverProcess = Process()
                    serverProcess.executableURL = URL(fileURLWithPath: "../SwiftS3/.build/release/SwiftS3")
                    serverProcess.arguments = ["server", "--hostname", "127.0.0.1", "--port", "8080", "--storage", "/tmp/swifts3-benchmark", "--access-key", "admin", "--secret-key", "password"]
                    
                    let outputPipe = Pipe()
                    serverProcess.standardOutput = outputPipe
                    serverProcess.standardError = outputPipe
                    serverProcess.terminationHandler = { _ in
                        print("🛑 SwiftS3 server stopped")
                    }

                    try serverProcess.run()
                    print("🚀 SwiftS3 server started for benchmarking")
                    
                    // Wait for server to start
                    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

                    // Create bucket
                    let createProcess = Process()
                    createProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                    createProcess.arguments = ["buckets", "create", bucket, "--endpoint", endpoint, "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
                    try createProcess.run()
                    await createProcess.waitUntilExit()

                    // Run benchmark operations
                    try await runSwiftS3Benchmark(duration: duration, concurrency: concurrency, fileSize: fileSize, bucket: bucket, endpoint: endpoint)

                    // Stop server
                    serverProcess.terminate()
                    await serverProcess.waitUntilExit()
                    
                    print("\n✅ SwiftS3 benchmark complete")
                } else {
                    print("🏃 Running CybS3 performance benchmarks...")
                    print("   Duration: \(duration)s")
                    print("   Concurrency: \(concurrency)")
                    print("   File size: \(fileSize)KB")

                    // This would run actual benchmarks, but for now just show placeholder
                    print("\n📊 Performance Benchmark Results:")
                    print("   ⚠️  Note: Full benchmarks require S3 credentials")
                    print("   💡 Run integration tests with credentials for real benchmarks")

                    // Could integrate with PerformanceBenchmarks.swift test methods
                    print("\n✅ Benchmark setup complete")
                    print("💡 Use 'swift test --filter PerformanceBenchmarks' for detailed benchmarks")
                }
            }

            private func runSwiftS3Benchmark(duration: Int, concurrency: Int, fileSize: Int, bucket: String, endpoint: String) async throws {
                print("\n📊 Running SwiftS3 Load Test...")
                
                // Create test data
                let testData = Data(repeating: 0x41, count: fileSize * 1024) // 'A' repeated
                
                let startTime = Date()
                var operations = 0
                
                // Run concurrent uploads
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for i in 0..<concurrency {
                        group.addTask {
                            while Date().timeIntervalSince(startTime) < Double(duration) {
                                let key = "benchmark-\(i)-\(operations).dat"
                                
                                let uploadProcess = Process()
                                uploadProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                                uploadProcess.arguments = ["files", "put", "-", key, "--bucket", bucket, "--endpoint", endpoint, "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
                                
                                let inputPipe = Pipe()
                                uploadProcess.standardInput = inputPipe
                                
                                try uploadProcess.run()
                                
                                // Write test data to stdin
                                try inputPipe.fileHandleForWriting.write(contentsOf: testData)
                                try inputPipe.fileHandleForWriting.close()
                                
                                await uploadProcess.waitUntilExit()
                                
                                if uploadProcess.terminationStatus == 0 {
                                    operations += 1
                                }
                            }
                        }
                    }
                    
                    try await group.waitForAll()
                }
                
                let elapsed = Date().timeIntervalSince(startTime)
                let opsPerSecond = Double(operations) / elapsed
                let throughput = Double(operations * fileSize) / elapsed / 1024.0 // KB/s
                
                print("📈 Results:")
                print("   Operations: \(operations)")
                print("   Duration: \(String(format: "%.2f", elapsed))s")
                print("   Ops/sec: \(String(format: "%.2f", opsPerSecond))")
                print("   Throughput: \(String(format: "%.2f", throughput)) KB/s")
            }
        }
    }

    // MARK: - Server Command

    struct Server: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "server",
            abstract: "Manage SwiftS3 server instances",
            subcommands: [
                Start.self,
                Stop.self,
                Status.self,
                Config.self,
            ]
        )

        struct Start: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "start",
                abstract: "Start a SwiftS3 server instance"
            )

            @Option(name: .long, help: "SwiftS3 executable path")
            var swifts3Path: String = "../SwiftS3/.build/release/SwiftS3"

            @Option(name: .shortAndLong, help: "Port to bind to")
            var port: Int = 8080

            @Option(name: .shortAndLong, help: "Hostname to bind to")
            var hostname: String = "127.0.0.1"

            @Option(name: .long, help: "Storage directory path")
            var storage: String = "./data"

            @Option(name: .customLong("access-key"), help: "AWS Access Key ID")
            var accessKey: String = "admin"

            @Option(name: .customLong("secret-key"), help: "AWS Secret Access Key")
            var secretKey: String = "password"

            @Flag(name: .long, help: "Run in background")
            var background: Bool = false

            func run() async throws {
                print("🚀 Starting SwiftS3 server...")
                print("   Host: \(hostname):\(port)")
                print("   Storage: \(storage)")
                print("   Access Key: \(accessKey)")

                let process = Process()
                process.executableURL = URL(fileURLWithPath: swifts3Path)
                process.arguments = [
                    "server",
                    "--hostname", hostname,
                    "--port", "\(port)",
                    "--storage", storage,
                    "--access-key", accessKey,
                    "--secret-key", secretKey
                ]

                if background {
                    // Save PID for later stop command
                    let pidFile = "/tmp/swifts3-\(port).pid"
                    process.terminationHandler = { _ in
                        try? FileManager.default.removeItem(atPath: pidFile)
                    }

                    try process.run()
                    try "\(process.processIdentifier)".write(toFile: pidFile, atomically: true, encoding: .utf8)
                    print("✅ Server started in background (PID: \(process.processIdentifier))")
                    print("💡 Use 'cybs3 server stop --port \(port)' to stop")
                } else {
                    let outputPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = outputPipe

                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        print("✅ Server stopped gracefully")
                    } else {
                        print("❌ Server exited with code \(process.terminationStatus)")
                    }
                }
            }
        }

        struct Stop: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "stop",
                abstract: "Stop a running SwiftS3 server instance"
            )

            @Option(name: .shortAndLong, help: "Port of the server to stop")
            var port: Int = 8080

            func run() async throws {
                let pidFile = "/tmp/swifts3-\(port).pid"
                guard let pidString = try? String(contentsOfFile: pidFile),
                      let pid = Int(pidString) else {
                    print("❌ No server found running on port \(port)")
                    return
                }

                print("🛑 Stopping SwiftS3 server on port \(port) (PID: \(pid))")

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["\(pid)"]

                try process.run()
                process.waitUntilExit()

                try? FileManager.default.removeItem(atPath: pidFile)
                print("✅ Server stopped")
            }
        }

        struct Status: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "status",
                abstract: "Check status of SwiftS3 server instances"
            )

            @Option(name: .shortAndLong, help: "Port to check")
            var port: Int = 8080

            func run() async throws {
                let pidFile = "/tmp/swifts3-\(port).pid"
                if let pidString = try? String(contentsOfFile: pidFile),
                   let pid = Int(pidString) {
                    print("✅ SwiftS3 server running on port \(port) (PID: \(pid))")

                    // Try to connect and get basic info
                    do {
                        let url = URL(string: "http://127.0.0.1:\(port)/")!
                        let (_, response) = try await URLSession.shared.data(from: url)
                        if let httpResponse = response as? HTTPURLResponse {
                            print("   Status: \(httpResponse.statusCode)")
                        }
                    } catch {
                        print("   Status: Unable to connect")
                    }
                } else {
                    print("❌ No SwiftS3 server running on port \(port)")
                }
            }
        }

        struct Config: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "config",
                abstract: "Show SwiftS3 server configuration"
            )

            func run() async throws {
                print("🔧 SwiftS3 Server Configuration:")
                print("   Default Host: 127.0.0.1:8080")
                print("   Default Storage: ./data")
                print("   Default Credentials: admin/password")
                print("   Enterprise Features: SSE-KMS, Versioning, Lifecycle")
                print("💡 Use 'cybs3 server start --help' for all options")
            }
        }
    }

    // MARK: - Test Command

    struct Test: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Run integration tests with SwiftS3 server",
            subcommands: [
                Integration.self,
                // SecurityTests.self, // TODO: Fix reference
            ]
        )

        struct Integration: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "integration",
                abstract: "Run basic integration tests"
            )

            @Option(name: .long, help: "SwiftS3 executable path")
            var swifts3Path: String = "../SwiftS3/.build/release/SwiftS3"

            @Option(name: .long, help: "Test bucket name")
            var bucket: String = "test-bucket"

            @Flag(name: .long, help: "Keep SwiftS3 server running after tests")
            var keepServer: Bool = false

            func run() async throws {
                print("🧪 Starting CybS3 + SwiftS3 integration tests...")

                // Start SwiftS3 server
                let serverProcess = Process()
                serverProcess.executableURL = URL(fileURLWithPath: swifts3Path)
                serverProcess.arguments = ["server", "--hostname", "127.0.0.1", "--port", "8080", "--storage", "/tmp/swifts3-test", "--access-key", "admin", "--secret-key", "password"]
                
                let outputPipe = Pipe()
                serverProcess.standardOutput = outputPipe
                serverProcess.standardError = outputPipe

                try serverProcess.run()
                print("🚀 SwiftS3 server started on http://127.0.0.1:8080")

                // Wait a bit for server to start
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                // Run tests using CybS3 commands
                do {
                    try await runIntegrationTests(bucket: bucket)
                    print("✅ All integration tests passed!")
                } catch {
                    print("❌ Tests failed: \(error)")
                }

                if !keepServer {
                    serverProcess.terminate()
                    print("🛑 SwiftS3 server stopped")
                }
            }

        private func runIntegrationTests(bucket: String) async throws {
            // Test bucket operations
            print("📦 Testing bucket operations...")
            
            // Create bucket
            let createProcess = Process()
            createProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3") // Assume installed
            createProcess.arguments = ["buckets", "create", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
            try createProcess.run()
            await createProcess.waitUntilExit()
            guard createProcess.terminationStatus == 0 else { throw TestError.bucketCreateFailed }

            // List buckets
            let listProcess = Process()
            listProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
            listProcess.arguments = ["buckets", "list", "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
            try listProcess.run()
            await listProcess.waitUntilExit()
            guard listProcess.terminationStatus == 0 else { throw TestError.bucketListFailed }

            // Test file operations
            print("📁 Testing file operations...")
            
            // Create a test file
            let testFile = "/tmp/cybs3-test.txt"
            try "Hello from CybS3!".write(toFile: testFile, atomically: true, encoding: .utf8)

            // Upload file
            let uploadProcess = Process()
            uploadProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
            uploadProcess.arguments = ["files", "put", testFile, "test-key", "--bucket", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
            try uploadProcess.run()
            await uploadProcess.waitUntilExit()
            guard uploadProcess.terminationStatus == 0 else { throw TestError.fileUploadFailed }

            // List files
            let listFilesProcess = Process()
            listFilesProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
            listFilesProcess.arguments = ["files", "list", "--bucket", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
            try listFilesProcess.run()
            await listFilesProcess.waitUntilExit()
            guard listFilesProcess.terminationStatus == 0 else { throw TestError.fileListFailed }

            // Download file
            let downloadProcess = Process()
            downloadProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
            downloadProcess.arguments = ["files", "get", "test-key", "/tmp/downloaded-test.txt", "--bucket", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
            try downloadProcess.run()
            await downloadProcess.waitUntilExit()
            guard downloadProcess.terminationStatus == 0 else { throw TestError.fileDownloadFailed }

            // Verify content
            let downloadedContent = try String(contentsOfFile: "/tmp/downloaded-test.txt")
            guard downloadedContent == "Hello from CybS3!" else { throw TestError.contentMismatch }

            print("✅ File operations successful")
        }

        struct SecurityTests: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "security",
                abstract: "Run security and encryption tests"
            )

            @Option(name: .long, help: "SwiftS3 executable path")
            var swifts3Path: String = "../SwiftS3/.build/release/SwiftS3"

            @Option(name: .long, help: "Test bucket name")
            var bucket: String = "security-test-bucket"

            func run() async throws {
                print("🔐 Starting CybS3 + SwiftS3 security tests...")

                // Start SwiftS3 server with KMS support
                let serverProcess = Process()
                serverProcess.executableURL = URL(fileURLWithPath: swifts3Path)
                serverProcess.arguments = ["server", "--hostname", "127.0.0.1", "--port", "8080", "--storage", "/tmp/swifts3-security", "--access-key", "admin", "--secret-key", "password"]
                
                let outputPipe = Pipe()
                serverProcess.standardOutput = outputPipe
                serverProcess.standardError = outputPipe

                try serverProcess.run()
                print("🚀 SwiftS3 server started on http://127.0.0.1:8080")

                // Wait for server to start
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                do {
                    try await runSecurityTests(bucket: bucket)
                    print("✅ All security tests passed!")
                } catch {
                    print("❌ Security tests failed: \(error)")
                }

                serverProcess.terminate()
                print("🛑 SwiftS3 server stopped")
            }

            private func runSecurityTests(bucket: String) async throws {
                print("🔒 Testing client-side encryption...")
                
                // Create bucket
                let createProcess = Process()
                createProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                createProcess.arguments = ["buckets", "create", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
                try createProcess.run()
                await createProcess.waitUntilExit()
                guard createProcess.terminationStatus == 0 else { throw TestError.bucketCreateFailed }

                // Test client-side encryption (default behavior)
                let sensitiveFile = "/tmp/sensitive-data.txt"
                try "This is sensitive information".write(toFile: sensitiveFile, atomically: true, encoding: .utf8)

                let uploadProcess = Process()
                uploadProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                uploadProcess.arguments = ["files", "put", sensitiveFile, "encrypted-key", "--bucket", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
                try uploadProcess.run()
                await uploadProcess.waitUntilExit()
                guard uploadProcess.terminationStatus == 0 else { throw TestError.fileUploadFailed }

                // Download and verify decryption
                let downloadProcess = Process()
                downloadProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                downloadProcess.arguments = ["files", "get", "encrypted-key", "/tmp/decrypted-data.txt", "--bucket", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
                try downloadProcess.run()
                await downloadProcess.waitUntilExit()
                guard downloadProcess.terminationStatus == 0 else { throw TestError.fileDownloadFailed }

                let decryptedContent = try String(contentsOfFile: "/tmp/decrypted-data.txt")
                guard decryptedContent == "This is sensitive information" else { throw TestError.contentMismatch }

                print("✅ Client-side encryption/decryption successful")

                // Test double encryption (client + server)
                print("🔐 Testing double encryption (client + server)...")
                
                let doubleEncryptFile = "/tmp/double-encrypt.txt"
                try "Double encrypted data".write(toFile: doubleEncryptFile, atomically: true, encoding: .utf8)

                let doubleUploadProcess = Process()
                doubleUploadProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                doubleUploadProcess.arguments = ["files", "put", doubleEncryptFile, "double-encrypted-key", "--bucket", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl", "--sse-kms"]
                try doubleUploadProcess.run()
                await doubleUploadProcess.waitUntilExit()
                guard doubleUploadProcess.terminationStatus == 0 else { throw TestError.fileUploadFailed }

                // Download and verify
                let doubleDownloadProcess = Process()
                doubleDownloadProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                doubleDownloadProcess.arguments = ["files", "get", "double-encrypted-key", "/tmp/double-decrypted.txt", "--bucket", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
                try doubleDownloadProcess.run()
                await doubleDownloadProcess.waitUntilExit()
                guard doubleDownloadProcess.terminationStatus == 0 else { throw TestError.fileDownloadFailed }

                let doubleDecryptedContent = try String(contentsOfFile: "/tmp/double-decrypted.txt")
                guard doubleDecryptedContent == "Double encrypted data" else { throw TestError.contentMismatch }

                print("✅ Double encryption (client + server SSE-KMS) successful")

                // Test key rotation
                print("🔄 Testing key rotation...")
                
                let rotateProcess = Process()
                rotateProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                rotateProcess.arguments = ["keys", "rotate", "--yes"]
                try rotateProcess.run()
                await rotateProcess.waitUntilExit()
                guard rotateProcess.terminationStatus == 0 else { throw TestError.keyRotationFailed }

                // Verify file is still accessible after rotation
                let postRotationDownload = Process()
                postRotationDownload.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                postRotationDownload.arguments = ["files", "get", "encrypted-key", "/tmp/post-rotation.txt", "--bucket", bucket, "--endpoint", "http://127.0.0.1:8080", "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
                try postRotationDownload.run()
                await postRotationDownload.waitUntilExit()
                guard postRotationDownload.terminationStatus == 0 else { throw TestError.fileDownloadFailed }

                let postRotationContent = try String(contentsOfFile: "/tmp/post-rotation.txt")
                guard postRotationContent == "This is sensitive information" else { throw TestError.contentMismatch }

                print("✅ Key rotation successful - data remains accessible")
            }
        }
    }

    enum TestError: Error {
        case bucketCreateFailed
        case bucketListFailed
        case fileUploadFailed
        case fileListFailed
        case fileDownloadFailed
        case contentMismatch
        case keyRotationFailed
    }
}
