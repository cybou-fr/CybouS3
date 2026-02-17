import Foundation

/// Type alias for configuration
public typealias Configuration = EncryptedConfig

/// Configuration-related errors
enum ConfigurationError: LocalizedError {
    case vaultAlreadyExists(String)
    case vaultNotFound(String)

    var errorDescription: String? {
        switch self {
        case .vaultAlreadyExists(let name):
            return "Vault '\(name)' already exists"
        case .vaultNotFound(let name):
            return "Vault '\(name)' does not exist"
        }
    }
}

/// Protocol for command handlers that encapsulate business logic
public protocol CommandHandler {
    associatedtype Input
    associatedtype Output

    func handle(input: Input) async throws -> Output
}

/// Input/output types for core commands
public struct LoginInput {
    public let mnemonic: String
}

public struct LoginOutput {
    public let success: Bool
    public let message: String
}

public struct LogoutInput {
    // No input needed
}

public struct LogoutOutput {
    public let success: Bool
    public let message: String
}

public struct ConfigInput {
    public let mnemonic: String
    public let list: Bool
    public let reset: Bool
    public let accessKey: String?
    public let secretKey: String?
    public let endpoint: String?
    public let region: String?
    public let bucket: String?
    public let createVault: String?
    public let activeVault: String?
}

public struct ConfigOutput {
    public let success: Bool
    public let message: String
    public let config: Configuration? // Only populated when listing
}

/// Service protocols for dependency injection
public protocol AuthenticationServiceProtocol {
    func login(mnemonic: String) async throws -> LoginOutput
    func logout() async throws -> LogoutOutput
}

public protocol ConfigurationServiceProtocol {
    func getConfig(mnemonic: String) async throws -> Configuration
    func updateConfig(mnemonic: String, updates: ConfigInput) async throws -> ConfigOutput
    func resetConfig() async throws
    func createVault(mnemonic: String, name: String) async throws
    func setActiveVault(mnemonic: String, name: String) async throws
}

/// Default implementations using existing services
class DefaultAuthenticationService: AuthenticationServiceProtocol {
    func login(mnemonic: String) async throws -> LoginOutput {
        // Verify it works by trying to load config
        _ = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))

        try KeychainService.save(mnemonic: mnemonic.split(separator: " ").map(String.init))

        return LoginOutput(
            success: true,
            message: "Login successful. Mnemonic stored securely in Keychain."
        )
    }

    func logout() async throws -> LogoutOutput {
        do {
            try KeychainService.delete()
            return LogoutOutput(
                success: true,
                message: "Logout successful. Mnemonic removed from Keychain."
            )
        } catch KeychainError.itemNotFound {
            return LogoutOutput(
                success: true,
                message: "No active session found. Already logged out."
            )
        } catch {
            return LogoutOutput(
                success: false,
                message: "Logout failed: \(error.localizedDescription)"
            )
        }
    }
}

class DefaultConfigurationService: ConfigurationServiceProtocol {
    func getConfig(mnemonic: String) async throws -> Configuration {
        let (config, _) = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))
        return config
    }

    func updateConfig(mnemonic: String, updates: ConfigInput) async throws -> ConfigOutput {
        var (config, dataKey) = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))

        // Update global settings
        if let accessKey = updates.accessKey {
            config.settings.defaultAccessKey = accessKey
        }
        if let secretKey = updates.secretKey {
            config.settings.defaultSecretKey = secretKey
        }
        if let endpoint = updates.endpoint {
            config.settings.defaultEndpoint = endpoint
        }
        if let region = updates.region {
            config.settings.defaultRegion = region
        }
        if let bucket = updates.bucket {
            config.settings.defaultBucket = bucket
        }

        try StorageService.save(config: config, dataKey: dataKey)

        return ConfigOutput(
            success: true,
            message: "Configuration updated.",
            config: nil
        )
    }

    func resetConfig() async throws {
        // For now, just throw an error as reset is not implemented
        throw NSError(domain: "Configuration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reset not implemented"])
    }

    func createVault(mnemonic: String, name: String) async throws {
        var (config, dataKey) = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))

        if config.vaults.contains(where: { $0.name == name }) {
            throw ConfigurationError.vaultAlreadyExists(name)
        }

        config.vaults.append(VaultConfig(name: name, endpoint: "", accessKey: "", secretKey: "", region: ""))
        try StorageService.save(config: config, dataKey: dataKey)
    }

    func setActiveVault(mnemonic: String, name: String) async throws {
        var (config, dataKey) = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))

        if !config.vaults.contains(where: { $0.name == name }) {
            throw ConfigurationError.vaultNotFound(name)
        }

        config.activeVaultName = name
        try StorageService.save(config: config, dataKey: dataKey)
    }
}

/// Command handlers using the service layer
struct LoginHandler: CommandHandler {
    typealias Input = LoginInput
    typealias Output = LoginOutput

    let authService: AuthenticationServiceProtocol

    func handle(input: LoginInput) async throws -> LoginOutput {
        try await authService.login(mnemonic: input.mnemonic)
    }
}

struct LogoutHandler: CommandHandler {
    typealias Input = LogoutInput
    typealias Output = LogoutOutput

    let authService: AuthenticationServiceProtocol

    func handle(input: LogoutInput) async throws -> LogoutOutput {
        try await authService.logout()
    }
}

struct ConfigHandler: CommandHandler {
    typealias Input = ConfigInput
    typealias Output = ConfigOutput

    let configService: ConfigurationServiceProtocol

    func handle(input: ConfigInput) async throws -> ConfigOutput {
        if input.list {
            let config = try await configService.getConfig(mnemonic: input.mnemonic)
            return ConfigOutput(
                success: true,
                message: "Configuration retrieved successfully",
                config: config
            )
        }

        if input.reset {
            try await configService.resetConfig()
            return ConfigOutput(
                success: true,
                message: "Configuration reset to defaults.",
                config: nil
            )
        }

        // Handle vault creation
        if let vaultName = input.createVault {
            try await configService.createVault(mnemonic: input.mnemonic, name: vaultName)
            return ConfigOutput(
                success: true,
                message: "Created vault: \(vaultName)",
                config: nil
            )
        }

        // Handle active vault setting
        if let vaultName = input.activeVault {
            try await configService.setActiveVault(mnemonic: input.mnemonic, name: vaultName)
            return ConfigOutput(
                success: true,
                message: "Set active vault: \(vaultName)",
                config: nil
            )
        }

        // Handle configuration updates
        return try await configService.updateConfig(mnemonic: input.mnemonic, updates: input)
    }
}

/// Dependency container for services
class CoreServices {
    @MainActor
    static let shared = CoreServices()

    lazy var authService: AuthenticationServiceProtocol = DefaultAuthenticationService()
    lazy var configService: ConfigurationServiceProtocol = DefaultConfigurationService()
}