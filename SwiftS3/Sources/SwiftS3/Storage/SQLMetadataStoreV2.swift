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

        // Create audit events table
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS audit_events (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                event_type TEXT NOT NULL,
                principal TEXT NOT NULL,
                source_ip TEXT,
                user_agent TEXT,
                request_id TEXT NOT NULL,
                bucket TEXT,
                key TEXT,
                operation TEXT NOT NULL,
                status TEXT NOT NULL,
                error_message TEXT,
                additional_data TEXT
            )
            """, [])

        // Create batch jobs table
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS batch_jobs (
                id TEXT PRIMARY KEY,
                operation TEXT NOT NULL,
                manifest TEXT NOT NULL,
                priority INTEGER DEFAULT 0,
                role_arn TEXT,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                completed_at REAL,
                failure_reasons TEXT,
                progress TEXT NOT NULL
            )
            """, [])

        // Create indexes for performance
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_objects_bucket_key ON objects(bucket_name, key)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_objects_latest ON objects(is_latest)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_users_access_key ON users(access_key)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_bucket_tags_bucket ON bucket_tags(bucket_name)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_object_tags_object ON object_tags(bucket_name, object_key, version_id)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp ON audit_events(timestamp)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_audit_events_principal ON audit_events(principal)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_audit_events_bucket ON audit_events(bucket)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_batch_jobs_status ON batch_jobs(status)", [])
        try await connection.query("CREATE INDEX IF NOT EXISTS idx_batch_jobs_created_at ON batch_jobs(created_at)", [])

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
        let additionalDataJson = event.additionalData.map { try? JSONEncoder().encode($0) }
        
        try await connection.query("""
            INSERT INTO audit_events (
                id, timestamp, event_type, principal, source_ip, user_agent, 
                request_id, bucket, key, operation, status, error_message, additional_data
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                event.id,
                event.timestamp.timeIntervalSince1970,
                event.eventType.rawValue,
                event.principal,
                event.sourceIp,
                event.userAgent,
                event.requestId,
                event.bucket,
                event.key,
                event.operation,
                event.status,
                event.errorMessage,
                additionalDataJson.map { String(data: $0, encoding: .utf8) }
            ])
        
        logger.info("Audit event logged", metadata: [
            "event_id": .string(event.id),
            "event_type": .string(event.eventType.rawValue),
            "principal": .string(event.principal)
        ])
    }

    public func getAuditEvents(
        bucket: String?, principal: String?, eventType: AuditEventType?, startDate: Date?, endDate: Date?,
        limit: Int?, continuationToken: String?
    ) async throws -> (events: [AuditEvent], nextContinuationToken: String?) {
        var conditions: [String] = []
        var parameters: [SQLiteData] = []
        
        if let bucket = bucket {
            conditions.append("bucket = ?")
            parameters.append(.text(bucket))
        }
        
        if let principal = principal {
            conditions.append("principal = ?")
            parameters.append(.text(principal))
        }
        
        if let eventType = eventType {
            conditions.append("event_type = ?")
            parameters.append(.text(eventType.rawValue))
        }
        
        if let startDate = startDate {
            conditions.append("timestamp >= ?")
            parameters.append(.real(startDate.timeIntervalSince1970))
        }
        
        if let endDate = endDate {
            conditions.append("timestamp <= ?")
            parameters.append(.real(endDate.timeIntervalSince1970))
        }
        
        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let limitClause = limit.map { "LIMIT \($0 + 1)" } ?? ""
        
        let rows = try await connection.query("""
            SELECT id, timestamp, event_type, principal, source_ip, user_agent, 
                   request_id, bucket, key, operation, status, error_message, additional_data
            FROM audit_events
            \(whereClause)
            ORDER BY timestamp DESC
            \(limitClause)
            """, parameters)
        
        var events: [AuditEvent] = []
        var hasMore = false
        
        for (index, row) in rows.enumerated() {
            if let limit = limit, index >= limit {
                hasMore = true
                break
            }
            
            let additionalData: [String: String]? = {
                guard let dataStr = row.column("additional_data")?.text,
                      let data = dataStr.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode([String: String].self, from: data)
            }()
            
            let event = AuditEvent(
                id: row.column("id")!.text!,
                timestamp: Date(timeIntervalSince1970: row.column("timestamp")!.real!),
                eventType: AuditEventType(rawValue: row.column("event_type")!.text!)!,
                principal: row.column("principal")!.text!,
                sourceIp: row.column("source_ip")?.text,
                userAgent: row.column("user_agent")?.text,
                requestId: row.column("request_id")!.text!,
                bucket: row.column("bucket")?.text,
                key: row.column("key")?.text,
                operation: row.column("operation")!.text!,
                status: row.column("status")!.text!,
                errorMessage: row.column("error_message")?.text,
                additionalData: additionalData
            )
            
            events.append(event)
        }
        
        let nextContinuationToken = hasMore ? events.last?.id : nil
        
        return (events, nextContinuationToken)
    }

    public func deleteAuditEvents(olderThan: Date) async throws {
        let deletedCount = try await connection.query("""
            DELETE FROM audit_events WHERE timestamp < ?
            """, [.real(olderThan.timeIntervalSince1970)])
        
        logger.info("Audit events deleted", metadata: [
            "older_than": .string(olderThan.description),
            "deleted_count": .stringConvertible(deletedCount.rowCount)
        ])
    }

    public func createBatchJob(job: BatchJob) async throws -> String {
        let manifestJson = try JSONEncoder().encode(job.manifest)
        let progressJson = try JSONEncoder().encode(job.progress)
        let failureReasonsJson = try JSONEncoder().encode(job.failureReasons)
        
        try await connection.query("""
            INSERT INTO batch_jobs (
                id, operation, manifest, priority, role_arn, status, 
                created_at, completed_at, failure_reasons, progress
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                job.id,
                try JSONEncoder().encode(job.operation).base64EncodedString(),
                manifestJson,
                .integer(Int64(job.priority)),
                job.roleArn,
                job.status.rawValue,
                job.createdAt.timeIntervalSince1970,
                job.completedAt?.timeIntervalSince1970,
                failureReasonsJson,
                progressJson
            ])
        
        logger.info("Batch job created", metadata: [
            "job_id": .string(job.id),
            "operation": .string(job.operation.type.rawValue),
            "status": .string(job.status.rawValue)
        ])
        
        return job.id
    }

    public func getBatchJob(jobId: String) async throws -> BatchJob? {
        let rows = try await connection.query("""
            SELECT id, operation, manifest, priority, role_arn, status, 
                   created_at, completed_at, failure_reasons, progress
            FROM batch_jobs WHERE id = ?
            """, [.text(jobId)])
        
        guard let row = rows.first else { return nil }
        
        let operation: BatchOperation = {
            guard let operationData = Data(base64Encoded: row.column("operation")!.text!),
                  let decoded = try? JSONDecoder().decode(BatchOperation.self, from: operationData) else {
                // Fallback for malformed data
                return BatchOperation(type: .s3PutObjectCopy)
            }
            return decoded
        }()
        
        let manifest = try JSONDecoder().decode(BatchManifest.self, from: row.column("manifest")!.blob!)
        let progress = try JSONDecoder().decode(BatchProgress.self, from: row.column("progress")!.blob!)
        let failureReasons = try JSONDecoder().decode([String].self, from: row.column("failure_reasons")!.blob!)
        
        return BatchJob(
            id: row.column("id")!.text!,
            operation: operation,
            manifest: manifest,
            priority: Int(row.column("priority")!.integer!),
            roleArn: row.column("role_arn")?.text,
            status: BatchJobStatus(rawValue: row.column("status")!.text!)!,
            createdAt: Date(timeIntervalSince1970: row.column("created_at")!.real!),
            completedAt: row.column("completed_at").map { Date(timeIntervalSince1970: $0.real!) },
            failureReasons: failureReasons,
            progress: progress
        )
    }

    public func listBatchJobs(bucket: String?, status: BatchJobStatus?, limit: Int?, continuationToken: String?) async throws -> (jobs: [BatchJob], nextContinuationToken: String?) {
        var conditions: [String] = []
        var parameters: [SQLiteData] = []
        
        if let bucket = bucket {
            // Note: This is a simplified implementation. In reality, we'd need to join with manifest data
            // For now, we'll skip bucket filtering as it requires more complex queries
            logger.warning("Bucket filtering for batch jobs not yet implemented")
        }
        
        if let status = status {
            conditions.append("status = ?")
            parameters.append(.text(status.rawValue))
        }
        
        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let limitClause = limit.map { "LIMIT \($0 + 1)" } ?? ""
        
        let rows = try await connection.query("""
            SELECT id, operation, manifest, priority, role_arn, status, 
                   created_at, completed_at, failure_reasons, progress
            FROM batch_jobs
            \(whereClause)
            ORDER BY created_at DESC
            \(limitClause)
            """, parameters)
        
        var jobs: [BatchJob] = []
        var hasMore = false
        
        for (index, row) in rows.enumerated() {
            if let limit = limit, index >= limit {
                hasMore = true
                break
            }
            
            let operation: BatchOperation = {
                guard let operationData = Data(base64Encoded: row.column("operation")!.text!),
                      let decoded = try? JSONDecoder().decode(BatchOperation.self, from: operationData) else {
                    return BatchOperation(type: .s3PutObjectCopy)
                }
                return decoded
            }()
            
            let manifest = try JSONDecoder().decode(BatchManifest.self, from: row.column("manifest")!.blob!)
            let progress = try JSONDecoder().decode(BatchProgress.self, from: row.column("progress")!.blob!)
            let failureReasons = try JSONDecoder().decode([String].self, from: row.column("failure_reasons")!.blob!)
            
            let job = BatchJob(
                id: row.column("id")!.text!,
                operation: operation,
                manifest: manifest,
                priority: Int(row.column("priority")!.integer!),
                roleArn: row.column("role_arn")?.text,
                status: BatchJobStatus(rawValue: row.column("status")!.text!)!,
                createdAt: Date(timeIntervalSince1970: row.column("created_at")!.real!),
                completedAt: row.column("completed_at").map { Date(timeIntervalSince1970: $0.real!) },
                failureReasons: failureReasons,
                progress: progress
            )
            
            jobs.append(job)
        }
        
        let nextContinuationToken = hasMore ? jobs.last?.id : nil
        
        return (jobs, nextContinuationToken)
    }

    public func updateBatchJobStatus(jobId: String, status: BatchJobStatus, message: String?) async throws {
        let completedAt = (status == .completed || status == .failed) ? Date().timeIntervalSince1970 : nil
        
        try await connection.query("""
            UPDATE batch_jobs 
            SET status = ?, completed_at = ?
            WHERE id = ?
            """, [
                .text(status.rawValue),
                completedAt.map { .real($0) } ?? .null,
                .text(jobId)
            ])
        
        logger.info("Batch job status updated", metadata: [
            "job_id": .string(jobId),
            "status": .string(status.rawValue),
            "message": .string(message ?? "")
        ])
    }

    public func deleteBatchJob(jobId: String) async throws {
        let result = try await connection.query("""
            DELETE FROM batch_jobs WHERE id = ?
            """, [.text(jobId)])
        
        if result.rowCount > 0 {
            logger.info("Batch job deleted", metadata: ["job_id": .string(jobId)])
        } else {
            logger.warning("Batch job not found for deletion", metadata: ["job_id": .string(jobId)])
        }
    }

    public func executeBatchOperation(jobId: String, bucket: String, key: String) async throws {
        // Get the job to understand what operation to perform
        guard let job = try await getBatchJob(jobId: jobId) else {
            throw NSError(domain: "SQLMetadataStoreV2", code: 1, userInfo: [NSLocalizedDescriptionKey: "Batch job not found"])
        }
        
        // For now, implement basic logging. In a full implementation, this would:
        // 1. Validate the operation type
        // 2. Perform the actual S3 operation (copy, delete, etc.)
        // 3. Update progress
        // 4. Handle errors
        
        logger.info("Executing batch operation", metadata: [
            "job_id": .string(jobId),
            "operation": .string(job.operation.type.rawValue),
            "bucket": .string(bucket),
            "key": .string(key)
        ])
        
        // Update job progress (simplified)
        var updatedProgress = job.progress
        updatedProgress.processedObjects += 1
        
        let progressJson = try JSONEncoder().encode(updatedProgress)
        try await connection.query("""
            UPDATE batch_jobs SET progress = ? WHERE id = ?
            """, [progressJson, .text(jobId)])
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