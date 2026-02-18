import Foundation
import NIO
import SQLiteNIO

/// Protocol defining object metadata operations
public protocol ObjectStore: Sendable {
    /// Retrieve metadata for an object
    func getMetadata(bucket: String, key: String, versionId: String?) async throws -> ObjectMetadata

    /// Save metadata for an object
    func saveMetadata(bucket: String, key: String, metadata: ObjectMetadata) async throws

    /// Delete metadata for an object
    func deleteMetadata(bucket: String, key: String, versionId: String?) async throws

    /// List objects in a bucket with optional filtering
    func listObjects(
        bucket: String, prefix: String?, delimiter: String?, marker: String?,
        continuationToken: String?, maxKeys: Int?
    ) async throws -> ListObjectsResult

    /// List all versions of objects in a bucket
    func listObjectVersions(
        bucket: String, prefix: String?, delimiter: String?, keyMarker: String?,
        versionIdMarker: String?, maxKeys: Int?
    ) async throws -> ListVersionsResult

    /// Get ACL for an object
    func getACL(bucket: String, key: String?, versionId: String?) async throws -> AccessControlPolicy

    /// Set ACL for an object
    func putACL(bucket: String, key: String?, versionId: String?, acl: AccessControlPolicy) async throws

    /// Get tags for an object
    func getTags(bucket: String, key: String?, versionId: String?) async throws -> [S3Tag]

    /// Set tags for an object
    func putTags(bucket: String, key: String?, versionId: String?, tags: [S3Tag]) async throws

    /// Remove tags from an object
    func deleteTags(bucket: String, key: String?, versionId: String?) async throws
}

/// SQLite implementation of ObjectStore
public struct SQLObjectStore: ObjectStore {
    let connection: SQLiteConnection
    let logger: Logger = Logger(label: "SwiftS3.SQLObjectStore")

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func getMetadata(bucket: String, key: String, versionId: String?) async throws -> ObjectMetadata {
        let query: String
        let parameters: [SQLiteData]

        if let versionId = versionId {
            query = """
                SELECT * FROM objects
                WHERE bucket_name = ? AND key = ? AND version_id = ?
                ORDER BY version_id DESC LIMIT 1
                """
            parameters = [bucket, key, versionId]
        } else {
            query = """
                SELECT * FROM objects
                WHERE bucket_name = ? AND key = ?
                ORDER BY is_latest DESC, version_id DESC LIMIT 1
                """
            parameters = [bucket, key]
        }

        let result = try await connection.query(query, parameters)
        guard let row = try await result.collect().first else {
            throw S3Error.noSuchKey
        }

        return try decodeObjectMetadata(from: row)
    }

    public func saveMetadata(bucket: String, key: String, metadata: ObjectMetadata) async throws {
        // Check if bucket versioning is enabled
        let versioningResult = try await connection.query(
            "SELECT versioning_status FROM buckets WHERE name = ?",
            [bucket]
        )
        let versioningRow = try await versioningResult.collect().first
        let versioningStatus = try versioningRow?.decode(String?.self, column: "versioning_status")
            .flatMap { VersioningStatus(rawValue: $0) } ?? .suspended

        let versionId: String
        if versioningStatus == .enabled {
            versionId = metadata.versionId ?? UUID().uuidString
        } else {
            versionId = "null"
        }

        // Mark previous versions as not latest
        if versioningStatus == .enabled {
            try await connection.query(
                "UPDATE objects SET is_latest = 0 WHERE bucket_name = ? AND key = ?",
                [bucket, key]
            )
        } else {
            // For non-versioned buckets, delete existing object
            try await connection.query(
                "DELETE FROM objects WHERE bucket_name = ? AND key = ?",
                [bucket, key]
            )
        }

        // Insert new metadata
        try await connection.query(
            """
            INSERT INTO objects (
                bucket_name, key, version_id, size, last_modified, etag, content_type,
                custom_metadata, is_latest, is_delete_marker, storage_class,
                checksum_algorithm, checksum_value, object_lock_mode,
                object_lock_retain_until_date, object_lock_legal_hold_status,
                server_side_encryption
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                bucket, key, versionId, metadata.size, metadata.lastModified,
                metadata.eTag, metadata.contentType, encodeMetadata(metadata.customMetadata),
                metadata.isLatest, metadata.isDeleteMarker, metadata.storageClass?.rawValue,
                metadata.checksumAlgorithm?.rawValue, metadata.checksumValue,
                metadata.objectLockMode?.rawValue, metadata.objectLockRetainUntilDate,
                metadata.objectLockLegalHoldStatus?.rawValue,
                encodeServerSideEncryption(metadata.serverSideEncryption)
            ]
        )

        logger.info("Saved object metadata", metadata: [
            "bucket": .string(bucket),
            "key": .string(key),
            "version_id": .string(versionId)
        ])
    }

    public func deleteMetadata(bucket: String, key: String, versionId: String?) async throws {
        if let versionId = versionId {
            // Delete specific version
            try await connection.query(
                "DELETE FROM objects WHERE bucket_name = ? AND key = ? AND version_id = ?",
                [bucket, key, versionId]
            )
        } else {
            // Check versioning status
            let versioningResult = try await connection.query(
                "SELECT versioning_status FROM buckets WHERE name = ?",
                [bucket]
            )
            let versioningRow = try await versioningResult.collect().first
            let versioningStatus = try versioningRow?.decode(String?.self, column: "versioning_status")
                .flatMap { VersioningStatus(rawValue: $0) } ?? .suspended

            if versioningStatus == .enabled {
                // Create delete marker
                let deleteMarker = ObjectMetadata(
                    key: key,
                    size: 0,
                    lastModified: Date(),
                    eTag: nil,
                    contentType: nil,
                    customMetadata: [:],
                    versionId: UUID().uuidString,
                    isLatest: true,
                    isDeleteMarker: true,
                    storageClass: nil,
                    checksumAlgorithm: nil,
                    checksumValue: nil,
                    objectLockMode: nil,
                    objectLockRetainUntilDate: nil,
                    objectLockLegalHoldStatus: nil,
                    serverSideEncryption: nil
                )
                try await saveMetadata(bucket: bucket, key: key, metadata: deleteMarker)
            } else {
                // Delete the object
                try await connection.query(
                    "DELETE FROM objects WHERE bucket_name = ? AND key = ?",
                    [bucket, key]
                )
            }
        }

        logger.info("Deleted object metadata", metadata: [
            "bucket": .string(bucket),
            "key": .string(key),
            "version_id": .string(versionId ?? "latest")
        ])
    }

    public func listObjects(
        bucket: String, prefix: String?, delimiter: String?, marker: String?,
        continuationToken: String?, maxKeys: Int?
    ) async throws -> ListObjectsResult {
        let maxKeysValue = maxKeys ?? 1000
        let startKey = continuationToken ?? marker ?? ""

        var query = """
            SELECT key, size, last_modified, etag, storage_class
            FROM objects
            WHERE bucket_name = ? AND is_latest = 1 AND is_delete_marker = 0
            """
        var parameters: [SQLiteData] = [bucket]

        if let prefix = prefix {
            query += " AND key LIKE ?"
            parameters.append("\(prefix)%")
        }

        query += " AND key > ? ORDER BY key LIMIT ?"
        parameters.append(startKey)
        parameters.append(maxKeysValue)

        let result = try await connection.query(query, parameters)

        var objects: [S3Object] = []
        var nextContinuationToken: String?

        for try await row in result {
            let key = try row.decode(String.self, column: "key")
            let size = try row.decode(Int64.self, column: "size")
            let lastModified = try row.decode(Date.self, column: "last_modified")
            let etag = try row.decode(String?.self, column: "etag")
            let storageClassString = try row.decode(String?.self, column: "storage_class")
            let storageClass = storageClassString.flatMap { StorageClass(rawValue: $0) }

            objects.append(S3Object(
                key: key,
                size: size,
                lastModified: lastModified,
                eTag: etag,
                storageClass: storageClass
            ))

            nextContinuationToken = key
        }

        return ListObjectsResult(
            objects: objects,
            isTruncated: objects.count == maxKeysValue,
            nextContinuationToken: objects.count == maxKeysValue ? nextContinuationToken : nil
        )
    }

    public func listObjectVersions(
        bucket: String, prefix: String?, delimiter: String?, keyMarker: String?,
        versionIdMarker: String?, maxKeys: Int?
    ) async throws -> ListVersionsResult {
        let maxKeysValue = maxKeys ?? 1000

        var query = """
            SELECT key, version_id, size, last_modified, etag, is_delete_marker, storage_class
            FROM objects
            WHERE bucket_name = ?
            """
        var parameters: [SQLiteData] = [bucket]

        if let prefix = prefix {
            query += " AND key LIKE ?"
            parameters.append("\(prefix)%")
        }

        // Handle pagination with key and version markers
        if let keyMarker = keyMarker {
            if let versionIdMarker = versionIdMarker {
                query += " AND (key > ? OR (key = ? AND version_id > ?))"
                parameters.append(contentsOf: [keyMarker, keyMarker, versionIdMarker])
            } else {
                query += " AND key >= ?"
                parameters.append(keyMarker)
            }
        }

        query += " ORDER BY key, version_id DESC LIMIT ?"
        parameters.append(maxKeysValue)

        let result = try await connection.query(query, parameters)

        var versions: [ObjectVersion] = []
        var nextKeyMarker: String?
        var nextVersionIdMarker: String?

        for try await row in result {
            let key = try row.decode(String.self, column: "key")
            let versionId = try row.decode(String.self, column: "version_id")
            let size = try row.decode(Int64.self, column: "size")
            let lastModified = try row.decode(Date.self, column: "last_modified")
            let etag = try row.decode(String?.self, column: "etag")
            let isDeleteMarker = try row.decode(Bool.self, column: "is_delete_marker")
            let storageClassString = try row.decode(String?.self, column: "storage_class")
            let storageClass = storageClassString.flatMap { StorageClass(rawValue: $0) }

            versions.append(ObjectVersion(
                key: key,
                versionId: versionId,
                size: size,
                lastModified: lastModified,
                eTag: etag,
                isDeleteMarker: isDeleteMarker,
                storageClass: storageClass
            ))

            nextKeyMarker = key
            nextVersionIdMarker = versionId
        }

        return ListVersionsResult(
            versions: versions,
            isTruncated: versions.count == maxKeysValue,
            nextKeyMarker: versions.count == maxKeysValue ? nextKeyMarker : nil,
            nextVersionIdMarker: versions.count == maxKeysValue ? nextVersionIdMarker : nil
        )
    }

    public func getACL(bucket: String, key: String?, versionId: String?) async throws -> AccessControlPolicy {
        let table = key != nil ? "object_acls" : "bucket_acls"
        let idColumn = key != nil ? "object_key" : "bucket_name"
        let idValue = key ?? bucket

        let result = try await connection.query(
            "SELECT owner, grants FROM \(table) WHERE \(idColumn) = ?",
            [idValue]
        )

        guard let row = try await result.collect().first else {
            throw S3Error.noSuchKey
        }

        let ownerId = try row.decode(String.self, column: "owner")
        let grantsData = try row.decode(Data.self, column: "grants")
        let grants = try JSONDecoder().decode([Grant].self, from: grantsData)

        return AccessControlPolicy(owner: Owner(id: ownerId), grants: grants)
    }

    public func putACL(bucket: String, key: String?, versionId: String?, acl: AccessControlPolicy) async throws {
        let table = key != nil ? "object_acls" : "bucket_acls"
        let idColumn = key != nil ? "object_key" : "bucket_name"
        let idValue = key ?? bucket

        let grantsData = try JSONEncoder().encode(acl.grants)

        try await connection.query(
            """
            INSERT OR REPLACE INTO \(table) (\(idColumn), owner, grants)
            VALUES (?, ?, ?)
            """,
            [idValue, acl.owner.id, grantsData]
        )

        logger.info("Updated ACL", metadata: [
            "bucket": .string(bucket),
            "key": .string(key ?? "bucket"),
            "owner": .string(acl.owner.id)
        ])
    }

    public func getTags(bucket: String, key: String?, versionId: String?) async throws -> [S3Tag] {
        let table = key != nil ? "object_tags" : "bucket_tags"
        let idColumn = key != nil ? "object_key" : "bucket_name"
        let idValue = key ?? bucket

        let result = try await connection.query(
            "SELECT key, value FROM \(table) WHERE \(idColumn) = ?",
            [idValue]
        )

        var tags: [S3Tag] = []
        for try await row in result {
            let tagKey = try row.decode(String.self, column: "key")
            let value = try row.decode(String.self, column: "value")
            tags.append(S3Tag(key: tagKey, value: value))
        }
        return tags
    }

    public func putTags(bucket: String, key: String?, versionId: String?, tags: [S3Tag]) async throws {
        let table = key != nil ? "object_tags" : "bucket_tags"
        let idColumn = key != nil ? "object_key" : "bucket_name"
        let idValue = key ?? bucket

        // Delete existing tags
        try await connection.query(
            "DELETE FROM \(table) WHERE \(idColumn) = ?",
            [idValue]
        )

        // Insert new tags
        for tag in tags {
            try await connection.query(
                "INSERT INTO \(table) (\(idColumn), key, value) VALUES (?, ?, ?)",
                [idValue, tag.key, tag.value]
            )
        }

        logger.info("Updated tags", metadata: [
            "bucket": .string(bucket),
            "key": .string(key ?? "bucket"),
            "tag_count": .stringConvertible(tags.count)
        ])
    }

    public func deleteTags(bucket: String, key: String?, versionId: String?) async throws {
        let table = key != nil ? "object_tags" : "bucket_tags"
        let idColumn = key != nil ? "object_key" : "bucket_name"
        let idValue = key ?? bucket

        try await connection.query(
            "DELETE FROM \(table) WHERE \(idColumn) = ?",
            [idValue]
        )

        logger.info("Deleted tags", metadata: [
            "bucket": .string(bucket),
            "key": .string(key ?? "bucket")
        ])
    }

    // Helper methods
    private func decodeObjectMetadata(from row: SQLiteRow) throws -> ObjectMetadata {
        let key = try row.decode(String.self, column: "key")
        let size = try row.decode(Int64.self, column: "size")
        let lastModified = try row.decode(Date.self, column: "last_modified")
        let etag = try row.decode(String?.self, column: "etag")
        let contentType = try row.decode(String?.self, column: "content_type")
        let customMetadataData = try row.decode(Data?.self, column: "custom_metadata")
        let customMetadata = customMetadataData.flatMap {
            try? JSONDecoder().decode([String: String].self, from: $0)
        } ?? [:]
        let versionId = try row.decode(String.self, column: "version_id")
        let isLatest = try row.decode(Bool.self, column: "is_latest")
        let isDeleteMarker = try row.decode(Bool.self, column: "is_delete_marker")
        let storageClassString = try row.decode(String?.self, column: "storage_class")
        let storageClass = storageClassString.flatMap { StorageClass(rawValue: $0) }
        let checksumAlgorithmString = try row.decode(String?.self, column: "checksum_algorithm")
        let checksumAlgorithm = checksumAlgorithmString.flatMap { ChecksumAlgorithm(rawValue: $0) }
        let checksumValue = try row.decode(String?.self, column: "checksum_value")
        let objectLockModeString = try row.decode(String?.self, column: "object_lock_mode")
        let objectLockMode = objectLockModeString.flatMap { ObjectLockMode(rawValue: $0) }
        let objectLockRetainUntilDate = try row.decode(Date?.self, column: "object_lock_retain_until_date")
        let objectLockLegalHoldStatusString = try row.decode(String?.self, column: "object_lock_legal_hold_status")
        let objectLockLegalHoldStatus = objectLockLegalHoldStatusString.flatMap { LegalHoldStatus(rawValue: $0) }
        let serverSideEncryptionData = try row.decode(Data?.self, column: "server_side_encryption")
        let serverSideEncryption = serverSideEncryptionData.flatMap {
            try? JSONDecoder().decode(ServerSideEncryptionConfig.self, from: $0)
        }

        return ObjectMetadata(
            key: key,
            size: size,
            lastModified: lastModified,
            eTag: etag,
            contentType: contentType,
            customMetadata: customMetadata,
            versionId: versionId,
            isLatest: isLatest,
            isDeleteMarker: isDeleteMarker,
            storageClass: storageClass,
            checksumAlgorithm: checksumAlgorithm,
            checksumValue: checksumValue,
            objectLockMode: objectLockMode,
            objectLockRetainUntilDate: objectLockRetainUntilDate,
            objectLockLegalHoldStatus: objectLockLegalHoldStatus,
            serverSideEncryption: serverSideEncryption
        )
    }

    private func encodeMetadata(_ metadata: [String: String]) -> Data? {
        try? JSONEncoder().encode(metadata)
    }

    private func encodeServerSideEncryption(_ config: ServerSideEncryptionConfig?) -> Data? {
        config.flatMap { try? JSONEncoder().encode($0) }
    }
}