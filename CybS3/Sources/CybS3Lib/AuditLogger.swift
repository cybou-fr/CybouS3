import Foundation
import Crypto

/// Audit event types for compliance tracking.
public enum AuditEventType: String, Codable, Sendable {
    case operationStart = "operation_start"
    case operationComplete = "operation_complete"
    case operationFailed = "operation_failed"
    case authentication = "authentication"
    case authorization = "authorization"
    case dataAccess = "data_access"
    case configurationChange = "configuration_change"
    case securityEvent = "security_event"
    case complianceCheck = "compliance_check"
}

/// Audit log entry for compliance and security tracking.
public struct AuditLogEntry: Codable, Sendable {
    /// Unique identifier for the audit entry.
    public let id: String
    /// Timestamp of the event.
    public let timestamp: Date
    /// Type of audit event.
    public let eventType: AuditEventType
    /// User or service that performed the action.
    public let actor: String
    /// Resource that was accessed or modified.
    public let resource: String
    /// Action performed (upload, download, delete, etc.).
    public let action: String
    /// Result of the operation (success, failure, etc.).
    public let result: String
    /// Additional metadata about the event.
    public let metadata: [String: String]
    /// IP address or source identifier.
    public let source: String
    /// Session or request identifier.
    public let sessionId: String?
    /// Compliance-related tags.
    public let complianceTags: [String]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        eventType: AuditEventType,
        actor: String,
        resource: String,
        action: String,
        result: String,
        metadata: [String: String] = [:],
        source: String,
        sessionId: String? = nil,
        complianceTags: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.actor = actor
        self.resource = resource
        self.action = action
        self.result = result
        self.metadata = metadata
        self.source = source
        self.sessionId = sessionId
        self.complianceTags = complianceTags
    }

    /// Creates an audit entry for operation start.
    public static func operationStart(
        actor: String,
        resource: String,
        action: String,
        source: String,
        sessionId: String? = nil,
        metadata: [String: String] = [:]
    ) -> AuditLogEntry {
        AuditLogEntry(
            eventType: .operationStart,
            actor: actor,
            resource: resource,
            action: action,
            result: "started",
            metadata: metadata,
            source: source,
            sessionId: sessionId
        )
    }

    /// Creates an audit entry for operation completion.
    public static func operationComplete(
        actor: String,
        resource: String,
        action: String,
        source: String,
        sessionId: String? = nil,
        metadata: [String: String] = [:],
        complianceTags: [String] = []
    ) -> AuditLogEntry {
        AuditLogEntry(
            eventType: .operationComplete,
            actor: actor,
            resource: resource,
            action: action,
            result: "success",
            metadata: metadata,
            source: source,
            sessionId: sessionId,
            complianceTags: complianceTags
        )
    }

    /// Creates an audit entry for operation failure.
    public static func operationFailed(
        actor: String,
        resource: String,
        action: String,
        error: String,
        source: String,
        sessionId: String? = nil,
        metadata: [String: String] = [:]
    ) -> AuditLogEntry {
        AuditLogEntry(
            eventType: .operationFailed,
            actor: actor,
            resource: resource,
            action: action,
            result: "failed",
            metadata: metadata.merging(["error": error]) { $1 },
            source: source,
            sessionId: sessionId,
            complianceTags: ["error"]
        )
    }

    /// Creates an audit entry for authentication events.
    public static func authentication(
        actor: String,
        result: String,
        source: String,
        metadata: [String: String] = [:]
    ) -> AuditLogEntry {
        AuditLogEntry(
            eventType: .authentication,
            actor: actor,
            resource: "authentication",
            action: "login",
            result: result,
            metadata: metadata,
            source: source,
            complianceTags: ["authentication"]
        )
    }

    /// Creates an audit entry for data access.
    public static func dataAccess(
        actor: String,
        resource: String,
        action: String,
        source: String,
        sessionId: String? = nil,
        complianceTags: [String] = []
    ) -> AuditLogEntry {
        AuditLogEntry(
            eventType: .dataAccess,
            actor: actor,
            resource: resource,
            action: action,
            result: "accessed",
            source: source,
            sessionId: sessionId,
            complianceTags: complianceTags + ["data_access"]
        )
    }
}

/// Protocol for audit log storage implementations.
public protocol AuditLogStorage: Sendable {
    /// Stores an audit log entry.
    func store(entry: AuditLogEntry) async throws

    /// Retrieves audit log entries with optional filtering.
    func retrieve(
        startDate: Date?,
        endDate: Date?,
        actor: String?,
        resource: String?,
        eventType: AuditEventType?,
        limit: Int?
    ) async throws -> [AuditLogEntry]

    /// Retrieves audit entries for compliance reporting.
    func retrieveForCompliance(
        complianceTags: [String],
        startDate: Date,
        endDate: Date
    ) async throws -> [AuditLogEntry]

    /// Purges old audit entries based on retention policy.
    func purgeEntries(olderThan: Date) async throws -> Int
}

/// File-based audit log storage implementation.
public actor FileAuditLogStorage: AuditLogStorage {
    private let logDirectory: URL
    private let maxFileSize: Int
    private let retentionDays: Int

    public init(logDirectory: URL, maxFileSize: Int = 10 * 1024 * 1024, retentionDays: Int = 365) {
        self.logDirectory = logDirectory
        self.maxFileSize = maxFileSize
        self.retentionDays = retentionDays
    }

    public func store(entry: AuditLogEntry) async throws {
        let logFile = try await getCurrentLogFile()
        let entryData = try JSONEncoder().encode(entry)
        let entryString = String(data: entryData, encoding: .utf8)! + "\n"

        try entryString.write(to: logFile, atomically: false, encoding: .utf8)
    }

    public func retrieve(
        startDate: Date?,
        endDate: Date?,
        actor: String?,
        resource: String?,
        eventType: AuditEventType?,
        limit: Int?
    ) async throws -> [AuditLogEntry] {
        let logFiles = try await getLogFiles()
        var entries: [AuditLogEntry] = []

        for logFile in logFiles {
            let fileEntries = try await parseLogFile(logFile)
            let filtered = fileEntries.filter { entry in
                if let startDate = startDate, entry.timestamp < startDate { return false }
                if let endDate = endDate, entry.timestamp > endDate { return false }
                if let actor = actor, entry.actor != actor { return false }
                if let resource = resource, entry.resource != resource { return false }
                if let eventType = eventType, entry.eventType != eventType { return false }
                return true
            }
            entries.append(contentsOf: filtered)
        }

        // Sort by timestamp (newest first) and apply limit
        entries.sort { $0.timestamp > $1.timestamp }
        if let limit = limit {
            entries = Array(entries.prefix(limit))
        }

        return entries
    }

    public func retrieveForCompliance(
        complianceTags: [String],
        startDate: Date,
        endDate: Date
    ) async throws -> [AuditLogEntry] {
        let allEntries = try await retrieve(
            startDate: startDate,
            endDate: endDate,
            actor: nil,
            resource: nil,
            eventType: nil,
            limit: nil
        )

        return allEntries.filter { entry in
            !Set(entry.complianceTags).isDisjoint(with: Set(complianceTags))
        }
    }

    public func purgeEntries(olderThan: Date) async throws -> Int {
        let logFiles = try await getLogFiles()
        var purgedCount = 0

        for logFile in logFiles {
            let entries = try await parseLogFile(logFile)
            let entriesToKeep = entries.filter { $0.timestamp >= olderThan }

            if entriesToKeep.count != entries.count {
                // Rewrite file with only entries to keep
                let keepData = entriesToKeep.map { entry -> String in
                    let entryData = try! JSONEncoder().encode(entry)
                    return String(data: entryData, encoding: .utf8)! + "\n"
                }.joined()

                try keepData.write(to: logFile, atomically: true, encoding: .utf8)
                purgedCount += (entries.count - entriesToKeep.count)
            }
        }

        return purgedCount
    }

    // MARK: - Private Methods

    private func getCurrentLogFile() async throws -> URL {
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let logFileName = "audit-\(dateString).log"
        let logFile = logDirectory.appendingPathComponent(logFileName)

        // Check if file exists and is too large
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let fileSize = attributes[.size] as? Int,
           fileSize > maxFileSize {
            // Rotate the log file
            let rotatedName = "audit-\(dateString)-\(Int(Date().timeIntervalSince1970)).log"
            let rotatedFile = logDirectory.appendingPathComponent(rotatedName)
            try FileManager.default.moveItem(at: logFile, to: rotatedFile)
        }

        return logFile
    }

    private func getLogFiles() async throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: nil
        )
        return contents.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func parseLogFile(_ fileURL: URL) async throws -> [AuditLogEntry] {
        let data = try Data(contentsOf: fileURL)
        let content = String(data: data, encoding: .utf8) ?? ""

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return try lines.map { line in
            let lineData = line.data(using: .utf8)!
            return try JSONDecoder().decode(AuditLogEntry.self, from: lineData)
        }
    }
}

/// In-memory audit log storage for testing.
public actor MemoryAuditLogStorage: AuditLogStorage {
    private var entries: [AuditLogEntry] = []

    public init() {}

    public func store(entry: AuditLogEntry) async throws {
        entries.append(entry)
    }

    public func retrieve(
        startDate: Date?,
        endDate: Date?,
        actor: String?,
        resource: String?,
        eventType: AuditEventType?,
        limit: Int?
    ) async throws -> [AuditLogEntry] {
        var filtered = entries.filter { entry in
            if let startDate = startDate, entry.timestamp < startDate { return false }
            if let endDate = endDate, entry.timestamp > endDate { return false }
            if let actor = actor, entry.actor != actor { return false }
            if let resource = resource, entry.resource != resource { return false }
            if let eventType = eventType, entry.eventType != eventType { return false }
            return true
        }

        // Sort by timestamp (newest first) and apply limit
        filtered.sort { $0.timestamp > $1.timestamp }
        if let limit = limit {
            filtered = Array(filtered.prefix(limit))
        }

        return filtered
    }

    public func retrieveForCompliance(
        complianceTags: [String],
        startDate: Date,
        endDate: Date
    ) async throws -> [AuditLogEntry] {
        let allEntries = try await retrieve(
            startDate: startDate,
            endDate: endDate,
            actor: nil,
            resource: nil,
            eventType: nil,
            limit: nil
        )

        return allEntries.filter { entry in
            !Set(entry.complianceTags).isDisjoint(with: Set(complianceTags))
        }
    }

    public func purgeEntries(olderThan: Date) async throws -> Int {
        let initialCount = entries.count
        entries = entries.filter { $0.timestamp >= olderThan }
        return initialCount - entries.count
    }

    /// Clears all entries (for testing).
    public func clear() {
        entries.removeAll()
    }
}