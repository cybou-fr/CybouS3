import Foundation
import AsyncHTTPClient
import NIOFoundationCompat
import Crypto

/// Azure Blob Storage client implementation.
public actor AzureClient: CloudClientProtocol {
    private let config: CloudConfig
    private let bucket: String?
    private let httpClient: HTTPClient
    private let baseURL: String
    private let accountName: String

    /// Initializes a new Azure client.
    ///
    /// - Parameters:
    ///   - config: Cloud configuration for Azure.
    ///   - bucket: Optional container name.
    /// - Throws: Error if configuration is invalid.
    public init(config: CloudConfig, bucket: String?) throws {
        guard config.provider == .azure else {
            throw CloudClientError.invalidConfiguration("AzureClient requires Azure provider")
        }

        self.config = config
        self.bucket = bucket
        self.accountName = config.accessKey
        self.baseURL = "https://\(accountName).blob.core.windows.net"

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

    /// Upload data to Azure Blob Storage.
    public func upload(key: String, data: Data) async throws {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No container specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        let date = getCurrentDateString()

        var request = HTTPClientRequest(url: url)
        request.method = .PUT
        request.headers.add(name: "x-ms-blob-type", value: "BlockBlob")
        request.headers.add(name: "x-ms-date", value: date)
        request.headers.add(name: "x-ms-version", value: "2020-04-08")
        request.headers.add(name: "Content-Type", value: "application/octet-stream")
        request.headers.add(name: "Authorization", value: try createAuthorizationHeader(request: request, date: date))
        request.body = .bytes(data)

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(300))
        guard response.status.code >= 200 && response.status.code < 300 else {
            throw CloudClientError.operationFailed("Upload failed with status \(response.status.code)")
        }
    }

    /// Download data from Azure Blob Storage.
    public func download(key: String) async throws -> Data {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No container specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        let date = getCurrentDateString()

        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "x-ms-date", value: date)
        request.headers.add(name: "x-ms-version", value: "2020-04-08")
        request.headers.add(name: "Authorization", value: try createAuthorizationHeader(request: request, date: date))

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(300))
        guard response.status.code == 200 else {
            throw CloudClientError.operationFailed("Download failed with status \(response.status.code)")
        }

        return try await response.body.collect(upTo: 100 * 1024 * 1024) // 100MB limit
    }

    /// List blobs in the container.
    public func list(prefix: String?) async throws -> [CloudObject] {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No container specified")
        }

        var url = "\(baseURL)/\(bucket)?restype=container&comp=list"
        if let prefix = prefix {
            url += "&prefix=\(prefix.urlEncoded())"
        }

        let date = getCurrentDateString()
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "x-ms-date", value: date)
        request.headers.add(name: "x-ms-version", value: "2020-04-08")
        request.headers.add(name: "Authorization", value: try createAuthorizationHeader(request: request, date: date))

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(30))
        guard response.status.code == 200 else {
            throw CloudClientError.operationFailed("List failed with status \(response.status.code)")
        }

        let data = try await response.body.collect(upTo: 1024 * 1024) // 1MB limit
        return try parseListResponse(data)
    }

    /// Delete a blob from Azure Blob Storage.
    public func delete(key: String) async throws {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No container specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        let date = getCurrentDateString()

        var request = HTTPClientRequest(url: url)
        request.method = .DELETE
        request.headers.add(name: "x-ms-date", value: date)
        request.headers.add(name: "x-ms-version", value: "2020-04-08")
        request.headers.add(name: "Authorization", value: try createAuthorizationHeader(request: request, date: date))

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(30))
        guard response.status.code >= 200 && response.status.code < 300 else {
            throw CloudClientError.operationFailed("Delete failed with status \(response.status.code)")
        }
    }

    /// Check if a blob exists.
    public func exists(key: String) async throws -> Bool {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No container specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        let date = getCurrentDateString()

        var request = HTTPClientRequest(url: url)
        request.method = .HEAD
        request.headers.add(name: "x-ms-date", value: date)
        request.headers.add(name: "x-ms-version", value: "2020-04-08")
        request.headers.add(name: "Authorization", value: try createAuthorizationHeader(request: request, date: date))

        let response = try await httpClient.execute(request, deadline: .now() + .seconds(30))
        return response.status.code == 200
    }

    /// Get blob metadata.
    public func metadata(key: String) async throws -> CloudObjectMetadata {
        guard let bucket = bucket else {
            throw CloudClientError.operationFailed("No container specified")
        }

        let url = "\(baseURL)/\(bucket)/\(key.urlEncoded())"
        let date = getCurrentDateString()

        var request = HTTPClientRequest(url: url)
        request.method = .HEAD
        request.headers.add(name: "x-ms-date", value: date)
        request.headers.add(name: "x-ms-version", value: "2020-04-08")
        request.headers.add(name: "Authorization", value: try createAuthorizationHeader(request: request, date: date))

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

    private func createAuthorizationHeader(request: HTTPClientRequest, date: String) throws -> String {
        // Azure Shared Key authentication
        let canonicalizedHeaders = createCanonicalizedHeaders(request: request, date: date)
        let canonicalizedResource = createCanonicalizedResource(request: request)

        let stringToSign = """
        \(request.method.rawValue)\n\
        \n\
        \n\
        \n\
        \n\
        \n\
        \n\
        \n\
        \n\
        \n\
        \n\
        \n\
        \(canonicalizedHeaders)\(canonicalizedResource)
        """

        let signature = try createSignature(stringToSign: stringToSign)
        return "SharedKey \(accountName):\(signature)"
    }

    private func createCanonicalizedHeaders(request: HTTPClientRequest, date: String) -> String {
        var headers = [String: String]()
        for header in request.headers {
            let lowerKey = header.name.lowercased()
            if lowerKey.hasPrefix("x-ms-") {
                headers[lowerKey] = header.value
            }
        }
        headers["x-ms-date"] = date

        return headers.sorted(by: { $0.key < $1.key })
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "\n") + "\n"
    }

    private func createCanonicalizedResource(request: HTTPClientRequest) -> String {
        guard let url = URL(string: request.url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return ""
        }

        let account = accountName
        let container = components.path.components(separatedBy: "/").dropFirst().first ?? ""
        let blob = components.path.components(separatedBy: "/").dropFirst(2).joined(separator: "/")

        var resource = "/\(account)/\(container)"
        if !blob.isEmpty {
            resource += "/\(blob)"
        }

        // Add query parameters
        if let queryItems = components.queryItems {
            for item in queryItems.sorted(by: { $0.name < $1.name }) {
                resource += "\n\(item.name.lowercased()):\(item.value ?? "")"
            }
        }

        return resource
    }

    private func createSignature(stringToSign: String) throws -> String {
        let key = Data(base64Encoded: config.secretKey) ?? Data()
        let data = stringToSign.data(using: .utf8) ?? Data()

        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac).base64EncodedString()
    }

    private func parseListResponse(_ data: Data) throws -> [CloudObject] {
        // Parse Azure XML response
        let xmlString = String(data: data, encoding: .utf8) ?? ""

        var objects: [CloudObject] = []

        // Simple XML parsing (in production, use proper XML parser)
        let lines = xmlString.components(separatedBy: "\n")
        var currentObject: (name: String?, size: String?, lastModified: String?, etag: String?)?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.contains("<Blob>") {
                currentObject = (nil, nil, nil, nil)
            } else if trimmed.contains("</Blob>") {
                if let name = currentObject?.name,
                   let sizeString = currentObject?.size,
                   let size = Int64(sizeString),
                   let lastModifiedString = currentObject?.lastModified,
                   let lastModified = parseDate(lastModifiedString) {
                    objects.append(CloudObject(
                        key: name,
                        size: size,
                        lastModified: lastModified,
                        etag: currentObject?.etag
                    ))
                }
                currentObject = nil
            } else if let object = currentObject {
                if trimmed.hasPrefix("<Name>") && trimmed.hasSuffix("</Name>") {
                    currentObject?.name = trimmed.replacingOccurrences(of: "<Name>", with: "").replacingOccurrences(of: "</Name>", with: "")
                } else if trimmed.hasPrefix("<Content-Length>") && trimmed.hasSuffix("</Content-Length>") {
                    currentObject?.size = trimmed.replacingOccurrences(of: "<Content-Length>", with: "").replacingOccurrences(of: "</Content-Length>", with: "")
                } else if trimmed.hasPrefix("<Last-Modified>") && trimmed.hasSuffix("</Last-Modified>") {
                    currentObject?.lastModified = trimmed.replacingOccurrences(of: "<Last-Modified>", with: "").replacingOccurrences(of: "</Last-Modified>", with: "")
                } else if trimmed.hasPrefix("<Etag>") && trimmed.hasSuffix("</Etag>") {
                    currentObject?.etag = trimmed.replacingOccurrences(of: "<Etag>", with: "").replacingOccurrences(of: "</Etag>", with: "")
                }
            }
        }

        return objects
    }

    private func getCurrentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
}

private extension String {
    func urlEncoded() -> String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}</content>
<parameter name="filePath">/Users/cybou/Documents/CybouS3/CybS3/Sources/CybS3Lib/AzureClient.swift