import Foundation
import Hummingbird
import HTTPTypes
import Logging
import NIO

extension S3Controller {
    /// Registers bucket-related routes.
    func addBucketRoutes(to router: some Router<S3RequestContext>) {
        // List Buckets (Service)
        router.get("/", use: { request, context in
            try await self.listBuckets(request: request, context: context)
        })

        // Bucket Operations
        router.put(":bucket", use: { request, context in
            try await self.createBucket(request: request, context: context)
        })
        router.delete(":bucket", use: { request, context in
            try await self.deleteBucket(request: request, context: context)
        })
        router.head(":bucket", use: { request, context in
            try await self.headBucket(request: request, context: context)
        })
        router.get(":bucket", use: { request, context in
            try await self.listObjects(request: request, context: context)
        })
    }

    /// Validates bucket name according to AWS S3 rules.
    func isValidBucketName(_ name: String) -> Bool {
        // Bucket names must be between 3 and 63 characters long
        guard (3...63).contains(name.count) else { return false }

        // Bucket names can consist only of lowercase letters, numbers, hyphens, and periods
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard name.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else { return false }

        // Bucket names must begin and end with a letter or number
        guard let first = name.first, let last = name.last else { return false }
        let alphanumeric = CharacterSet.alphanumerics
        guard alphanumeric.contains(first.unicodeScalars.first!) &&
              alphanumeric.contains(last.unicodeScalars.first!) else { return false }

        // Bucket names cannot contain two adjacent periods
        guard !name.contains("..") else { return false }

        // Bucket names cannot be formatted as an IP address
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        guard name.range(of: ipPattern, options: .regularExpression) == nil else { return false }

        return true
    }

    /// Handles GET / requests to list all buckets owned by the authenticated user.
    @Sendable func listBuckets(request: Request, context: S3RequestContext) async throws -> Response {
        let buckets = try await storage.listBuckets()
        let xml = XML.listBuckets(buckets: buckets)
        let headers: HTTPFields = [.contentType: "application/xml"]
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Handles PUT /:bucket requests to create a new bucket.
    @Sendable func createBucket(request: Request, context: S3RequestContext) async throws -> Response {
        let bucket = try context.parameters.require("bucket")

        // Validate bucket name according to AWS S3 rules
        if !isValidBucketName(bucket) {
            throw S3Error.invalidBucketName
        }

        // Check if this is a Policy operation
        if request.uri.queryParameters.get("policy") != nil {
            return try await putBucketPolicy(bucket: bucket, request: request, context: context)
        }
        // Check if this is an ACL operation
        if request.uri.queryParameters.get("acl") != nil {
            return try await putBucketACL(bucket: bucket, request: request, context: context)
        }

        // Check if this is a Versioning operation
        if request.uri.queryParameters.get("versioning") != nil {
            return try await putBucketVersioning(bucket: bucket, request: request, context: context)
        }

        // Check if this is a Tagging operation
        if request.uri.queryParameters.get("tagging") != nil {
            return try await putBucketTagging(bucket: bucket, request: request, context: context)
        }

        // Check if this is a Lifecycle operation
        if request.uri.queryParameters.get("lifecycle") != nil {
            return try await putBucketLifecycle(bucket: bucket, request: request, context: context)
        }

        // Check if this is a VPC configuration operation
        if request.uri.queryParameters.get("vpc") != nil {
            return try await putBucketVpcConfiguration(bucket: bucket, request: request, context: context)
        }

        // Check if this is a Notification operation
        if request.uri.queryParameters.get("notification") != nil {
            return try await putBucketNotification(bucket: bucket, request: request, context: context)
        }

        let ownerID = context.principal ?? "admin"
        try await storage.createBucket(name: bucket, owner: ownerID)

        // Handle ACL (Canned or Default)
        let acl = parseCannedACL(headers: request.headers, ownerID: ownerID)
            ?? CannedACL.privateACL.createPolicy(owner: Owner(id: ownerID))

        try await storage.putACL(bucket: bucket, key: nil, versionId: nil as String?, acl: acl)

        logger.info("Bucket created", metadata: ["bucket": "\(bucket)"])
        return Response(status: .ok, headers: [.contentLength: "0"], body: .init(byteBuffer: ByteBuffer()))
    }

    /// Configures versioning settings for a bucket.
    func putBucketVersioning(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutBucketVersioning", request: request, context: context)

        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        let xmlStr = String(buffer: buffer)

        var status: VersioningConfiguration.Status = .suspended
        if xmlStr.contains(">Enabled<") {
            status = .enabled
        }
        
        var mfaDelete: Bool? = nil
        if xmlStr.contains("<MfaDelete>Enabled</MfaDelete>") {
            mfaDelete = true
        } else if xmlStr.contains("<MfaDelete>Disabled</MfaDelete>") {
            mfaDelete = false
        }
        
        let config = VersioningConfiguration(status: status, mfaDelete: mfaDelete)

        try await storage.putBucketVersioning(bucket: bucket, configuration: config)
        logger.info("Bucket versioning updated", metadata: ["bucket": "\(bucket)"])
        return Response(status: .ok)
    }

    /// Sets or updates the bucket policy.
    func putBucketPolicy(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutBucketPolicy", request: request, context: context)

        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        
        let policy: BucketPolicy
        do {
            policy = try JSONDecoder().decode(BucketPolicy.self, from: Data(buffer.readableBytesView))
        } catch {
            throw S3Error.malformedPolicy
        }

        try await storage.putBucketPolicy(bucket: bucket, policy: policy)
        logger.info("Bucket policy updated", metadata: ["bucket": "\(bucket)"])
        return Response(status: .noContent)
    }

    /// Handles DELETE /:bucket requests to delete a bucket.
    @Sendable func deleteBucket(request: Request, context: S3RequestContext) async throws -> Response {
        let bucket = try context.parameters.require("bucket")

        if request.uri.queryParameters.get("policy") != nil {
            return try await deleteBucketPolicy(bucket: bucket, context: context, request: request)
        }
        if request.uri.queryParameters.get("tagging") != nil {
            return try await deleteBucketTagging(bucket: bucket, request: request, context: context)
        }
        if request.uri.queryParameters.get("lifecycle") != nil {
            return try await deleteBucketLifecycle(bucket: bucket, request: request, context: context)
        }
        if request.uri.queryParameters.get("vpc") != nil {
            return try await deleteBucketVpcConfiguration(bucket: bucket, request: request, context: context)
        }

        try await checkAccess(bucket: bucket, action: "s3:DeleteBucket", request: request, context: context)

        try await storage.deleteBucket(name: bucket)
        logger.info("Bucket deleted", metadata: ["bucket": "\(bucket)"])
        return Response(status: .noContent)
    }

    /// Deletes the bucket policy for the specified bucket.
    func deleteBucketPolicy(bucket: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:DeleteBucketPolicy", request: request, context: context)
        try await storage.deleteBucketPolicy(bucket: bucket)
        logger.info("Bucket policy deleted", metadata: ["bucket": "\(bucket)"])
        return Response(status: .noContent)
    }

    /// Handles HEAD /:bucket requests.
    @Sendable func headBucket(request: Request, context: S3RequestContext) async throws -> Response {
        let bucket = try context.parameters.require("bucket")
        try await checkAccess(bucket: bucket, action: "s3:ListBucket", request: request, context: context)
        try await storage.headBucket(name: bucket)
        return Response(status: .ok)
    }

    /// Handles GET /:bucket requests to list objects in a bucket.
    @Sendable func listObjects(request: Request, context: S3RequestContext) async throws -> Response {
        let bucket = try context.parameters.require("bucket")

        if request.uri.queryParameters.get("policy") != nil {
            return try await getBucketPolicy(bucket: bucket, context: context, request: request)
        }
        if request.uri.queryParameters.get("acl") != nil {
            return try await getBucketACL(bucket: bucket, context: context, request: request)
        }
        if request.uri.queryParameters.get("versioning") != nil {
            return try await getBucketVersioning(bucket: bucket, context: context, request: request)
        }
        if request.uri.queryParameters.get("versions") != nil {
            return try await listObjectVersions(bucket: bucket, context: context, request: request)
        }
        if request.uri.queryParameters.get("tagging") != nil {
            return try await getBucketTagging(bucket: bucket, context: context, request: request)
        }
        if request.uri.queryParameters.get("lifecycle") != nil {
            return try await getBucketLifecycle(bucket: bucket, context: context, request: request)
        }
        if request.uri.queryParameters.get("notification") != nil {
            return try await getBucketNotification(bucket: bucket, context: context, request: request)
        }

        try await checkAccess(bucket: bucket, action: "s3:ListBucket", request: request, context: context)

        let prefix = request.uri.queryParameters.get("prefix")
        let delimiter = request.uri.queryParameters.get("delimiter")
        let marker = request.uri.queryParameters.get("marker")
        let listType = request.uri.queryParameters.get("list-type")
        let continuationToken = request.uri.queryParameters.get("continuation-token")
        let maxKeys = request.uri.queryParameters.get("max-keys").flatMap { Int($0) }

        let result = try await storage.listObjects(
            bucket: bucket, prefix: prefix, delimiter: delimiter, marker: marker,
            continuationToken: continuationToken, maxKeys: maxKeys)

        let xml: String
        if listType == "2" {
            xml = XML.listObjectsV2(
                bucket: bucket, result: result, prefix: prefix ?? "",
                continuationToken: continuationToken ?? "", maxKeys: maxKeys ?? 1000,
                isTruncated: result.isTruncated,
                keyCount: result.objects.count + result.commonPrefixes.count)
        } else {
            xml = XML.listObjects(
                bucket: bucket, result: result, prefix: prefix ?? "", marker: marker ?? "",
                maxKeys: maxKeys ?? 1000, isTruncated: result.isTruncated)
        }

        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Retrieves the bucket policy.
    func getBucketPolicy(bucket: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:GetBucketPolicy", request: request, context: context)
        let policy = try await storage.getBucketPolicy(bucket: bucket)
        let data = try JSONEncoder().encode(policy)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: data)))
    }

    /// Retrieves the versioning configuration.
    func getBucketVersioning(bucket: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:GetBucketVersioning", request: request, context: context)
        let config = try await storage.getBucketVersioning(bucket: bucket)
        let xml = XML.versioningConfiguration(config: config)
        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Retrieves the Access Control List for the specified bucket.
    func getBucketACL(bucket: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:GetBucketAcl", request: request, context: context)
        let acl = try await storage.getACL(bucket: bucket, key: nil, versionId: nil as String?)
        let xml = XML.accessControlPolicy(policy: acl)
        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Updates the Access Control List for the specified bucket.
    func putBucketACL(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutBucketAcl", request: request, context: context)

        if let acl = parseCannedACL(headers: request.headers, ownerID: context.principal ?? "anonymous") {
            try await storage.putACL(bucket: bucket, key: nil, versionId: nil as String?, acl: acl)
            return Response(status: .ok)
        }

        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        if buffer.readableBytes > 0 {
            let xmlString = String(buffer: buffer)
            let acl = XML.parseAccessControlPolicy(xml: xmlString)
            try await storage.putACL(bucket: bucket, key: nil, versionId: nil as String?, acl: acl)
            return Response(status: .ok)
        }

        logger.warning("No ACL specified. Use x-amz-acl header or XML body.")
        throw S3Error.invalidArgument
    }
    
    /// Lists object versions in a bucket.
    @Sendable func listObjectVersions(bucket: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, key: nil, action: "s3:ListBucketVersions", request: request, context: context)

        let prefix = request.uri.queryParameters.get("prefix")
        let delimiter = request.uri.queryParameters.get("delimiter")
        let keyMarker = request.uri.queryParameters.get("key-marker")
        let versionIdMarker = request.uri.queryParameters.get("version-id-marker")
        let maxKeys = request.uri.queryParameters.get("max-keys").flatMap { Int($0) }

        let result = try await storage.listObjectVersions(
            bucket: bucket, prefix: prefix, delimiter: delimiter, keyMarker: keyMarker,
            versionIdMarker: versionIdMarker, maxKeys: maxKeys)

        let xml = XML.listVersionsResult(
            bucket: bucket, result: result, prefix: prefix, delimiter: delimiter,
            keyMarker: keyMarker, versionIdMarker: versionIdMarker, maxKeys: maxKeys)

        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Retrieves bucket tags.
    func getBucketTagging(bucket: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:GetBucketTagging", request: request, context: context)
        let tags = try await storage.getTags(bucket: bucket, key: nil, versionId: nil as String?)
        let xml = XML.taggingConfiguration(tags: tags)
        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Updates bucket tags.
    func putBucketTagging(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutBucketTagging", request: request, context: context)
        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        let tags = XML.parseTagging(xml: String(buffer: buffer))
        try await storage.putTags(bucket: bucket, key: nil, versionId: nil as String?, tags: tags)
        return Response(status: .noContent)
    }

    /// Deletes bucket tags.
    func deleteBucketTagging(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutBucketTagging", request: request, context: context)
        try await storage.deleteTags(bucket: bucket, key: nil, versionId: nil as String?)
        return Response(status: .noContent)
    }

    /// Retrieves lifecycle configuration.
    func getBucketLifecycle(bucket: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:GetLifecycleConfiguration", request: request, context: context)
        guard let config = try await storage.getBucketLifecycle(bucket: bucket) else {
            throw S3Error.noSuchLifecycleConfiguration
        }
        let xml = XML.lifecycleConfiguration(config: config)
        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Sets lifecycle configuration.
    func putBucketLifecycle(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutLifecycleConfiguration", request: request, context: context)
        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        let xmlString = String(buffer: buffer)
        
        guard xmlString.contains("<LifecycleConfiguration>") || xmlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw S3Error.invalidArgument
        }
        
        let config = XML.parseLifecycle(xml: xmlString)
        try await storage.putBucketLifecycle(bucket: bucket, configuration: config)
        return Response(status: .ok)
    }

    /// Deletes lifecycle configuration.
    func deleteBucketLifecycle(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutLifecycleConfiguration", request: request, context: context)
        try await storage.deleteBucketLifecycle(bucket: bucket)
        return Response(status: .noContent)
    }

    /// Configures VPC-only access.
    func putBucketVpcConfiguration(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutBucketVpcConfiguration", request: request, context: context)

        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        let config = try JSONDecoder().decode(VpcConfiguration.self, from: buffer)

        try await storage.putBucketVpcConfiguration(bucket: bucket, configuration: config)
        logger.info("Bucket VPC configuration updated", metadata: ["bucket": "\(bucket)"])
        return Response(status: .ok)
    }

    /// Removes VPC configuration.
    func deleteBucketVpcConfiguration(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutBucketVpcConfiguration", request: request, context: context)
        try await storage.deleteBucketVpcConfiguration(bucket: bucket)
        logger.info("Bucket VPC configuration deleted", metadata: ["bucket": "\(bucket)"])
        return Response(status: .noContent)
    }

    /// Retrieves notification configuration.
    func getBucketNotification(bucket: String, context: S3RequestContext, request: Request) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:GetBucketNotification", request: request, context: context)
        guard let config = try await storage.getBucketNotification(bucket: bucket) else {
            let xml = XML.notificationConfiguration(config: NotificationConfiguration())
            return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
        }
        let xml = XML.notificationConfiguration(config: config)
        return Response(status: .ok, headers: [.contentType: "application/xml"], body: .init(byteBuffer: ByteBuffer(string: xml)))
    }

    /// Sets notification configuration.
    func putBucketNotification(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        try await checkAccess(bucket: bucket, action: "s3:PutBucketNotification", request: request, context: context)
        let buffer = try await request.body.collect(upTo: 1024 * 1024)
        let xmlString = String(buffer: buffer)
        
        guard xmlString.contains("<NotificationConfiguration>") || xmlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw S3Error.invalidArgument
        }
        
        let config = XML.parseNotification(xml: xmlString)
        try await storage.putBucketNotification(bucket: bucket, configuration: config)
        logger.info("Bucket notification configuration updated", metadata: ["bucket": "\(bucket)"])
        return Response(status: .ok)
    }
}
