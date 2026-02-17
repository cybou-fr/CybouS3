import Foundation
import AsyncHTTPClient
import NIOFoundationCompat

/// Response structure for list objects operation
public struct ListObjectsResponse: Sendable {
    public let objects: [S3Object]
    public let isTruncated: Bool
    public let continuationToken: String?
}

/// Handles parsing of S3 XML responses and error responses.
public actor S3ResponseParser {

    /// Parses an S3 XML response for list buckets operation.
    public func parseListBuckets(data: Data) async throws -> [String] {
        let xml = try XMLDocument(data: data)
        return try xml.nodes(forXPath: "//ListAllMyBucketsResult/Buckets/Bucket/Name")
            .compactMap { $0.stringValue }
    }

    /// Parses an S3 XML response for list objects operation.
    public func parseListObjects(data: Data) async throws -> ListObjectsResponse {
        let xml = try XMLDocument(data: data)

        var objects: [S3Object] = []

        // Parse regular objects
        let objectNodes = try xml.nodes(forXPath: "//*[local-name()='Contents']")
        for node in objectNodes {
            guard let key = (try? node.nodes(forXPath: "*[local-name()='Key']").first)?.stringValue,
                  let lastModified = (try? node.nodes(forXPath: "*[local-name()='LastModified']").first)?.stringValue,
                  let sizeString = (try? node.nodes(forXPath: "*[local-name()='Size']").first)?.stringValue,
                  let size = Int(sizeString) else {
                continue
            }

            let etag = (try? node.nodes(forXPath: "*[local-name()='ETag']").first)?.stringValue

            // Use ISO8601DateFormatter for parsing
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]

            objects.append(S3Object(
                key: key,
                size: size,
                lastModified: dateFormatter.date(from: lastModified) ?? Date(),
                isDirectory: false,
                etag: etag
            ))
        }

        // Parse common prefixes (directories)
        let prefixNodes = try xml.nodes(forXPath: "//*[local-name()='CommonPrefixes']/*[local-name()='Prefix']")
        for node in prefixNodes {
            guard let prefix = node.stringValue else { continue }
            if !objects.contains(where: { $0.key == prefix && $0.isDirectory }) {
                objects.append(S3Object(
                    key: prefix,
                    size: 0,
                    lastModified: Date(),
                    isDirectory: true
                ))
            }
        }

        // Check for truncation
        let isTruncatedString = (try? xml.nodes(forXPath: "//*[local-name()='IsTruncated']").first)?
            .stringValue?.lowercased()
        let isTruncated = isTruncatedString == "true"
        
        let continuationToken = (try? xml.nodes(forXPath: "//*[local-name()='NextContinuationToken']").first)?
            .stringValue

        return ListObjectsResponse(
            objects: objects,
            isTruncated: isTruncated,
            continuationToken: continuationToken
        )
    }

    /// Parses an S3 XML response for create bucket operation.
    public func parseCreateBucket(data: Data) throws -> String {
        // Create bucket response typically contains Location header, but body might be empty
        // For now, return success message
        return "Bucket created successfully"
    }

    /// Parses an S3 XML response for delete bucket operation.
    public func parseDeleteBucket(data: Data) throws -> String {
        // Delete bucket response is typically empty
        return "Bucket deleted successfully"
    }

    /// Parses an S3 XML response for delete object operation.
    public func parseDeleteObject(data: Data) throws -> String {
        // Delete object response is typically empty
        return "Object deleted successfully"
    }
}

/// Handles S3 error responses and converts them to appropriate S3Error types.
public actor S3ErrorHandler {

    /// Processes an HTTP error response and converts it to an S3Error.
    public func handleErrorResponse(_ response: HTTPClientResponse) async throws -> S3Error {
        let body = try await response.body.collect(upTo: 1024 * 1024)
        let data = Data(buffer: body)
        return S3ErrorParser.parse(data: data, status: Int(response.status.code))
    }
}

/// Helper to parse S3 XML error responses.
struct S3ErrorParser {
    /// Parses an S3 XML error response and returns an appropriate S3Error.
    static func parse(data: Data, status: Int) -> S3Error {
        guard !data.isEmpty else {
            return .requestFailed(status: status, code: nil, message: "Empty response")
        }
        do {
            let xml = try XMLDocument(data: data)
            guard let root = xml.rootElement() else {
                throw NSError(domain: "XML", code: 0, userInfo: nil)
            }
            let code = (try? root.nodes(forXPath: "Code").first?.stringValue) ?? (try? xml.nodes(forXPath: "//Error/Code").first?.stringValue)
            let message = (try? root.nodes(forXPath: "Message").first?.stringValue) ?? (try? xml.nodes(forXPath: "//Error/Message").first?.stringValue)

            // Map common S3 error codes to specific errors
            switch code {
            case "AccessDenied":
                return .accessDenied(resource: nil)
            case "NoSuchBucket":
                return .bucketNotFound
            case "NoSuchKey":
                return .objectNotFound
            case "BucketNotEmpty":
                return .bucketNotEmpty
            case "InvalidAccessKeyId", "SignatureDoesNotMatch":
                return .authenticationFailed
            default:
                return .requestFailed(status: status, code: code, message: message)
            }
        } catch {
            // If we can't parse XML, return generic error with raw data
            let rawMessage = String(data: data, encoding: .utf8)
            return .requestFailed(status: status, code: nil, message: rawMessage)
        }
    }
}