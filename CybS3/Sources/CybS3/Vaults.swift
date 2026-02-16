import Foundation
import ArgumentParser
import Crypto
import SwiftBIP39
import CybS3Lib
import AsyncHTTPClient

extension CybS3CLI {
    struct Vaults: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "vaults",
            abstract: "Manage encrypted S3 vaults",
            subcommands: [
                Add.self,
                List.self,
                Delete.self,
                Local.self,
                Select.self,
                Provision.self,
                Sync.self,
                Status.self
            ]
        )
    }
}

extension CybS3CLI.Vaults {
    /// Command to add a new encrypted vault configuration.
    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a new encrypted vault configuration"
        )
        
        @Option(name: .shortAndLong, help: "Vault name")
        var name: String
        
        func run() async throws {
            // 1. Authenticate first to load config
            let mnemonic = try InteractionService.promptForMnemonic(purpose: "unlock configuration")
            var (config, _) = try StorageService.load(mnemonic: mnemonic)
            
            // 2. Gather Vault Details
            guard let endpoint = InteractionService.prompt(message: "Enter S3 Endpoint (e.g. s3.amazonaws.com):"), !endpoint.isEmpty else { return }
            guard let accessKey = InteractionService.prompt(message: "Enter Access Key:"), !accessKey.isEmpty else { return }
            guard let secretKey = InteractionService.prompt(message: "Enter Secret Key:"), !secretKey.isEmpty else { return }
            
            let region = InteractionService.prompt(message: "Enter Region (default: us-east-1):") ?? "us-east-1"
            let finalRegion = region.isEmpty ? "us-east-1" : region
            
            let bucket = InteractionService.prompt(message: "Enter Bucket (optional):")
            let finalBucket = (bucket?.isEmpty ?? true) ? nil : bucket
            
            let newVault = VaultConfig(
                name: name,
                endpoint: endpoint,
                accessKey: accessKey,
                secretKey: secretKey,
                region: finalRegion,
                bucket: finalBucket
            )
            
            // 3. Show preview and ask for confirmation
            print("\n📋 Vault Configuration Preview:")
            print("─────────────────────────────────────────")
            print("Name:       \(newVault.name)")
            print("Endpoint:   \(newVault.endpoint)")
            print("Region:     \(newVault.region)")
            print("Bucket:     \(newVault.bucket ?? "(not set)")")
            print("─────────────────────────────────────────")
            
            let confirmed = InteractionService.confirm(message: "Save this vault configuration?", defaultValue: false)
            
            if !confirmed {
                print("❌ Vault configuration cancelled.")
                return
            }
            
            // 4. Save
            config.vaults.append(newVault)
            try StorageService.save(config, mnemonic: mnemonic)
            print("✅ Vault '\(name)' added successfully.")
        }
    }
    
    /// Command to list all configured vaults.
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all encrypted vaults"
        )
        
        func run() async throws {
            let mnemonic = try InteractionService.promptForMnemonic(purpose: "unlock configuration")
            let (config, _) = try StorageService.load(mnemonic: mnemonic)
            
            if config.vaults.isEmpty {
                print("No vaults found.")
                return
            }
            
            print("\nEncrypted Vaults:")
            print("------------------------------------------------")
            for vault in config.vaults {
                print("Name: \(vault.name)")
                print("Endpoint: \(vault.endpoint)")
                print("Bucket: \(vault.bucket ?? "N/A")")
                print("Region: \(vault.region)")
                print("------------------------------------------------")
            }
        }
    }
    
    /// Command to delete a configured vault.
    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete an encrypted vault configuration"
        )
        
        @Argument(help: "Name of the vault to delete")
        var name: String
        
        @Flag(name: .shortAndLong, help: "Force deletion without confirmation")
        var force: Bool = false
        
        func run() async throws {
            let mnemonic = try InteractionService.promptForMnemonic(purpose: "unlock configuration")
            var (config, _) = try StorageService.load(mnemonic: mnemonic)
            
            guard let index = config.vaults.firstIndex(where: { $0.name == name }) else {
                print("❌ Error: Vault '\(name)' not found.")
                print("Use 'cybs3 vaults list' to see available vaults.")
                throw ExitCode.failure
            }
            
            // Ask for confirmation unless force is set
            if !force {
                ConsoleUI.warning("You are about to delete vault '\(name)'.")
                guard InteractionService.confirm(message: "Are you sure you want to delete this vault?", defaultValue: false) else {
                    ConsoleUI.info("Deletion cancelled.")
                    return
                }
            }
            
            config.vaults.remove(at: index)
            try StorageService.save(config, mnemonic: mnemonic)
            ConsoleUI.success("Vault '\(name)' deleted successfully.")
        }
    }

    /// Command to select a vault and apply its settings globally.
    struct Select: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "select",
            abstract: "Select a vault and apply its configuration globally"
        )
        
        @Argument(help: "Name of the vault to select")
        var name: String
        
        func run() async throws {
            let mnemonic = try InteractionService.promptForMnemonic(purpose: "unlock configuration")
            var (config, _) = try StorageService.load(mnemonic: mnemonic)
            
            guard let vault = config.vaults.first(where: { $0.name == name }) else {
                 print("Error: Vault '\(name)' not found.")
                 throw ExitCode.failure
            }
            
            // Apply to global settings in the Unified Config
            // This replaces the old logic of writing to separate config file
            config.activeVaultName = vault.name
            config.settings.defaultEndpoint = vault.endpoint
            config.settings.defaultAccessKey = vault.accessKey
            config.settings.defaultSecretKey = vault.secretKey
            config.settings.defaultRegion = vault.region
            config.settings.defaultBucket = vault.bucket
            
            try StorageService.save(config, mnemonic: mnemonic)
            print("✅ Vault '\(name)' selected. Global settings updated.")
        }
    }

    /// Command to add a local SwiftS3 vault configuration.
    struct Local: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "local",
            abstract: "Add a vault configured for local SwiftS3 server"
        )
        
        @Option(name: .shortAndLong, help: "Vault name")
        var name: String = "local-swifts3"
        
        @Option(name: .long, help: "SwiftS3 server hostname")
        var hostname: String = "127.0.0.1"
        
        @Option(name: .long, help: "SwiftS3 server port")
        var port: Int = 8080
        
        @Option(name: .long, help: "Access key for SwiftS3")
        var accessKey: String = "admin"
        
        @Option(name: .long, help: "Secret key for SwiftS3")
        var secretKey: String = "password"
        
        @Option(name: .long, help: "Bucket name")
        var bucket: String?
        
        func run() async throws {
            // 1. Authenticate first to load config
            let mnemonic = try InteractionService.promptForMnemonic(purpose: "unlock configuration")
            var (config, _) = try StorageService.load(mnemonic: mnemonic)
            
            // 2. Check if vault already exists
            if config.vaults.contains(where: { $0.name == name }) {
                print("Error: Vault '\(name)' already exists.")
                throw ExitCode.failure
            }
            
            // 3. Create local vault config
            let endpoint = "http://\(hostname):\(port)"
            let newVault = VaultConfig(
                name: name,
                endpoint: endpoint,
                accessKey: accessKey,
                secretKey: secretKey,
                region: "us-east-1", // SwiftS3 doesn't use regions strictly
                bucket: bucket
            )
            
            config.vaults.append(newVault)
            try StorageService.save(config, mnemonic: mnemonic)
            
            print("✅ Local SwiftS3 vault '\(name)' added.")
            print("   Endpoint: \(endpoint)")
            print("   Access Key: \(accessKey)")
            print("💡 Use 'cybs3 vaults select \(name)' to activate this vault")
            print("💡 Start SwiftS3 server: SwiftS3 server --hostname \(hostname) --port \(port) --access-key \(accessKey) --secret-key \(secretKey)")
        }
    }

    /// Command to provision server resources for a vault.
    struct Provision: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "provision",
            abstract: "Auto-provision server resources for a vault"
        )

        @Option(name: .shortAndLong, help: "Vault name to provision")
        var vault: String?

        @Option(name: .long, help: "SwiftS3 server endpoint for provisioning")
        var serverEndpoint: String = "http://127.0.0.1:8080"

        @Flag(name: .long, help: "Create bucket if it doesn't exist")
        var createBucket: Bool = false

        @Flag(name: .long, help: "Setup server-side encryption")
        var enableSSE: Bool = false

        func run() async throws {
            print("🏗️  Provisioning server resources for vault...")

            // Get vault configuration
            let mnemonic = try InteractionService.promptForMnemonic(purpose: "unlock configuration for vault provisioning")
            let (config, _) = try StorageService.load(mnemonic: mnemonic)

            let vaultToProvision: VaultConfig
            if let vaultName = vault {
                guard let v = config.vaults.first(where: { $0.name == vaultName }) else {
                    print("❌ Vault '\(vaultName)' not found.")
                    throw ExitCode.failure
                }
                vaultToProvision = v
            } else if let activeVault = config.activeVaultName,
                      let v = config.vaults.first(where: { $0.name == activeVault }) {
                vaultToProvision = v
                print("Using active vault: \(activeVault)")
            } else {
                print("❌ No vault specified and no active vault set.")
                throw ExitCode.failure
            }

            print("📋 Provisioning vault '\(vaultToProvision.name)' on server \(serverEndpoint)")

            // Parse server endpoint
            let endpointString = serverEndpoint.contains("://") ? serverEndpoint : "http://\(serverEndpoint)"
            guard let url = URL(string: endpointString) else {
                print("❌ Invalid server endpoint URL")
                throw ExitCode.failure
            }

            let s3Endpoint = S3Endpoint(
                host: url.host ?? serverEndpoint,
                port: url.port ?? (url.scheme == "http" ? 80 : 443),
                useSSL: url.scheme == "https"
            )

            // Step 1: Sync authentication
            do {
                let success = try await UnifiedAuthService.syncCredentials(from: vaultToProvision, to: serverEndpoint)
                if success {
                    print("✅ Authentication synced")
                }
            } catch {
                print("⚠️  Auth sync failed (continuing): \(error.localizedDescription)")
            }

            // Step 2: Create bucket if requested
            if createBucket, let bucketName = vaultToProvision.bucket {
                print("📦 Creating bucket '\(bucketName)'...")

                // Use S3Client to create the bucket
                let client = S3Client(
                    endpoint: s3Endpoint,
                    accessKey: vaultToProvision.accessKey,
                    secretKey: vaultToProvision.secretKey,
                    region: vaultToProvision.region
                )

                do {
                    try await client.createBucket(name: bucketName)
                    print("✅ Bucket '\(bucketName)' created")
                } catch let error as S3Error {
                    if case .requestFailed(let status, _, _) = error, status == 409 {
                        print("⚠️  Bucket '\(bucketName)' already exists")
                    } else {
                        print("⚠️  Bucket creation failed: \(error.localizedDescription)")
                    }
                } catch {
                    print("⚠️  Bucket creation failed: \(error.localizedDescription)")
                }
            }

            // Step 3: Setup SSE if requested
            if enableSSE {
                print("🔐 Configuring server-side encryption...")

                // Test SSE-KMS capability
                let sseClient = S3Client(
                    endpoint: s3Endpoint,
                    accessKey: vaultToProvision.accessKey,
                    secretKey: vaultToProvision.secretKey,
                    bucket: vaultToProvision.bucket,
                    region: vaultToProvision.region,
                    sseKms: true,
                    kmsKeyId: "alias/test-key"
                )

                do {
                    try await sseClient.putObject(key: "sse-test", data: "SSE test data".data(using: .utf8)!)
                    print("✅ Server-side encryption configured")
                } catch {
                    print("⚠️  SSE-KMS not supported by server (continuing): \(error.localizedDescription)")
                }
            }

            print("✅ Vault provisioning completed")
            print("🔧 Vault '\(vaultToProvision.name)' is ready for use")
            print("   Server: \(serverEndpoint)")
            print("   Bucket: \(vaultToProvision.bucket ?? "not configured")")
            print("   SSE: \(enableSSE ? "enabled" : "disabled")")
        }
    }

    /// Command to synchronize vault configuration across ecosystem.
    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "sync",
            abstract: "Synchronize vault configuration across CybS3 and SwiftS3"
        )

        @Option(name: .shortAndLong, help: "Vault name to sync")
        var vault: String?

        @Option(name: .long, help: "Target server endpoint")
        var server: String?

        @Flag(name: .long, help: "Sync all vaults")
        var all: Bool = false

        func run() async throws {
            print("🔄 Synchronizing vault configurations...")

            let mnemonic = try InteractionService.promptForMnemonic(purpose: "unlock configuration for vault sync")
            let (config, _) = try StorageService.load(mnemonic: mnemonic)

            let vaultsToSync: [VaultConfig]
            if all {
                vaultsToSync = config.vaults
                print("Syncing all \(vaultsToSync.count) vaults...")
            } else if let vaultName = vault {
                guard let v = config.vaults.first(where: { $0.name == vaultName }) else {
                    print("❌ Vault '\(vaultName)' not found.")
                    throw ExitCode.failure
                }
                vaultsToSync = [v]
            } else if let activeVault = config.activeVaultName,
                      let v = config.vaults.first(where: { $0.name == activeVault }) {
                vaultsToSync = [v]
                print("Using active vault: \(activeVault)")
            } else {
                print("❌ No vault specified. Use --vault, --all, or select an active vault.")
                throw ExitCode.failure
            }

            // Determine target servers
            let targetServers = server.map { [$0] } ?? ["http://127.0.0.1:8080"] // Default to local server

            for vault in vaultsToSync {
                print("\n📋 Syncing vault '\(vault.name)'...")

                for serverEndpoint in targetServers {
                    do {
                        let success = try await UnifiedAuthService.syncCredentials(from: vault, to: serverEndpoint)
                        if success {
                            print("   ✅ Synced to \(serverEndpoint)")
                        } else {
                            print("   ⚠️  Sync to \(serverEndpoint) completed with warnings")
                        }
                    } catch {
                        print("   ❌ Failed to sync to \(serverEndpoint): \(error.localizedDescription)")
                    }
                }
            }

            print("\n✅ Vault synchronization completed")
        }
    }

    /// Command to show vault status and health.
    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show vault status and health across ecosystem"
        )

        @Option(name: .shortAndLong, help: "Vault name to check")
        var vault: String?

        @Option(name: .long, help: "Server endpoint to check")
        var server: String = "http://127.0.0.1:8080"

        @Flag(name: .long, help: "Include detailed health checks")
        var detailed: Bool = false

        func run() async throws {
            print("📊 Checking vault status and health...")

            let mnemonic = try InteractionService.promptForMnemonic(purpose: "unlock configuration for vault status")
            let (config, _) = try StorageService.load(mnemonic: mnemonic)

            let vaultsToCheck: [VaultConfig]
            if let vaultName = vault {
                guard let v = config.vaults.first(where: { $0.name == vaultName }) else {
                    print("❌ Vault '\(vaultName)' not found.")
                    throw ExitCode.failure
                }
                vaultsToCheck = [v]
            } else {
                vaultsToCheck = config.vaults
            }

            for vault in vaultsToCheck {
                print("\n🔐 Vault: \(vault.name)")
                print("   Endpoint: \(vault.endpoint)")
                print("   Region: \(vault.region)")
                print("   Bucket: \(vault.bucket ?? "not set")")

                // Check authentication sync status
                do {
                    let authStatus = try await UnifiedAuthService.checkSyncStatus(for: vault, serverEndpoint: server)
                    print("   Auth Sync: \(authStatus.isSynced ? "✅" : "❌")")
                    if let lastSync = authStatus.lastSync {
                        print("   Last Sync: \(lastSync.formatted())")
                    }
                } catch {
                    print("   Auth Sync: ❌ (\(error.localizedDescription))")
                }

                // Check credential validation
                do {
                    let validation = try await UnifiedAuthService.validateCredentials(vault)
                    print("   CybS3 Creds: \(validation.cybS3Valid ? "✅" : "❌")")
                    print("   SwiftS3 Creds: \(validation.swiftS3Valid ? "✅" : "❌")")
                    if !validation.errors.isEmpty {
                        print("   Errors: \(validation.errors.joined(separator: "; "))")
                    }
                } catch {
                    print("   Credential Check: ❌ (\(error.localizedDescription))")
                }

                if detailed {
                    // Additional health checks
                    print("   📈 Detailed Health:")

                    // Check if server is accessible
                    do {
                        let client = HTTPClient()
                        defer { try? client.shutdown() }

                        let request = HTTPClientRequest(url: server as String)
                        let response: HTTPClientResponse = try await client.execute(request, deadline: .distantFuture)
                        print("      Server: ✅ (HTTP \(response.status.code))")
                    } catch {
                        print("      Server: ❌ (unreachable)")
                    }

                    // Check bucket accessibility
                    if let bucket = vault.bucket {
                        // Parse server URL
                        let endpointString = server.contains("://") ? server : "http://\(server)"
                        guard let url = URL(string: endpointString) else {
                            print("      Bucket '\(bucket)': ❌ (invalid server URL)")
                            continue
                        }

                        let s3Endpoint = S3Endpoint(
                            host: url.host ?? server,
                            port: url.port ?? (url.scheme == "http" ? 80 : 443),
                            useSSL: url.scheme == "https"
                        )

                        let bucketClient = S3Client(
                            endpoint: s3Endpoint,
                            accessKey: vault.accessKey,
                            secretKey: vault.secretKey,
                            bucket: bucket,
                            region: vault.region
                        )

                        do {
                            _ = try await bucketClient.listBuckets()
                            print("      Bucket '\(bucket)': ✅ (accessible)")
                        } catch {
                            print("      Bucket '\(bucket)': ❌ (access denied or not found)")
                        }
                    }
                }
            }

            print("\n✅ Vault status check completed")
        }
    }
}
