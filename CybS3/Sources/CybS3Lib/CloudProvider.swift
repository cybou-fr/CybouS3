import Foundation

// Forward declarations for cloud clients
// These will be imported when the clients are created

/// Cloud provider types supported by CybouS3.
public enum CloudProvider: String, Codable, Sendable, CaseIterable {
    case aws = "aws"
    case gcp = "gcp"
    case azure = "azure"
    case minio = "minio"
    case wasabi = "wasabi"
    case digitalocean = "digitalocean"
    case linode = "linode"
    case backblaze = "backblaze"
    case cloudflare = "cloudflare"
    case alibaba = "alibaba"
    case tencent = "tencent"
    case huawei = "huawei"
    case oracle = "oracle"

    /// Display name for the provider.
    public var displayName: String {
        switch self {
        case .aws: return "Amazon Web Services S3"
        case .gcp: return "Google Cloud Storage"
        case .azure: return "Microsoft Azure Blob Storage"
        case .minio: return "MinIO"
        case .wasabi: return "Wasabi"
        case .digitalocean: return "DigitalOcean Spaces"
        case .linode: return "Linode Object Storage"
        case .backblaze: return "Backblaze B2"
        case .cloudflare: return "Cloudflare R2"
        case .alibaba: return "Alibaba Cloud OSS"
        case .tencent: return "Tencent Cloud COS"
        case .huawei: return "Huawei Cloud OBS"
        case .oracle: return "Oracle Cloud Infrastructure"
        }
    }

    /// Whether this provider supports S3-compatible API.
    public var isS3Compatible: Bool {
        switch self {
        case .aws, .minio, .wasabi, .digitalocean, .linode, .cloudflare:
            return true
        case .gcp, .azure, .backblaze, .alibaba, .tencent, .huawei, .oracle:
            return false // These have different APIs but can be adapted
        }
    }

    /// Default region for the provider.
    public var defaultRegion: String {
        switch self {
        case .aws: return "us-east-1"
        case .gcp: return "us-central1"
        case .azure: return "eastus"
        case .minio: return "us-east-1"
        case .wasabi: return "us-east-1"
        case .digitalocean: return "nyc3"
        case .linode: return "us-east-1"
        case .backblaze: return "us-west-002"
        case .cloudflare: return "auto"
        case .alibaba: return "oss-cn-hangzhou"
        case .tencent: return "ap-beijing"
        case .huawei: return "cn-north-1"
        case .oracle: return "us-ashburn-1"
        }
    }

    /// Available regions for the provider.
    public var availableRegions: [String] {
        switch self {
        case .aws:
            return [
                "us-east-1", "us-east-2", "us-west-1", "us-west-2",
                "eu-west-1", "eu-west-2", "eu-central-1",
                "ap-southeast-1", "ap-southeast-2", "ap-northeast-1",
                "ca-central-1", "sa-east-1"
            ]
        case .gcp:
            return [
                "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
                "europe-central2", "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
                "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1", "asia-southeast1"
            ]
        case .azure:
            return [
                "eastus", "eastus2", "centralus", "northcentralus", "southcentralus", "westcentralus",
                "westus", "westus2", "canadacentral", "canadaeast",
                "northeurope", "westeurope", "uksouth", "ukwest",
                "eastasia", "southeastasia", "japaneast", "japanwest",
                "australiaeast", "australiasoutheast", "australiacentral"
            ]
        default:
            return [defaultRegion]
        }
    }
}

/// Configuration for a cloud provider connection.
public struct CloudConfig: Codable, Sendable {
    /// The cloud provider.
    public let provider: CloudProvider
    /// Access key or equivalent.
    public let accessKey: String
    /// Secret key or equivalent.
    public let secretKey: String
    /// Region for the provider.
    public let region: String
    /// Custom endpoint URL (optional, uses provider default if nil).
    public let customEndpoint: String?
    /// Additional provider-specific configuration.
    public let extraConfig: [String: String]

    public init(
        provider: CloudProvider,
        accessKey: String,
        secretKey: String,
        region: String? = nil,
        customEndpoint: String? = nil,
        extraConfig: [String: String] = [:]
    ) {
        self.provider = provider
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region ?? provider.defaultRegion
        self.customEndpoint = customEndpoint
        self.extraConfig = extraConfig
    }

    /// Creates an S3-compatible endpoint for this cloud configuration.
    public func toS3Endpoint() -> S3Endpoint {
        if let customEndpoint = customEndpoint {
            // Parse custom endpoint
            if let url = URL(string: customEndpoint) {
                let useSSL = url.scheme == "https"
                let port = url.port ?? (useSSL ? 443 : 80)
                return S3Endpoint(host: url.host ?? customEndpoint, port: port, useSSL: useSSL)
            }
        }

        // Use provider-specific default endpoints
        switch provider {
        case .aws:
            return S3Endpoint(host: "s3.\(region).amazonaws.com", port: 443, useSSL: true)
        case .minio:
            return S3Endpoint(host: "minio.\(region).minio.io", port: 443, useSSL: true)
        case .wasabi:
            return S3Endpoint(host: "s3.\(region).wasabisys.com", port: 443, useSSL: true)
        case .digitalocean:
            return S3Endpoint(host: "\(region).digitaloceanspaces.com", port: 443, useSSL: true)
        case .linode:
            return S3Endpoint(host: "\(region).linodeobjects.com", port: 443, useSSL: true)
        case .cloudflare:
            return S3Endpoint(host: "\(region).r2.cloudflarestorage.com", port: 443, useSSL: true)
        case .backblaze:
            return S3Endpoint(host: "s3.\(region).backblazeb2.com", port: 443, useSSL: true)
        default:
            // For non-S3 compatible providers, this would need adaptation
            return S3Endpoint(host: "storage.\(provider.rawValue).cloud", port: 443, useSSL: true)
        }
    }

    /// Validates the configuration.
    public func validate() throws {
        guard !accessKey.isEmpty else {
            throw CloudConfigError.emptyAccessKey
        }
        guard !secretKey.isEmpty else {
            throw CloudConfigError.emptySecretKey
        }
        guard provider.availableRegions.contains(region) else {
            throw CloudConfigError.invalidRegion(region: region, provider: provider)
        }
        if let customEndpoint = customEndpoint {
            guard URL(string: customEndpoint) != nil else {
                throw CloudConfigError.invalidEndpoint(endpoint: customEndpoint)
            }
        }
    }
}

/// Errors related to cloud configuration.
public enum CloudConfigError: Error, LocalizedError {
    case emptyAccessKey
    case emptySecretKey
    case invalidRegion(region: String, provider: CloudProvider)
    case invalidEndpoint(endpoint: String)

    public var errorDescription: String? {
        switch self {
        case .emptyAccessKey:
            return "Access key cannot be empty"
        case .emptySecretKey:
            return "Secret key cannot be empty"
        case .invalidRegion(let region, let provider):
            return "Region '\(region)' is not valid for provider \(provider.displayName)"
        case .invalidEndpoint(let endpoint):
            return "Invalid endpoint URL: \(endpoint)"
        }
    }
}

/// Multi-cloud client factory for creating appropriate clients.
public struct CloudClientFactory {
    /// Creates an S3-compatible client for the given cloud configuration.
    ///
    /// - Parameter config: Cloud configuration.
    /// - Returns: Configured S3Client.
    /// - Throws: Error if configuration is invalid or client creation fails.
    public static func createS3Client(
        config: CloudConfig,
        bucket: String? = nil,
        auditLogger: (any AuditLogStorage)? = nil,
        sessionId: String? = nil
    ) throws -> S3Client {
        try config.validate()

        let endpoint = config.toS3Endpoint()
        let client = S3Client(
            endpoint: endpoint,
            accessKey: config.accessKey,
            secretKey: config.secretKey,
            bucket: bucket,
            region: config.region,
            auditLogger: auditLogger,
            sessionId: sessionId
        )

        return client
    }

    /// Creates a cloud-specific client (for non-S3 compatible providers).
    ///
    /// - Parameters:
    ///   - config: Cloud configuration.
    ///   - bucket: Optional bucket/container name.
    /// - Returns: Cloud-specific client.
    /// - Throws: Error if provider is not supported or configuration is invalid.
    public static func createCloudClient(
        config: CloudConfig,
        bucket: String? = nil,
        auditLogger: (any AuditLogStorage)? = nil,
        sessionId: String? = nil
    ) throws -> any CloudClientProtocol {
        try config.validate()

        switch config.provider {
        case .aws, .minio, .wasabi, .digitalocean, .linode, .cloudflare, .backblaze:
            // These use S3-compatible API
            return try createS3Client(config: config, bucket: bucket, auditLogger: auditLogger, sessionId: sessionId)
        case .gcp:
            return try GCPClient(config: config, bucket: bucket)
        case .azure:
            return try AzureClient(config: config, bucket: bucket)
        default:
            throw CloudClientError.unsupportedProvider(config.provider)
        }
    }
}

/// Protocol for cloud storage clients.
public protocol CloudClientProtocol {
    /// Upload data to the cloud storage.
    func upload(key: String, data: Data) async throws

    /// Download data from cloud storage.
    func download(key: String) async throws -> Data

    /// List objects with optional prefix.
    func list(prefix: String?) async throws -> [CloudObject]

    /// Delete an object.
    func delete(key: String) async throws

    /// Check if an object exists.
    func exists(key: String) async throws -> Bool

    /// Get object metadata.
    func metadata(key: String) async throws -> CloudObjectMetadata

    /// Shutdown the client.
    func shutdown() async throws
}

/// Cloud object representation.
public struct CloudObject: Sendable {
    public let key: String
    public let size: Int64
    public let lastModified: Date
    public let etag: String?

    public init(key: String, size: Int64, lastModified: Date, etag: String? = nil) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
        self.etag = etag
    }
}

/// Cloud object metadata.
public struct CloudObjectMetadata: Sendable {
    public let key: String
    public let size: Int64
    public let lastModified: Date
    public let contentType: String?
    public let etag: String?
    public let metadata: [String: String]

    public init(
        key: String,
        size: Int64,
        lastModified: Date,
        contentType: String? = nil,
        etag: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
        self.contentType = contentType
        self.etag = etag
        self.metadata = metadata
    }
}

/// Errors for cloud client operations.
public enum CloudClientError: Error, LocalizedError {
    case unsupportedProvider(CloudProvider)
    case invalidConfiguration(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Provider \(provider.displayName) is not yet supported"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }
}