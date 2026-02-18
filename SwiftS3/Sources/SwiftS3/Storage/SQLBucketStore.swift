import Foundation
import NIO
import SQLiteNIO

/// Protocol defining bucket management operations
public protocol BucketStore: Sendable {
    /// Create a new bucket with the specified owner
    func createBucket(name: String, owner: String) async throws

    /// Delete a bucket and all its contents
    func deleteBucket(name: String) async throws

    /// Check if a bucket exists
    func bucketExists(name: String) async throws -> Bool

    /// Get bucket owner
    func getBucketOwner(name: String) async throws -> String?

    /// List all buckets for an owner
    func listBuckets(owner: String) async throws -> [BucketInfo]

    /// Get bucket versioning configuration
    func getBucketVersioning(bucket: String) async throws -> VersioningConfiguration?

    /// Set bucket versioning configuration
    func setBucketVersioning(bucket: String, configuration: VersioningConfiguration) async throws

    /// Get bucket lifecycle configuration
    func getLifecycle(bucket: String) async throws -> LifecycleConfiguration?

    /// Set bucket lifecycle configuration
    func putLifecycle(bucket: String, configuration: LifecycleConfiguration) async throws

    /// Remove bucket lifecycle configuration
    func deleteLifecycle(bucket: String) async throws

    /// Get object lock configuration
    func getObjectLockConfiguration(bucket: String) async throws -> ObjectLockConfiguration?

    /// Set object lock configuration
    func putObjectLockConfiguration(bucket: String, configuration: ObjectLockConfiguration) async throws

    /// Get replication configuration
    func getBucketReplication(bucket: String) async throws -> ReplicationConfiguration?

    /// Set replication configuration
    func putBucketReplication(bucket: String, configuration: ReplicationConfiguration) async throws

    /// Remove replication configuration
    func deleteBucketReplication(bucket: String) async throws

    /// Get notification configuration
    func getBucketNotification(bucket: String) async throws -> NotificationConfiguration?

    /// Set notification configuration
    func putBucketNotification(bucket: String, configuration: NotificationConfiguration) async throws

    /// Remove notification configuration
    func deleteBucketNotification(bucket: String) async throws

    /// Get VPC configuration
    func getBucketVpcConfiguration(bucket: String) async throws -> VpcConfiguration?

    /// Set VPC configuration
    func putBucketVpcConfiguration(bucket: String, configuration: VpcConfiguration) async throws

    /// Remove VPC configuration
    func deleteBucketVpcConfiguration(bucket: String) async throws

    /// Get bucket tags
    func getBucketTags(bucket: String) async throws -> [S3Tag]

    /// Set bucket tags
    func putBucketTags(bucket: String, tags: [S3Tag]) async throws

    /// Remove bucket tags
    func deleteBucketTags(bucket: String) async throws
}

/// Bucket information structure
public struct BucketInfo: Codable, Sendable {
    public let name: String
    public let creationDate: Date
    public let owner: String

    public init(name: String, creationDate: Date, owner: String) {
        self.name = name
        self.creationDate = creationDate
        self.owner = owner
    }
}

/// SQLite implementation of BucketStore
public struct SQLBucketStore: BucketStore {
    let connection: SQLiteConnection
    let logger: Logger = Logger(label: "SwiftS3.SQLBucketStore")

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func createBucket(name: String, owner: String) async throws {
        let creationDate = Date()
        try await connection.query(
            "INSERT INTO buckets (name, owner, creation_date) VALUES (?, ?, ?)",
            [name, owner, creationDate]
        )
        logger.info("Created bucket", metadata: ["bucket": .string(name), "owner": .string(owner)])
    }

    public func deleteBucket(name: String) async throws {
        try await connection.query(
            "DELETE FROM buckets WHERE name = ?",
            [name]
        )
        logger.info("Deleted bucket", metadata: ["bucket": .string(name)])
    }

    public func bucketExists(name: String) async throws -> Bool {
        let result = try await connection.query(
            "SELECT COUNT(*) as count FROM buckets WHERE name = ?",
            [name]
        )
        let row = try await result.collect().first
        let count = try row?.decode(Int.self, column: "count") ?? 0
        return count > 0
    }

    public func getBucketOwner(name: String) async throws -> String? {
        let result = try await connection.query(
            "SELECT owner FROM buckets WHERE name = ?",
            [name]
        )
        let row = try await result.collect().first
        return try row?.decode(String.self, column: "owner")
    }

    public func listBuckets(owner: String) async throws -> [BucketInfo] {
        let result = try await connection.query(
            "SELECT name, creation_date, owner FROM buckets WHERE owner = ? ORDER BY creation_date DESC",
            [owner]
        )

        var buckets: [BucketInfo] = []
        for try await row in result {
            let name = try row.decode(String.self, column: "name")
            let creationDate = try row.decode(Date.self, column: "creation_date")
            let bucketOwner = try row.decode(String.self, column: "owner")
            buckets.append(BucketInfo(name: name, creationDate: creationDate, owner: bucketOwner))
        }
        return buckets
    }

    public func getBucketVersioning(bucket: String) async throws -> VersioningConfiguration? {
        let result = try await connection.query(
            "SELECT versioning_status FROM buckets WHERE name = ?",
            [bucket]
        )
        let row = try await result.collect().first
        guard let statusString = try row?.decode(String?.self, column: "versioning_status") else {
            return nil
        }
        return VersioningConfiguration(status: VersioningStatus(rawValue: statusString) ?? .suspended)
    }

    public func setBucketVersioning(bucket: String, configuration: VersioningConfiguration) async throws {
        try await connection.query(
            "UPDATE buckets SET versioning_status = ? WHERE name = ?",
            [configuration.status.rawValue, bucket]
        )
        logger.info("Updated bucket versioning", metadata: [
            "bucket": .string(bucket),
            "status": .string(configuration.status.rawValue)
        ])
    }

    public func getLifecycle(bucket: String) async throws -> LifecycleConfiguration? {
        let result = try await connection.query(
            "SELECT lifecycle_config FROM buckets WHERE name = ?",
            [bucket]
        )
        let row = try await result.collect().first
        guard let data = try row?.decode(Data?.self, column: "lifecycle_config") else {
            return nil
        }
        return try JSONDecoder().decode(LifecycleConfiguration.self, from: data)
    }

    public func putLifecycle(bucket: String, configuration: LifecycleConfiguration) async throws {
        let data = try JSONEncoder().encode(configuration)
        try await connection.query(
            "UPDATE buckets SET lifecycle_config = ? WHERE name = ?",
            [data, bucket]
        )
        logger.info("Updated bucket lifecycle", metadata: ["bucket": .string(bucket)])
    }

    public func deleteLifecycle(bucket: String) async throws {
        try await connection.query(
            "UPDATE buckets SET lifecycle_config = NULL WHERE name = ?",
            [bucket]
        )
        logger.info("Deleted bucket lifecycle", metadata: ["bucket": .string(bucket)])
    }

    public func getObjectLockConfiguration(bucket: String) async throws -> ObjectLockConfiguration? {
        let result = try await connection.query(
            "SELECT object_lock_config FROM buckets WHERE name = ?",
            [bucket]
        )
        let row = try await result.collect().first
        guard let data = try row?.decode(Data?.self, column: "object_lock_config") else {
            return nil
        }
        return try JSONDecoder().decode(ObjectLockConfiguration.self, from: data)
    }

    public func putObjectLockConfiguration(bucket: String, configuration: ObjectLockConfiguration) async throws {
        let data = try JSONEncoder().encode(configuration)
        try await connection.query(
            "UPDATE buckets SET object_lock_config = ? WHERE name = ?",
            [data, bucket]
        )
        logger.info("Updated bucket object lock", metadata: ["bucket": .string(bucket)])
    }

    public func getBucketReplication(bucket: String) async throws -> ReplicationConfiguration? {
        let result = try await connection.query(
            "SELECT replication_config FROM buckets WHERE name = ?",
            [bucket]
        )
        let row = try await result.collect().first
        guard let data = try row?.decode(Data?.self, column: "replication_config") else {
            return nil
        }
        return try JSONDecoder().decode(ReplicationConfiguration.self, from: data)
    }

    public func putBucketReplication(bucket: String, configuration: ReplicationConfiguration) async throws {
        let data = try JSONEncoder().encode(configuration)
        try await connection.query(
            "UPDATE buckets SET replication_config = ? WHERE name = ?",
            [data, bucket]
        )
        logger.info("Updated bucket replication", metadata: ["bucket": .string(bucket)])
    }

    public func deleteBucketReplication(bucket: String) async throws {
        try await connection.query(
            "UPDATE buckets SET replication_config = NULL WHERE name = ?",
            [bucket]
        )
        logger.info("Deleted bucket replication", metadata: ["bucket": .string(bucket)])
    }

    public func getBucketNotification(bucket: String) async throws -> NotificationConfiguration? {
        let result = try await connection.query(
            "SELECT notification_config FROM buckets WHERE name = ?",
            [bucket]
        )
        let row = try await result.collect().first
        guard let data = try row?.decode(Data?.self, column: "notification_config") else {
            return nil
        }
        return try JSONDecoder().decode(NotificationConfiguration.self, from: data)
    }

    public func putBucketNotification(bucket: String, configuration: NotificationConfiguration) async throws {
        let data = try JSONEncoder().encode(configuration)
        try await connection.query(
            "UPDATE buckets SET notification_config = ? WHERE name = ?",
            [data, bucket]
        )
        logger.info("Updated bucket notification", metadata: ["bucket": .string(bucket)])
    }

    public func deleteBucketNotification(bucket: String) async throws {
        try await connection.query(
            "UPDATE buckets SET notification_config = NULL WHERE name = ?",
            [bucket]
        )
        logger.info("Deleted bucket notification", metadata: ["bucket": .string(bucket)])
    }

    public func getBucketVpcConfiguration(bucket: String) async throws -> VpcConfiguration? {
        let result = try await connection.query(
            "SELECT vpc_config FROM buckets WHERE name = ?",
            [bucket]
        )
        let row = try await result.collect().first
        guard let data = try row?.decode(Data?.self, column: "vpc_config") else {
            return nil
        }
        return try JSONDecoder().decode(VpcConfiguration.self, from: data)
    }

    public func putBucketVpcConfiguration(bucket: String, configuration: VpcConfiguration) async throws {
        let data = try JSONEncoder().encode(configuration)
        try await connection.query(
            "UPDATE buckets SET vpc_config = ? WHERE name = ?",
            [data, bucket]
        )
        logger.info("Updated bucket VPC config", metadata: ["bucket": .string(bucket)])
    }

    public func deleteBucketVpcConfiguration(bucket: String) async throws {
        try await connection.query(
            "UPDATE buckets SET vpc_config = NULL WHERE name = ?",
            [bucket]
        )
        logger.info("Deleted bucket VPC config", metadata: ["bucket": .string(bucket)])
    }

    public func getBucketTags(bucket: String) async throws -> [S3Tag] {
        let result = try await connection.query(
            "SELECT key, value FROM bucket_tags WHERE bucket_name = ?",
            [bucket]
        )

        var tags: [S3Tag] = []
        for try await row in result {
            let key = try row.decode(String.self, column: "key")
            let value = try row.decode(String.self, column: "value")
            tags.append(S3Tag(key: key, value: value))
        }
        return tags
    }

    public func putBucketTags(bucket: String, tags: [S3Tag]) async throws {
        // Delete existing tags
        try await connection.query(
            "DELETE FROM bucket_tags WHERE bucket_name = ?",
            [bucket]
        )

        // Insert new tags
        for tag in tags {
            try await connection.query(
                "INSERT INTO bucket_tags (bucket_name, key, value) VALUES (?, ?, ?)",
                [bucket, tag.key, tag.value]
            )
        }
        logger.info("Updated bucket tags", metadata: [
            "bucket": .string(bucket),
            "tag_count": .stringConvertible(tags.count)
        ])
    }

    public func deleteBucketTags(bucket: String) async throws {
        try await connection.query(
            "DELETE FROM bucket_tags WHERE bucket_name = ?",
            [bucket]
        )
        logger.info("Deleted bucket tags", metadata: ["bucket": .string(bucket)])
    }
}