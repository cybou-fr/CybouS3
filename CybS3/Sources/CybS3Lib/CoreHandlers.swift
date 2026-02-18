import Foundation

/// Type alias for configuration
public typealias Configuration = EncryptedConfig

/// Configuration-related errors
public enum ConfigurationError: LocalizedError {
    case vaultAlreadyExists(String)
    case vaultNotFound(String)

    public var errorDescription: String? {
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

    public init(mnemonic: String) {
        self.mnemonic = mnemonic
    }
}

public struct LoginOutput {
    public let success: Bool
    public let message: String
}

public struct LogoutInput {
    // No input needed
    public init() {}
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

    public init(mnemonic: String, list: Bool, reset: Bool, accessKey: String?, secretKey: String?, endpoint: String?, region: String?, bucket: String?, createVault: String?, activeVault: String?) {
        self.mnemonic = mnemonic
        self.list = list
        self.reset = reset
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.createVault = createVault
        self.activeVault = activeVault
    }
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
public class DefaultAuthenticationService: AuthenticationServiceProtocol {
    public func login(mnemonic: String) async throws -> LoginOutput {
        // Verify it works by trying to load config
        _ = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))

        try KeychainService.save(mnemonic: mnemonic.split(separator: " ").map(String.init))

        return LoginOutput(
            success: true,
            message: "Login successful. Mnemonic stored securely in Keychain."
        )
    }

    public func logout() async throws -> LogoutOutput {
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

public class DefaultConfigurationService: ConfigurationServiceProtocol {
    public func getConfig(mnemonic: String) async throws -> Configuration {
        let (config, _) = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))
        return config
    }

    public func updateConfig(mnemonic: String, updates: ConfigInput) async throws -> ConfigOutput {
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

    public func resetConfig() async throws {
        // For now, just throw an error as reset is not implemented
        throw NSError(domain: "Configuration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reset not implemented"])
    }

    public func createVault(mnemonic: String, name: String) async throws {
        var (config, dataKey) = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))

        if config.vaults.contains(where: { $0.name == name }) {
            throw ConfigurationError.vaultAlreadyExists(name)
        }

        config.vaults.append(VaultConfig(name: name, endpoint: "", accessKey: "", secretKey: "", region: ""))
        try StorageService.save(config: config, dataKey: dataKey)
    }

    public func setActiveVault(mnemonic: String, name: String) async throws {
        var (config, dataKey) = try StorageService.load(mnemonic: mnemonic.split(separator: " ").map(String.init))

        if !config.vaults.contains(where: { $0.name == name }) {
            throw ConfigurationError.vaultNotFound(name)
        }

        config.activeVaultName = name
        try StorageService.save(config: config, dataKey: dataKey)
    }
}

/// Command handlers using the service layer
public struct LoginHandler: CommandHandler {
    public typealias Input = LoginInput
    public typealias Output = LoginOutput

    public let authService: AuthenticationServiceProtocol

    public init(authService: AuthenticationServiceProtocol) {
        self.authService = authService
    }

    public func handle(input: LoginInput) async throws -> LoginOutput {
        try await authService.login(mnemonic: input.mnemonic)
    }
}

public struct LogoutHandler: CommandHandler {
    public typealias Input = LogoutInput
    public typealias Output = LogoutOutput

    public let authService: AuthenticationServiceProtocol

    public init(authService: AuthenticationServiceProtocol) {
        self.authService = authService
    }

    public func handle(input: LogoutInput) async throws -> LogoutOutput {
        try await authService.logout()
    }
}

public struct ConfigHandler: CommandHandler {
    public typealias Input = ConfigInput
    public typealias Output = ConfigOutput

    public let configService: ConfigurationServiceProtocol

    public init(configService: ConfigurationServiceProtocol) {
        self.configService = configService
    }

    public func handle(input: ConfigInput) async throws -> ConfigOutput {
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
public class CoreServices: @unchecked Sendable {
    public static let shared = CoreServices()

    public lazy var authService: AuthenticationServiceProtocol = DefaultAuthenticationService()
    public lazy var configService: ConfigurationServiceProtocol = DefaultConfigurationService()
}