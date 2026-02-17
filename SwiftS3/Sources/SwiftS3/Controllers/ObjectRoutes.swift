import Foundation
import Hummingbird
import HTTPTypes
import Logging
import NIO

extension S3Controller {
    /// Registers object-related routes.
    func addObjectRoutes(to router: some Router<S3RequestContext>) {
        // Object Operations
        // Recursive wildcard for key
        router.put(":bucket/**", use: { request, context in
            try await self.putObject(request: request, context: context)
        })
        router.get(":bucket/**", use: { request, context in
            try await self.getObject(request: request, context: context)
        })
        router.delete(":bucket/**", use: { request, context in
            try await self.deleteObject(request: request, context: context)
        })
        router.head(":bucket/**", use: { request, context in
            try await self.headObject(request: request, context: context)
        })
        router.post(":bucket", use: { request, context in
            try await self.postObject(
                request: request, context: context, isBucketOperation: true)
        })
        router.post(":bucket/**", use: { request, context in
            try await self.postObject(
                request: request, context: context, isBucketOperation: false)
        })
    }

    /// Handles PUT /:bucket/:key requests to upload or copy objects.
    @Sendable func putObject(request: Request, context: S3RequestContext) async throws -> Response {
        let (bucket, key) = try parsePath(request.uri.path)

        // Validate key length (S3 limit is 1024 bytes)
        guard key.utf8.count <= 1024 else {
            throw S3Error.invalidArgument
        }

        // Check if this is an ACL operation
        if request.uri.queryParameters.get("acl") != nil {
            return try await putObjectACL(bucket: bucket, key: key, request: request, context: context)
        }

        // Check if this is a Tagging operation
        if request.uri.queryParameters.get("tagging") != nil {
            return try await putObjectTagging(bucket: bucket, key: key, request: request, context: context)
        }

        try await checkAccess(bucket: bucket, key: key, action: "s3:PutObject", request: request, context: context)

        // Check for Upload Part
        let query = parseQuery(request.uri.query)

        if let partNumberStr = query["partNumber"], let uploadId = query["uploadId"],
            let partNumber = Int(partNumberStr)
        {
            // Check for copy source
            if let copySource = request.headers[HTTPField.Name("x-amz-copy-source")!] {
                var source = copySource
                if source.hasPrefix("/") {
                    source.removeFirst()
                }
                
                // Parse range if present
                var range: ValidatedRange? = nil
                if let copyRange = request.headers[HTTPField.Name("x-amz-copy-source-range")!] {
                    let rangeStr = copyRange.replacingOccurrences(of: "bytes=", with: "")
                    let parts = rangeStr.split(separator: "-")
                    if parts.count == 2, let start = Int64(parts[0]), let end = Int64(parts[1]) {
                        range = ValidatedRange(start: start, end: end)
                    }
                }
                
                let etag = try await storage.uploadPartCopy(
                    bucket: bucket, key: key, uploadId: uploadId, partNumber: partNumber,
                    copySource: source, range: range)
                return Response(status: .ok, headers: [.eTag: etag])
            } else {
                let contentLength = request.headers[.contentLength].flatMap { Int64($0) }
                let etag = try await storage.uploadPart(
                    bucket: bucket, key: key, uploadId: uploadId, partNumber: partNumber,
                    data: request.body, size: contentLength)
                return Response(status: .ok, headers: [.eTag: etag])
            }
        }

        // Check for Copy Source
        if let copySource = request.headers[HTTPField.Name("x-amz-copy-source")!] {
            var source = copySource
            if source.hasPrefix("/") {
                source.removeFirst()
            }
            let components = source.split(separator: "/", maxSplits: 1)
            guard components.count == 2 else {
                throw S3Error.invalidRequest
            }
            let srcBucket = String(components[0])
            let srcKey = String(components[1])

            let metadata = try await storage.copyObject(
                fromBucket: srcBucket, fromKey: srcKey, toBucket: bucket, toKey: key,
                owner: context.principal ?? "admin")

            let xml = XML.copyObjectResult(metadata: metadata)
            return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
        }

        // Extract Metadata
        var metadata: [String: String] = [:]
        for field in request.headers {
            let name = field.name.canonicalName.lowercased()
            if name.starts(with: "x-amz-meta-") {
                metadata[name] = field.value
            }
        }
        if let contentType = request.headers[.contentType] {
            metadata["Content-Type"] = contentType
        }

        let contentLength = request.headers[.contentLength].flatMap { Int64($0) }

        // Stream body
        let metadataResult = try await storage.putObject(
            bucket: bucket, key: key, data: request.body, size: contentLength, metadata: metadata,
            owner: context.principal ?? "admin")
        let etag = metadataResult.eTag ?? ""

        if let declaredHash = request.headers[HTTPField.Name("x-amz-content-sha256")!],
            declaredHash != "UNSIGNED-PAYLOAD",
            declaredHash != "STREAMING-AWS4-HMAC-SHA256-PAYLOAD"
        {
            if declaredHash != etag {
                _ = try? await storage.deleteObject(
                    bucket: bucket, key: key, versionId: metadataResult.versionId)
                logger.error(
                    "Checksum mismatch",
                    metadata: [
                        "bucket": "\(bucket)", "key": "\(key)",
                        "declared": "\(declaredHash)", "computed": "\(etag)",
                    ])
                throw S3Error.xAmzContentSHA256Mismatch
            }
        }

        // Handle ACL (Canned or Default)
        let ownerID = context.principal ?? "admin"
        let acl = parseCannedACL(headers: request.headers, ownerID: ownerID)
            ?? CannedACL.privateACL.createPolicy(owner: Owner(id: ownerID))

        try await storage.putACL(bucket: bucket, key: key, versionId: metadataResult.versionId, acl: acl)

        var headers: HTTPFields = [.eTag: etag]
        if metadataResult.versionId != "null" {
            headers[HTTPField.Name("x-amz-version-id")!] = metadataResult.versionId
        }

        logger.info("Object uploaded", metadata: ["bucket": "\(bucket)", "key": "\(key)", "etag": "\(etag)"])

        // Publish event notification
        try await storage.publishEvent(bucket: bucket, event: .objectCreatedPut, key: key, metadata: metadataResult, userIdentity: context.principal, sourceIPAddress: nil)

        return Response(status: .ok, headers: headers)
    }

    /// Handles POST requests for multipart uploads and other bucket/object operations.
    @Sendable func postObject(request: Request, context: S3RequestContext, isBucketOperation: Bool) async throws -> Response {
        let bucket: String
        let key: String

        if isBucketOperation {
            bucket = try context.parameters.require("bucket")
            key = ""
        } else {
            (bucket, key) = try parsePath(request.uri.path)
        }

        let query = parseQuery(request.uri.query)

        if query.keys.contains("uploads") {
            // Initiate Multipart Upload
            var metadata: [String: String] = [:]
            for field in request.headers {
                let name = field.name.canonicalName.lowercased()
                if name.starts(with: "x-amz-meta-") {
                    metadata[name] = field.value
                }
            }
            if let contentType = request.headers[.contentType] {
                metadata["Content-Type"] = contentType
            }

            try await checkAccess(bucket: bucket, key: key, action: "s3:PutObject", request: request, context: context)

            let uploadId = try await storage.createMultipartUpload(
                bucket: bucket, key: key, metadata: metadata,
                owner: context.principal ?? "admin")
            let xml = XML.initiateMultipartUploadResult(
                bucket: bucket, key: key, uploadId: uploadId)
            return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
        } else if let uploadId = query["uploadId"] {
            // Complete Multipart Upload
            try await checkAccess(bucket: bucket, key: key, action: "s3:PutObject", request: request, context: context)

            var buffer = ByteBuffer()
            for try await var chunk in request.body {
                buffer.writeBuffer(&chunk)
            }
            let xmlStr = String(buffer: buffer)
            let parts = XML.parseCompleteMultipartUpload(xml: xmlStr)

            let eTag = try await storage.completeMultipartUpload(
                bucket: bucket, key: key, uploadId: uploadId, parts: parts)
            let location = "http://localhost:8080/\(bucket)/\(key)"
            let resultXml = XML.completeMultipartUploadResult(
                bucket: bucket, key: key, eTag: eTag, location: location)
            return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: resultXml)))
        } else if query.keys.contains("delete") {
            // Delete Objects
            try await checkAccess(bucket: bucket, key: nil, action: "s3:DeleteObject", request: request, context: context)

            // Check MFA delete requirement
            if let versioning = try await storage.getBucketVersioning(bucket: bucket),
               versioning.mfaDelete == true {
                guard let mfaHeader = request.headers[HTTPField.Name("x-amz-mfa")!],
                      !mfaHeader.isEmpty else {
                    throw S3Error.accessDenied
                }
            }

            var buffer = ByteBuffer()
            for try await var chunk in request.body {
                buffer.writeBuffer(&chunk)
            }
            let xmlStr = String(buffer: buffer)
            let objects = XML.parseDeleteObjects(xml: xmlStr)

            let deleted = try await storage.deleteObjects(bucket: bucket, objects: objects)
            let resultXml = XML.deleteResult(deleted: deleted, errors: [])

            return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: resultXml)))
        } else if query.keys.contains("select") {
            // S3 Select
            try await checkAccess(bucket: bucket, key: key, action: "s3:GetObject", request: request, context: context)

            let buffer = try await request.body.collect(upTo: 1024 * 1024)
            
            struct SelectRequest: Codable {
                let Expression: String
                let ExpressionType: String
                let InputSerialization: InputSerialization
                let OutputSerialization: OutputSerialization
            }
            
            struct InputSerialization: Codable {
                let CSV: CSVInput?
                let JSON: JSONInput?
            }
            
            struct CSVInput: Codable {
                let FileHeaderInfo: String?
            }
            
            struct JSONInput: Codable {
                let `Type`: String?
            }
            
            struct OutputSerialization: Codable {
                let CSV: CSVOutput?
                let JSON: JSONOutput?
            }
            
            struct CSVOutput: Codable {}
            
            struct JSONOutput: Codable {
                let RecordDelimiter: String?
            }
            
            let selectReq: SelectRequest
            do {
                selectReq = try JSONDecoder().decode(SelectRequest.self, from: Data(buffer.readableBytesView))
            } catch {
                throw S3Error.malformedPolicy
            }
            
            let (_, bodyStream) = try await storage.getObject(bucket: bucket, key: key, versionId: nil, range: nil)
            var data = Data()
            if let body = bodyStream {
                for try await buffer in body {
                    data.append(contentsOf: buffer.readableBytesView)
                }
            }
            let content = String(data: data, encoding: .utf8) ?? ""
            
            guard selectReq.Expression.uppercased() == "SELECT * FROM S3OBJECT" else {
                throw S3Error.invalidArgument
            }
            
            var result: String
            if selectReq.InputSerialization.CSV != nil {
                result = content
            } else {
                throw S3Error.invalidArgument
            }
            
            if selectReq.OutputSerialization.CSV != nil {
                // Already CSV
            } else if let json = selectReq.OutputSerialization.JSON {
                let lines = result.split(separator: "\n")
                let delimiter = json.RecordDelimiter ?? "\n"
                result = lines.map { "{\"record\": \"\($0)\"}" }.joined(separator: delimiter)
            }
            
            return Response(status: .ok, headers: [.contentType: "application/octet-stream"], body: .init(byteBuffer: ByteBuffer(string: result)))
        }

        return Response(status: .badRequest)
    }

    /// Handles GET /:bucket/:key requests to download objects.
    @Sendable func getObject(request: Request, context: S3RequestContext) async throws -> Response {
        let (bucket, key) = try parsePath(request.uri.path)

        if request.uri.queryParameters.get("acl") != nil {
            return try await getObjectACL(bucket: bucket, key: key, context: context, request: request)
        }
        if request.uri.queryParameters.get("tagging") != nil {
            return try await getObjectTagging(bucket: bucket, key: key, context: context, request: request)
        }

        try await checkAccess(bucket: bucket, key: key, action: "s3:GetObject", request: request, context: context)

        // Parse Range Header
        var range: ValidatedRange? = nil
        if let rangeHeader = request.headers[.range] {
            if rangeHeader.starts(with: "bytes=") {
                let value = rangeHeader.dropFirst(6)
                let components = value.split(separator: "-", omittingEmptySubsequences: false)
                if components.count == 2 {
                    let startStr = String(components[0])
                    let endStr = String(components[1])

                    let rangeHeaderQuery = parseQuery(request.uri.query)
                    let versionId = rangeHeaderQuery["versionId"]

                    let metadata = try await storage.getObjectMetadata(bucket: bucket, key: key, versionId: versionId)
                    let objectSize = metadata.size

                    var start: Int64 = 0
                    var end: Int64 = objectSize - 1

                    if startStr.isEmpty && !endStr.isEmpty {
                        if let suffix = Int64(endStr) {
                            start = max(0, objectSize - suffix)
                        }
                    } else if !startStr.isEmpty && endStr.isEmpty {
                        if let s = Int64(startStr) {
                            start = s
                        }
                    } else if let s = Int64(startStr), let e = Int64(endStr) {
                        start = s
                        end = min(e, objectSize - 1)
                    }

                    if start <= end {
                        range = ValidatedRange(start: start, end: end)
                    } else {
                        return Response(status: .rangeNotSatisfiable, headers: [
                            .contentRange: "bytes */\(objectSize)",
                            .contentLength: "0"
                        ])
                    }
                }
            }
        }

        let query = parseQuery(request.uri.query)
        let versionId = query["versionId"]

        let (metadata, body) = try await storage.getObject(bucket: bucket, key: key, versionId: versionId, range: range)

        var headers: HTTPFields = [
            .lastModified: ISO8601DateFormatter().string(from: metadata.lastModified),
            .contentType: metadata.contentType ?? "application/octet-stream",
        ]

        let contentLength: Int64
        if let range = range {
            contentLength = range.end - range.start + 1
            headers[.contentRange] = "bytes \(range.start)-\(range.end)/\(metadata.size)"
        } else {
            contentLength = metadata.size
        }
        headers[.contentLength] = String(contentLength)

        if let etag = metadata.eTag {
            headers[.eTag] = etag
        }
        if metadata.versionId != "null" {
            headers[HTTPField.Name("x-amz-version-id")!] = metadata.versionId
        }

        for (k, v) in metadata.customMetadata {
            if let name = HTTPField.Name(k) {
                headers[name] = v
            }
        }

        let status: HTTPResponse.Status = range != nil ? .partialContent : .ok

        if let body = body {
            return Response(status: status, headers: headers, body: .init(asyncSequence: body))
        } else {
            return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer()))
        }
    }

    /// Handles DELETE /:bucket/:key requests to delete objects.
    @Sendable func deleteObject(request: Request, context: S3RequestContext) async throws -> Response {
        let (bucket, key) = try parsePath(request.uri.path)
        try await checkAccess(bucket: bucket, key: key, action: "s3:DeleteObject", request: request, context: context)
        let query = parseQuery(request.uri.query)

        // Check MFA delete requirement
        if let versioning = try await storage.getBucketVersioning(bucket: bucket),
           versioning.mfaDelete == true {
            guard let mfaHeader = request.headers[HTTPField.Name("x-amz-mfa")!],
                  !mfaHeader.isEmpty else {
                throw S3Error.accessDenied
            }
        }

        if request.uri.queryParameters.get("tagging") != nil {
            return try await deleteObjectTagging(bucket: bucket, key: key, request: request, context: context)
        }

        if let uploadId = query["uploadId"] {
            try await storage.abortMultipartUpload(bucket: bucket, key: key, uploadId: uploadId)
            return Response(status: .noContent)
        }

        let result = try await storage.deleteObject(bucket: bucket, key: key, versionId: query["versionId"])
        logger.info("Object deleted", metadata: ["bucket": "\(bucket)", "key": "\(key)"])

        // Publish event notification
        try await storage.publishEvent(bucket: bucket, event: .objectRemovedDelete, key: key, metadata: nil, userIdentity: context.principal, sourceIPAddress: nil)

        var headers: HTTPFields = [:]
        if let vid = result.versionId, vid != "null" {
            headers[HTTPField.Name("x-amz-version-id")!] = vid
        }
        if result.isDeleteMarker {
            headers[HTTPField.Name("x-amz-delete-marker")!] = "true"
        }

        return Response(status: .noContent, headers: headers)
    }

    /// Handles HEAD /:bucket/:key requests to get object metadata.
    @Sendable func headObject(request: Request, context: S3RequestContext) async throws -> Response {
        let (bucket, key) = try parsePath(request.uri.path)
        try await checkAccess(bucket: bucket, key: key, action: "s3:GetObject", request: request, context: context)

        let query = parseQuery(request.uri.query)
        let metadata = try await storage.getObjectMetadata(bucket: bucket, key: key, versionId: query["versionId"])

        var headers: HTTPFields = [
            .lastModified: ISO8601DateFormatter().string(from: metadata.lastModified),
            .contentLength: String(metadata.size),
            .contentType: metadata.contentType ?? "application/octet-stream",
        ]
        if let etag = metadata.eTag {
            headers[.eTag] = etag
        }
        if metadata.versionId != "null" {
            headers[HTTPField.Name("x-amz-version-id")!] = metadata.versionId
        }

        for (k, v) in metadata.customMetadata {
            if let name = HTTPField.Name(k) {
                headers[name] = v
            }
        }

        return Response(status: .ok, headers: headers)
    }

    /// Retrieves object ACL.
    func getObjectACL(bucket: String, key: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, key: key, action: "s3:GetObjectAcl", request: request, context: context)
        let query = parseQuery(request.uri.query)
        let acl = try await storage.getACL(bucket: bucket, key: key, versionId: query["versionId"])
        let xml = XML.accessControlPolicy(policy: acl)
        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Updates object ACL.
    func putObjectACL(bucket: String, key: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, key: key, action: "s3:PutObjectAcl", request: request, context: context)

        let query = parseQuery(request.uri.query)
        if let acl = parseCannedACL(headers: request.headers, ownerID: context.principal ?? "anonymous") {
            try await storage.putACL(bucket: bucket, key: key, versionId: query["versionId"], acl: acl)
            return Response(status: .ok)
        }

        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        if buffer.readableBytes > 0 {
            let xmlString = String(buffer: buffer)
            let acl = XML.parseAccessControlPolicy(xml: xmlString)
            try await storage.putACL(bucket: bucket, key: key, versionId: query["versionId"], acl: acl)
            return Response(status: .ok)
        }

        logger.warning("No ACL specified.")
        throw S3Error.invalidArgument
    }

    /// Retrieves object tags.
    func getObjectTagging(bucket: String, key: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, key: key, action: "s3:GetObjectTagging", request: request, context: context)
        let query = parseQuery(request.uri.query)
        let tags = try await storage.getTags(bucket: bucket, key: key, versionId: query["versionId"])
        let xml = XML.taggingConfiguration(tags: tags)
        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Updates object tags.
    func putObjectTagging(bucket: String, key: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, key: key, action: "s3:PutObjectTagging", request: request, context: context)
        let query = parseQuery(request.uri.query)
        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        let tags = XML.parseTagging(xml: String(buffer: buffer))
        try await storage.putTags(bucket: bucket, key: key, versionId: query["versionId"], tags: tags)
        return Response(status: .ok)
    }

    /// Deletes object tags.
    func deleteObjectTagging(bucket: String, key: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, key: key, action: "s3:PutObjectTagging", request: request, context: context)
        let query = parseQuery(request.uri.query)
        try await storage.deleteTags(bucket: bucket, key: key, versionId: query["versionId"])
        return Response(status: .noContent)
    }
}
