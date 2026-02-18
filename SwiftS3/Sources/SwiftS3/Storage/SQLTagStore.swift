import Foundation
import NIO
import SQLiteNIO

/// Protocol defining tagging operations
public protocol TagStore: Sendable {
    /// Retrieve tags for a bucket or object
    func getTags(bucket: String, key: String?, versionId: String?) async throws -> [S3Tag]

    /// Set tags for a bucket or object
    func putTags(bucket: String, key: String?, versionId: String?, tags: [S3Tag]) async throws

    /// Remove all tags from a bucket or object
    func deleteTags(bucket: String, key: String?, versionId: String?) async throws
}

/// SQLite implementation of TagStore
public struct SQLTagStore: TagStore {
    let connection: SQLiteConnection
    let logger: Logger = Logger(label: "SwiftS3.SQLTagStore")

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func getTags(bucket: String, key: String?, versionId: String?) async throws -> [S3Tag] {
        let table = key != nil ? "object_tags" : "bucket_tags"
        let idColumn = key != nil ? "object_key" : "bucket_name"
        let idValue = key ?? bucket

        let result = try await connection.query(
            "SELECT key, value FROM \(table) WHERE \(idColumn) = ? ORDER BY key",
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
}