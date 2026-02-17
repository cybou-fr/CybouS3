import ArgumentParser
import AsyncHTTPClient
import Crypto
import CybS3Lib
import Foundation
import NIO
import NIOCore
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
