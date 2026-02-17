import ArgumentParser
import CybS3Lib
import Foundation

/// Core authentication and configuration commands
struct CoreCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "core",
        abstract: "Core authentication and configuration commands",
        subcommands: [
            Login.self,
            Logout.self,
            Config.self,
        ]
    )

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

        @Option(name: .long, help: "Create a new vault")
        var createVault: String?

        @Option(name: .long, help: "Set active vault")
        var activeVault: String?

        @Flag(name: .long, help: "List current configuration")
        var list: Bool = false

        @Flag(name: .long, help: "Reset configuration to defaults")
        var reset: Bool = false

        func run() async throws {
            do {
                let mnemonic = try InteractionService.promptForMnemonic(
                    purpose: "modify configuration")

                if list {
                    let (config, _) = try StorageService.load(mnemonic: mnemonic)
                    ConsoleUI.header("Current Configuration")
                    print("Settings:")
                    print("  Endpoint: \(config.settings.endpoint ?? "not set")")
                    print("  Region: \(config.settings.region ?? "not set")")
                    print("  Bucket: \(config.settings.bucket ?? "not set")")
                    print("  Access Key: \(config.settings.accessKey?.prefix(8) ?? "not set")...")
                    print()
                    print("Vaults:")
                    for vault in config.vaults {
                        let active = vault.name == config.activeVaultName ? " (active)" : ""
                        print("  \(vault.name)\(active)")
                        print("    Endpoint: \(vault.endpoint ?? "inherits from global")")
                        print("    Region: \(vault.region ?? "inherits from global")")
                        print("    Bucket: \(vault.bucket ?? "inherits from global")")
                        print("    Access Key: \(vault.accessKey?.prefix(8) ?? "inherits from global")...")
                    }
                    return
                }

                if reset {
                    guard InteractionService.confirm(message: "Reset configuration to defaults?", defaultValue: false) else {
                        ConsoleUI.info("Operation cancelled.")
                        return
                    }
                    try StorageService.reset()
                    ConsoleUI.success("Configuration reset to defaults.")
                    return
                }

                var (config, dataKey) = try StorageService.load(mnemonic: mnemonic)

                // Update global settings
                if let accessKey = accessKey {
                    config.settings.accessKey = accessKey
                }
                if let secretKey = secretKey {
                    config.settings.secretKey = secretKey
                }
                if let endpoint = endpoint {
                    config.settings.endpoint = endpoint
                }
                if let region = region {
                    config.settings.region = region
                }
                if let bucket = bucket {
                    config.settings.bucket = bucket
                }

                // Vault management
                if let vaultName = createVault {
                    if config.vaults.contains(where: { $0.name == vaultName }) {
                        ConsoleUI.error("Vault '\(vaultName)' already exists.")
                        throw ExitCode.failure
                    }
                    config.vaults.append(VaultConfig(name: vaultName))
                    ConsoleUI.success("Created vault: \(vaultName)")
                }

                if let vaultName = activeVault {
                    if !config.vaults.contains(where: { $0.name == vaultName }) {
                        ConsoleUI.error("Vault '\(vaultName)' does not exist.")
                        throw ExitCode.failure
                    }
                    config.activeVaultName = vaultName
                    ConsoleUI.success("Set active vault: \(vaultName)")
                }

                try StorageService.save(config: config, dataKey: dataKey)
                ConsoleUI.success("Configuration updated.")

            } catch let error as InteractionError {
                CLIError.from(error).printError()
                throw ExitCode.failure
            } catch let error as StorageError {
                CLIError.from(error).printError()
                throw ExitCode.failure
            } catch {
                ConsoleUI.error("Configuration failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}