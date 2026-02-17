import Foundation
import AsyncHTTPClient
import NIOHTTP1

// MARK: - URL Encoding Extensions

extension String {
    /// Encodes a string for use in AWS S3 URIs.
    /// AWS unreserved characters: A-Z a-z 0-9 - _ . ~
    func awsURIEncoded() -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    /// Encodes a string for use in AWS S3 URI paths, preserving forward slashes.
    /// Use this for object keys that contain path separators.
    func awsPathEncoded() -> String {
        // Split by /, encode each segment, rejoin with /
        return self.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).awsURIEncoded() }
            .joined(separator: "/")
    }

    /// Encodes a string for use in AWS S3 query parameter values.
    /// Forward slashes ARE encoded in query parameters.
    func awsQueryEncoded() -> String {
        return self.awsURIEncoded()
    }
}

/// Represents an S3 endpoint configuration.
public struct S3Endpoint: Sendable {
    /// The hostname of the S3 service (e.g., `s3.amazonaws.com`).
    public let host: String
    /// The port number (usually 443 for HTTPS or 80 for HTTP).
    public let port: Int
    /// Whether to use SSL/HTTPS.
    public let useSSL: Bool

    public init(host: String, port: Int, useSSL: Bool) {
        self.host = host
        self.port = port
        self.useSSL = useSSL
    }

    /// Returns "https" or "http" based on `useSSL`.
    public var scheme: String { useSSL ? "https" : "http" }

    /// Constructs a full URL from the endpoint components.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url
    }
}

/// Builds HTTP requests for S3 operations with proper URL encoding and signing.
public actor S3RequestBuilder {
    private let endpoint: S3Endpoint
    private let bucket: String?
    private let signer: S3Signer

    public init(endpoint: S3Endpoint, bucket: String?, signer: S3Signer) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.signer = signer
    }

    /// Builds and signs an HTTPClientRequest for S3.
    public func buildRequest(
        method: String,
        path: String = "/",
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: HTTPClientRequest.Body? = nil,
        bodyHash: String = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ) async throws -> HTTPClientRequest {
        guard let baseURL = endpoint.url else {
            throw S3Error.invalidURL
        }

        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if let bucket = bucket {
            urlComponents?.host = "\(bucket).\(endpoint.host)"
        }

        // Encode path using AWS-compatible encoding
        // We use percentEncodedPath to ensure the URL contains properly encoded characters
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        urlComponents?.percentEncodedPath = normalizedPath.awsPathEncoded()

        // Encode query items using AWS-compatible encoding
        if !queryItems.isEmpty {
            urlComponents?.percentEncodedQuery = queryItems
                .map { item in
                    let encodedName = item.name.awsQueryEncoded()
                    let encodedValue = (item.value ?? "").awsQueryEncoded()
                    return "\(encodedName)=\(encodedValue)"
                }
                .joined(separator: "&")
        }

        guard let url = urlComponents?.url else {
            throw S3Error.invalidURL
        }

        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = HTTPMethod(rawValue: method)
        if let body = body {
            request.body = body
        }

        await signer.sign(
            request: &request,
            url: url,
            method: method,
            bodyHash: bodyHash,
            headers: headers
        )

        return request
    }
}