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

                let handler = LoginHandler(authService: CoreServices.shared.authService)
                let result = try await handler.handle(input: LoginInput(mnemonic: mnemonic.joined(separator: " ")))

                if result.success {
                    ConsoleUI.success(result.message)
                    ConsoleUI.dim("You can now run commands without entering your mnemonic.")
                } else {
                    ConsoleUI.error(result.message)
                    throw ExitCode.failure
                }

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
            let handler = LogoutHandler(authService: CoreServices.shared.authService)
            let result = try await handler.handle(input: LogoutInput())

            if result.success {
                ConsoleUI.success(result.message)
            } else {
                ConsoleUI.error(result.message)
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

                let input = ConfigInput(
                    mnemonic: mnemonic.joined(separator: " "),
                    list: list,
                    reset: reset,
                    accessKey: accessKey,
                    secretKey: secretKey,
                    endpoint: endpoint,
                    region: region,
                    bucket: bucket,
                    createVault: createVault,
                    activeVault: activeVault
                )

                let handler = ConfigHandler(configService: CoreServices.shared.configService)
                let result = try await handler.handle(input: input)

                if result.success {
                    ConsoleUI.success(result.message)

                    // Handle list output
                    if let config = result.config {
                        ConsoleUI.header("Current Configuration")
                        print("Settings:")
                        print("  Endpoint: \(config.settings.defaultEndpoint ?? "not set")")
                        print("  Region: \(config.settings.defaultRegion ?? "not set")")
                        print("  Bucket: \(config.settings.defaultBucket ?? "not set")")
                        print("  Access Key: \(config.settings.defaultAccessKey?.prefix(8) ?? "not set")...")
                        print()
                        print("Vaults:")
                        for vault in config.vaults {
                            let active = vault.name == config.activeVaultName ? " (active)" : ""
                            print("  \(vault.name)\(active)")
                            print("    Endpoint: \(vault.endpoint)")
                            print("    Region: \(vault.region)")
                            print("    Bucket: \(vault.bucket ?? "inherits from global")")
                            print("    Access Key: \(vault.accessKey.prefix(8))...")
                        }
                    }
                } else {
                    ConsoleUI.error(result.message)
                    throw ExitCode.failure
                }

            } catch let error as InteractionError {
                CLIError.from(error).printError()
                throw ExitCode.failure
            } catch let error as StorageError {
                CLIError.from(error).printError()
                throw ExitCode.failure
            } catch let error as ConfigurationError {
                ConsoleUI.error("Configuration error: \(error.localizedDescription)")
                throw ExitCode.failure
            } catch {
                ConsoleUI.error("Configuration failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}