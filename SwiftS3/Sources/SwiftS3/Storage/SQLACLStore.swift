import Foundation
import NIO
import SQLiteNIO

/// Protocol defining ACL operations
public protocol ACLStore: Sendable {
    /// Retrieve the access control policy for a bucket or object
    func getACL(bucket: String, key: String?, versionId: String?) async throws -> AccessControlPolicy

    /// Set the access control policy for a bucket or object
    func putACL(bucket: String, key: String?, versionId: String?, acl: AccessControlPolicy) async throws
}

/// SQLite implementation of ACLStore
public struct SQLACLStore: ACLStore {
    let connection: SQLiteConnection
    let logger: Logger = Logger(label: "SwiftS3.SQLACLStore")

    init(connection: SQLiteConnection) {
        self.connection = connection
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
            // Return default ACL if none exists
            let defaultOwner = try await getDefaultOwner(bucket: bucket)
            return AccessControlPolicy(
                owner: Owner(id: defaultOwner),
                grants: [Grant(grantee: Grantee(id: defaultOwner), permission: .fullControl)]
            )
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
            "owner": .string(acl.owner.id),
            "grant_count": .stringConvertible(acl.grants.count)
        ])
    }

    // Helper method to get default owner for a bucket
    private func getDefaultOwner(bucket: String) async throws -> String {
        let result = try await connection.query(
            "SELECT owner FROM buckets WHERE name = ?",
            [bucket]
        )

        guard let row = try await result.collect().first else {
            throw S3Error.noSuchBucket
        }

        return try row.decode(String.self, column: "owner")
    }
}