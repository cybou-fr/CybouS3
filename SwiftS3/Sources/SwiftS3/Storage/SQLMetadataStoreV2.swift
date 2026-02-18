import Foundation
import Logging
import NIO
import SQLiteNIO

/// Refactored metadata store that composes specialized stores
/// This replaces the monolithic SQLMetadataStore with focused components
public struct SQLMetadataStoreV2: MetadataStore {
    let connection: SQLiteConnection
    let logger: Logger = Logger(label: "SwiftS3.SQLMetadataStoreV2")

    // Composed specialized stores
    let bucketStore: SQLBucketStore
    let objectStore: SQLObjectStore
    let aclStore: SQLACLStore
    let tagStore: SQLTagStore
    let userStore: SQLUserStore

    init(connection: SQLiteConnection) {
        self.connection = connection
        self.bucketStore = SQLBucketStore(connection: connection)
        self.objectStore = SQLObjectStore(connection: connection)
        self.aclStore = SQLACLStore(connection: connection)
        self.tagStore = SQLTagStore(connection: connection)
        self.userStore = SQLUserStore(connection: connection)
    }

    /// Creates a new SQLite metadata store instance.
    /// Initializes database connection and creates all required tables and indexes.
    ///
    /// - Parameters:
    ///   - path: File system path for the SQLite database file
    ///   - eventLoopGroup: NIO event loop group for async operations
    ///   - threadPool: NIO thread pool for database I/O operations
    /// - Returns: Configured SQLMetadataStoreV2 instance
    /// - Throws: Database connection or schema initialization errors
    static func create(path: String, on eventLoopGroup: EventLoopGroup, threadPool: NIOThreadPool)
        async throws -> SQLMetadataStoreV2
    {
        let connection = try await SQLiteConnection.open(
            storage: .file(path: path),
            threadPool: threadPool,
            on: eventLoopGroup.next()
        )
        let store = SQLMetadataStoreV2(connection: connection)
        try await store.initializeSchema()
        return store
    }

    /// Initializes the SQLite database schema.
    /// Creates all required tables, indexes, and initial data for SwiftS3 operation.
    /// Safe to call multiple times - uses IF NOT EXISTS clauses.
    ///
    /// Tables created:
    /// - buckets: Bucket metadata and configuration
    /// - objects: Object metadata with versioning support
    /// - users: User accounts and credentials
    /// - bucket_acls: Bucket access control lists
    /// - object_acls: Object access control lists
    /// - bucket_tags: Bucket tagging
    /// - object_tags: Object tagging
    ///
    /// - Throws: SQLite errors if schema creation fails
    func initializeSchema() async throws {
        // Create buckets table
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS buckets (
                name TEXT PRIMARY KEY,
                owner TEXT NOT NULL,
                creation_date REAL NOT NULL,
                versioning_status TEXT DEFAULT 'Suspended',
                lifecycle_config BLOB,
                object_lock_config BLOB,
                replication_config BLOB,
                notification_config BLOB,
                vpc_config BLOB
            )
            """, [])

        // Create objects table
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS objects (
                bucket_name TEXT NOT NULL,
                key TEXT NOT NULL,
                version_id TEXT NOT NULL,
                size INTEGER NOT NULL,
                last_modified REAL NOT NULL,
                etag TEXT,
                content_type TEXT,
                custom_metadata BLOB,
                is_latest INTEGER DEFAULT 1,
                is_delete_marker INTEGER DEFAULT 0,
                storage_class TEXT,
                checksum_algorithm TEXT,
                checksum_value TEXT,
                object_lock_mode TEXT,
                object_lock_retain_until_date REAL,
                object_lock_legal_hold_status TEXT,
                server_side_encryption BLOB,
                PRIMARY KEY (bucket_name, key, version_id)
            )
            """, [])

        // Create users table
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS users (
                username TEXT NOT NULL,
                access_key TEXT PRIMARY KEY,
                secret_key TEXT NOT NULL
            )
            """, [])

        // Create ACL tables
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS bucket_acls (
                bucket_name TEXT PRIMARY KEY,
                owner TEXT NOT NULL,
                grants BLOB NOT NULL
            )
            """, [])

        try await connection.query("""
            CREATE TABLE IF NOT EXISTS object_acls (
                bucket_name TEXT NOT NULL,
                object_key TEXT NOT NULL,
                version_id TEXT,
                owner TEXT NOT NULL,
                grants BLOB NOT NULL,
                PRIMARY KEY (bucket_name, object_key, version_id)
            )
            """, [])

        // Create tag tables
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS bucket_tags (
                bucket_name TEXT NOT NULL,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                PRIMARY KEY (bucket_name, key)
            )
            """, [])

        try await connection.query("""
            CREATE TABLE IF NOT EXISTS object_tags (
                bucket_name TEXT NOT NULL,
                object_key TEXT NOT NULL,
                version_id TEXT,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                PRIMARY KEY (bucket_name, object_key, version_id, key)
            )
            """, [])

        // Create indexes for performance
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_objects_bucket_key ON objects(bucket_name, key)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_objects_latest ON objects(is_latest)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_users_access_key ON users(access_key)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_bucket_tags_bucket ON bucket_tags(bucket_name)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_object_tags_object ON object_tags(bucket_name, object_key, version_id)", [])

        logger.info("Database schema initialized successfully")
    }

    // MARK: - MetadataStore Protocol Implementation

    public func getMetadata(bucket: String, key: String, versionId: String?) async throws -> ObjectMetadata {
        try await objectStore.getMetadata(bucket: bucket, key: key, versionId: versionId)
    }

    public func saveMetadata(bucket: String, key: String, metadata: ObjectMetadata) async throws {
        try await objectStore.saveMetadata(bucket: bucket, key: key, metadata: metadata)
    }

    public func deleteMetadata(bucket: String, key: String, versionId: String?) async throws {
        try await objectStore.deleteMetadata(bucket: bucket, key: key, versionId: versionId)
    }

    public func listObjects(
        bucket: String, prefix: String?, delimiter: String?, marker: String?,
        continuationToken: String?, maxKeys: Int?
    ) async throws -> ListObjectsResult {
        try await objectStore.listObjects(
            bucket: bucket, prefix: prefix, delimiter: delimiter, marker: marker,
            continuationToken: continuationToken, maxKeys: maxKeys
        )
    }

    public func shutdown() async throws {
        // Connection will be closed by the caller
        logger.info("Metadata store shutdown")
    }

    public func getACL(bucket: String, key: String?, versionId: String?) async throws -> AccessControlPolicy {
        try await aclStore.getACL(bucket: bucket, key: key, versionId: versionId)
    }

    public func putACL(bucket: String, key: String?, versionId: String?, acl: AccessControlPolicy) async throws {
        try await aclStore.putACL(bucket: bucket, key: key, versionId: versionId, acl: acl)
    }

    public func getBucketVersioning(bucket: String) async throws -> VersioningConfiguration? {
        try await bucketStore.getBucketVersioning(bucket: bucket)
    }

    public func setBucketVersioning(bucket: String, configuration: VersioningConfiguration) async throws {
        try await bucketStore.setBucketVersioning(bucket: bucket, configuration: configuration)
    }

    public func listObjectVersions(
        bucket: String, prefix: String?, delimiter: String?, keyMarker: String?,
        versionIdMarker: String?, maxKeys: Int?
    ) async throws -> ListVersionsResult {
        try await objectStore.listObjectVersions(
            bucket: bucket, prefix: prefix, delimiter: delimiter, keyMarker: keyMarker,
            versionIdMarker: versionIdMarker, maxKeys: maxKeys
        )
    }

    public func createBucket(name: String, owner: String) async throws {
        try await bucketStore.createBucket(name: name, owner: owner)
    }

    public func deleteBucket(name: String) async throws {
        try await bucketStore.deleteBucket(name: name)
    }

    public func getTags(bucket: String, key: String?, versionId: String?) async throws -> [S3Tag] {
        try await tagStore.getTags(bucket: bucket, key: key, versionId: versionId)
    }

    public func putTags(bucket: String, key: String?, versionId: String?, tags: [S3Tag]) async throws {
        try await tagStore.putTags(bucket: bucket, key: key, versionId: versionId, tags: tags)
    }

    public func deleteTags(bucket: String, key: String?, versionId: String?) async throws {
        try await tagStore.deleteTags(bucket: bucket, key: key, versionId: versionId)
    }

    public func getLifecycle(bucket: String) async throws -> LifecycleConfiguration? {
        try await bucketStore.getLifecycle(bucket: bucket)
    }

    public func putLifecycle(bucket: String, configuration: LifecycleConfiguration) async throws {
        try await bucketStore.putLifecycle(bucket: bucket, configuration: configuration)
    }

    public func deleteLifecycle(bucket: String) async throws {
        try await bucketStore.deleteLifecycle(bucket: bucket)
    }

    public func getObjectLockConfiguration(bucket: String) async throws -> ObjectLockConfiguration? {
        try await bucketStore.getObjectLockConfiguration(bucket: bucket)
    }

    public func putObjectLockConfiguration(bucket: String, configuration: ObjectLockConfiguration) async throws {
        try await bucketStore.putObjectLockConfiguration(bucket: bucket, configuration: configuration)
    }

    public func getBucketReplication(bucket: String) async throws -> ReplicationConfiguration? {
        try await bucketStore.getBucketReplication(bucket: bucket)
    }

    public func putBucketReplication(bucket: String, configuration: ReplicationConfiguration) async throws {
        try await bucketStore.putBucketReplication(bucket: bucket, configuration: configuration)
    }

    public func deleteBucketReplication(bucket: String) async throws {
        try await bucketStore.deleteBucketReplication(bucket: bucket)
    }

    public func getBucketNotification(bucket: String) async throws -> NotificationConfiguration? {
        try await bucketStore.getBucketNotification(bucket: bucket)
    }

    public func putBucketNotification(bucket: String, configuration: NotificationConfiguration) async throws {
        try await bucketStore.putBucketNotification(bucket: bucket, configuration: configuration)
    }

    public func deleteBucketNotification(bucket: String) async throws {
        try await bucketStore.deleteBucketNotification(bucket: bucket)
    }

    public func getBucketVpcConfiguration(bucket: String) async throws -> VpcConfiguration? {
        try await bucketStore.getBucketVpcConfiguration(bucket: bucket)
    }

    public func putBucketVpcConfiguration(bucket: String, configuration: VpcConfiguration) async throws {
        try await bucketStore.putBucketVpcConfiguration(bucket: bucket, configuration: configuration)
    }

    public func deleteBucketVpcConfiguration(bucket: String) async throws {
        try await bucketStore.deleteBucketVpcConfiguration(bucket: bucket)
    }

    public func logAuditEvent(_ event: AuditEvent) async throws {
        // TODO: Implement audit logging
        logger.info("Audit event logged", metadata: [
            "event_type": .string(event.eventType.rawValue),
            "principal": .string(event.principal ?? "unknown")
        ])
    }

    public func getAuditEvents(
        bucket: String?, principal: String?, eventType: AuditEventType?, startDate: Date?, endDate: Date?,
        limit: Int?, continuationToken: String?
    ) async throws -> (events: [AuditEvent], nextContinuationToken: String?) {
        // TODO: Implement audit event retrieval
        logger.info("Audit events retrieved", metadata: [
            "bucket": .string(bucket ?? "all"),
            "limit": .stringConvertible(limit ?? 100)
        ])
        return ([], nil)
    }

    public func deleteAuditEvents(olderThan: Date) async throws {
        // TODO: Implement audit event deletion
        logger.info("Audit events deleted", metadata: ["older_than": .string(olderThan.description)])
    }

    public func createBatchJob(job: BatchJob) async throws -> String {
        // TODO: Implement batch job creation
        let jobId = UUID().uuidString
        logger.info("Batch job created", metadata: ["job_id": .string(jobId)])
        return jobId
    }

    public func getBatchJob(jobId: String) async throws -> BatchJob? {
        // TODO: Implement batch job retrieval
        logger.info("Batch job retrieved", metadata: ["job_id": .string(jobId)])
        return nil
    }

    public func listBatchJobs(bucket: String?, status: BatchJobStatus?, limit: Int?, continuationToken: String?) async throws -> (jobs: [BatchJob], nextContinuationToken: String?) {
        // TODO: Implement batch job listing
        logger.info("Batch jobs listed", metadata: ["bucket": .string(bucket ?? "all")])
        return ([], nil)
    }

    public func updateBatchJobStatus(jobId: String, status: BatchJobStatus, message: String?) async throws {
        // TODO: Implement batch job status update
        logger.info("Batch job status updated", metadata: [
            "job_id": .string(jobId),
            "status": .string(status.rawValue)
        ])
    }

    public func deleteBatchJob(jobId: String) async throws {
        // TODO: Implement batch job deletion
        logger.info("Batch job deleted", metadata: ["job_id": .string(jobId)])
    }

    public func executeBatchOperation(jobId: String, bucket: String, key: String) async throws {
        // TODO: Implement batch operation execution
        logger.info("Batch operation executed", metadata: [
            "job_id": .string(jobId),
            "bucket": .string(bucket),
            "key": .string(key)
        ])
    }
}

// MARK: - UserStore Extension
extension SQLMetadataStoreV2: UserStore {
    public func createUser(username: String, accessKey: String, secretKey: String) async throws {
        try await userStore.createUser(username: username, accessKey: accessKey, secretKey: secretKey)
    }

    public func getUser(accessKey: String) async throws -> User? {
        try await userStore.getUser(accessKey: accessKey)
    }

    public func listUsers() async throws -> [User] {
        try await userStore.listUsers()
    }

    public func deleteUser(accessKey: String) async throws {
        try await userStore.deleteUser(accessKey: accessKey)
    }
}