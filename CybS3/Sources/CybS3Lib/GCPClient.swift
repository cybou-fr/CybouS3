import Foundation
import AsyncHTTPClient
import NIOFoundationCompat
import NIO

/// Google Cloud Storage client implementation.
public actor GCPClient: CloudClientProtocol {
    private let config: CloudConfig
    private let bucket: String?
    private let httpClient: HTTPClient
    private let baseURL: String

    /// Initializes a new GCP client.
    ///
    /// - Parameters:
    ///   - config: Cloud configuration for GCP.
    ///   - bucket: Optional bucket name.
    /// - Throws: Error if configuration is invalid.
    public init(config: CloudConfig, bucket: String?) throws {
        guard config.provider == .gcp else {
            throw CloudClientError.invalidConfiguration("GCPClient requires GCP provider")
        }

        self.config = config
        self.bucket = bucket
        self.baseURL = "https://storage.googleapis.com"

        var httpConfig = HTTPClient.Configuration()
        httpConfig.timeout = HTTPClient.Configuration.Timeout(
            connect: .seconds(10),
            read: .seconds(300)
        )

        self.httpClient = HTTPClient(
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup(numberOfThreads: 4)),
            configuration: httpConfig
        )
    }

    /// Upload data to Google Cloud Storage.
    public func upload(key: String, data: Data) async throws {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No bucket specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        var request = HTTPClientRequest(url: url)
        request.method = .PUT
        request.headers.add(name: "Authorization", value: "Bearer \(try await getAccessToken())")
        request.headers.add(name: "Content-Type", value: "application/octet-stream")
        request.body = .bytes(data)

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(300))
        guard response.status.code >= 200 && response.status.code < 300 else {
            throw CloudClientError.operationFailed("Upload failed with status \(response.status.code)")
        }
    }

    /// Download data from Google Cloud Storage.
    public func download(key: String) async throws -> Data {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No bucket specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Authorization", value: "Bearer \(try await getAccessToken())")

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(300))
        guard response.status.code == 200 else {
            throw CloudClientError.operationFailed("Download failed with status \(response.status.code)")
        }

        return try await response.body.collect(upTo: 100 * 1024 * 1024) // 100MB limit
    }

    /// List objects in the bucket.
    public func list(prefix: String?) async throws -> [CloudObject] {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No bucket specified")
        }

        var url = "\(baseURL)/\(bucket)?list-type=2"
        if let prefix = prefix {
            url += "&prefix=\(prefix.urlEncoded())"
        }

        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Authorization", value: "Bearer \(try await getAccessToken())")

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(30))
        guard response.status.code == 200 else {
            throw CloudClientError.operationFailed("List failed with status \(response.status.code)")
        }

        let data = try await response.body.collect(upTo: 1024 * 1024) // 1MB limit
        return try parseListResponse(Data(data.readableBytesView))
    }

    /// Delete an object from Google Cloud Storage.
    public func delete(key: String) async throws {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No bucket specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        var request = HTTPClientRequest(url: url)
        request.method = .DELETE
        request.headers.add(name: "Authorization", value: "Bearer \(try await getAccessToken())")

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(30))
        guard response.status.code >= 200 && response.status.code < 300 else {
            throw CloudClientError.operationFailed("Delete failed with status \(response.status.code)")
        }
    }

    /// Check if an object exists.
    public func exists(key: String) async throws -> Bool {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No bucket specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        var request = HTTPClientRequest(url: url)
        request.method = .HEAD
        request.headers.add(name: "Authorization", value: "Bearer \(try await getAccessToken())")

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(30))
        return response.status.code == 200
    }

    /// Get object metadata.
    public func metadata(key: String) async throws -> CloudObjectMetadata {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No bucket specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        var request = HTTPClientRequest(url: url)
        request.method = .HEAD
        request.headers.add(name: "Authorization", value: "Bearer \(try await getAccessToken())")

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(30))
        guard response.status.code == 200 else {
            throw CloudClientError.operationFailed("Metadata request failed with status \(response.status.code)")
        }

        let size = Int64(response.headers.first(name: "content-length") ?? "0") ?? 0
        let lastModified = parseDate(response.headers.first(name: "last-modified"))
        let contentType = response.headers.first(name: "content-type")
        let etag = response.headers.first(name: "etag")

        return CloudObjectMetadata(
            key: key,
            size: size,
            lastModified: lastModified ?? Date(),
            contentType: contentType,
            etag: etag
        )
    }

    /// Shutdown the client.
    public func shutdown() async throws {
        try await httpClient.shutdown()
    }

    // MARK: - Private Methods

    private func getAccessToken() async throws -> String {
        // For simplicity, this assumes the secretKey is actually a service account key
        // In production, this would implement proper OAuth2 flow with GCP
        // For now, we'll use a simplified approach
        return config.secretKey
    }

    private func parseListResponse(_ data: Data) throws -> [CloudObject] {
        // Parse GCP XML response
        // This is a simplified implementation
        let xmlString = String(data: data, encoding: .utf8) ?? ""

        var objects: [CloudObject] = []

        // Simple XML parsing (in production, use proper XML parser)
        let lines = xmlString.components(separatedBy: "\n")
        var currentObject: (key: String?, size: String?, lastModified: String?, etag: String?)?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.contains("<Contents>") {
                currentObject = (nil, nil, nil, nil)
            } else if trimmed.contains("</Contents>") {
                if let key = currentObject?.key,
                   let sizeString = currentObject?.size,
                   let size = Int64(sizeString),
                   let lastModifiedString = currentObject?.lastModified,
                   let lastModified = parseDate(lastModifiedString) {
                    objects.append(CloudObject(
                        key: key,
                        size: size,
                        lastModified: lastModified,
                        etag: currentObject?.etag
                    ))
                }
                currentObject = nil
            } else if let object = currentObject {
                if trimmed.hasPrefix("<Key>") && trimmed.hasSuffix("</Key>") {
                    currentObject?.key = trimmed.replacingOccurrences(of: "<Key>", with: "").replacingOccurrences(of: "</Key>", with: "")
                } else if trimmed.hasPrefix("<Size>") && trimmed.hasSuffix("</Size>") {
                    currentObject?.size = trimmed.replacingOccurrences(of: "<Size>", with: "").replacingOccurrences(of: "</Size>", with: "")
                } else if trimmed.hasPrefix("<LastModified>") && trimmed.hasSuffix("</LastModified>") {
                    currentObject?.lastModified = trimmed.replacingOccurrences(of: "<LastModified>", with: "").replacingOccurrences(of: "</LastModified>", with: "")
                } else if trimmed.hasPrefix("<ETag>") && trimmed.hasSuffix("</ETag>") {
                    currentObject?.etag = trimmed.replacingOccurrences(of: "<ETag>", with: "").replacingOccurrences(of: "</ETag>", with: "")
                }
            }
        }

        return objects
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.date(from: dateString)
    }
}

private extension String {
    func urlEncoded() -> String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}