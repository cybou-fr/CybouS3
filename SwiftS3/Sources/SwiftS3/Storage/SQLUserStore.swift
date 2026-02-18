import Foundation
import NIO
import SQLiteNIO

/// SQLite implementation of UserStore
public struct SQLUserStore: UserStore {
    let connection: SQLiteConnection
    let logger: Logger = Logger(label: "SwiftS3.SQLUserStore")

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func createUser(username: String, accessKey: String, secretKey: String) async throws {
        try await connection.query(
            "INSERT INTO users (username, access_key, secret_key) VALUES (?, ?, ?)",
            [username, accessKey, secretKey]
        )
        logger.info("Created user", metadata: ["username": .string(username), "access_key": .string(accessKey)])
    }

    public func getUser(accessKey: String) async throws -> User? {
        let result = try await connection.query(
            "SELECT username, access_key, secret_key FROM users WHERE access_key = ?",
            [accessKey]
        )

        guard let row = try await result.collect().first else {
            return nil
        }

        let username = try row.decode(String.self, column: "username")
        let accessKeyValue = try row.decode(String.self, column: "access_key")
        let secretKey = try row.decode(String.self, column: "secret_key")

        return User(username: username, accessKey: accessKeyValue, secretKey: secretKey)
    }

    public func listUsers() async throws -> [User] {
        let result = try await connection.query(
            "SELECT username, access_key, secret_key FROM users ORDER BY username",
            []
        )

        var users: [User] = []
        for try await row in result {
            let username = try row.decode(String.self, column: "username")
            let accessKey = try row.decode(String.self, column: "access_key")
            let secretKey = try row.decode(String.self, column: "secret_key")
            users.append(User(username: username, accessKey: accessKey, secretKey: secretKey))
        }
        return users
    }

    public func deleteUser(accessKey: String) async throws {
        try await connection.query(
            "DELETE FROM users WHERE access_key = ?",
            [accessKey]
        )
        logger.info("Deleted user", metadata: ["access_key": .string(accessKey)])
    }
}