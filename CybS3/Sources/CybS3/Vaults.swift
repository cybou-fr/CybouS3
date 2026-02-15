import Foundation
import ArgumentParser
import Crypto
import SwiftBIP39
import CybS3Lib

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
                Select.self
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
}
