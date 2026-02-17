import Crypto
import Foundation
import AsyncHTTPClient

// MARK: - Date Formatter

private enum ISO8601DateFormatterFactory {
    static var formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

// MARK: - S3 Signer

/// Handles AWS Signature Version 4 signing for S3 requests.
public actor S3Signer {
    private let accessKey: String
    private let secretKey: String
    private let region: String
    private let service: String = "s3"

    private var iso8601DateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatterFactory.formatter
    }

    public init(accessKey: String, secretKey: String, region: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
    }

    /// Signs an HTTP request according to AWS V4 signature requirements.
    ///
    /// - Parameters:
    ///   - request: The HTTPClientRequest to modify with signature headers.
    ///   - url: The full URL of the request.
    ///   - method: The HTTP method (GET, PUT, etc.).
    ///   - bodyHash: The SHA256 hash of the request body (hex string). Use "UNSIGNED-PAYLOAD" if payload signing is skipped.
    ///   - headers: Additional headers to include in the signature.
    ///   - now: The timestamp to use for signing (defaults to current Date).
    public func sign(
        request: inout HTTPClientRequest,
        url: URL,
        method: String,
        bodyHash: String,
        headers: [String: String],
        now: Date = Date()
    ) async {
        let timestamp = iso8601DateFormatter.string(from: now)
        let dateStamp = String(timestamp.prefix(8))

        // 1. Prepare Headers
        request.headers.add(name: "Host", value: url.host ?? "")
        request.headers.add(name: "x-amz-date", value: timestamp)
        request.headers.add(name: "x-amz-content-sha256", value: bodyHash)

        for (k, v) in headers {
            request.headers.add(name: k, value: v)
        }

        // 2. Canonical Request
        // Headers for signing need to be sorted and lowercase
        var signedHeadersDict: [String: String] = [
            "host": url.host ?? "",
            "x-amz-date": timestamp,
            "x-amz-content-sha256": bodyHash
        ]

        for (k, v) in headers {
            signedHeadersDict[k.lowercased()] = v.trimmingCharacters(in: .whitespaces)
        }

        let signedHeadersKeys = signedHeadersDict.keys.sorted()
        let signedHeadersString = signedHeadersKeys.joined(separator: ";")

        let canonicalHeaders = signedHeadersKeys.map { key in
            "\(key):\(signedHeadersDict[key]!)"
        }.joined(separator: "\n")

        // Canonical Query - must use AWS-specific encoding
        // Use percentEncodedQuery to get the already-encoded query string,
        // then parse and re-sort it (since it's already properly encoded)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let canonicalQuery: String
        if let encodedQuery = components?.percentEncodedQuery, !encodedQuery.isEmpty {
            // Parse the already-encoded query string, sort by name, rejoin
            let pairs = encodedQuery.split(separator: "&").map { String($0) }
            let sortedPairs = pairs.sorted { pair1, pair2 in
                let name1 = pair1.split(separator: "=", maxSplits: 1).first ?? ""
                let name2 = pair2.split(separator: "=", maxSplits: 1).first ?? ""
                return name1 < name2
            }
            canonicalQuery = sortedPairs.joined(separator: "&")
        } else {
            canonicalQuery = ""
        }

        // Canonical Path - must use AWS-specific encoding
        // url.path returns decoded path, we need to re-encode it for signing
        let rawPath = url.path.isEmpty ? "/" : url.path
        let canonicalPath = rawPath.awsPathEncoded()

        let canonicalRequest = [
            method,
            canonicalPath,
            canonicalQuery,
            canonicalHeaders + "\n",
            signedHeadersString,
            bodyHash
        ].joined(separator: "\n")

        // 3. String to Sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            timestamp,
            credentialScope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        ].joined(separator: "\n")

        // 4. Signature
        let signingKey = getSignatureKey(secret: secretKey, dateStamp: dateStamp, region: region, service: service)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: signingKey)).hexString

        let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeadersString), Signature=\(signature)"
        request.headers.add(name: "Authorization", value: authHeader)
    }

    private func getSignatureKey(secret: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        let kSecret = SymmetricKey(data: Data("AWS4\(secret)".utf8))
        let kDate = HMAC<SHA256>.authenticationCode(for: Data(dateStamp.utf8), using: kSecret)
        let kRegion = HMAC<SHA256>.authenticationCode(for: Data(region.utf8), using: SymmetricKey(data: kDate))
        let kService = HMAC<SHA256>.authenticationCode(for: Data(service.utf8), using: SymmetricKey(data: kRegion))
        let kSigning = HMAC<SHA256>.authenticationCode(for: Data("aws4_request".utf8), using: SymmetricKey(data: kService))
        return SymmetricKey(data: kSigning)
    }
}