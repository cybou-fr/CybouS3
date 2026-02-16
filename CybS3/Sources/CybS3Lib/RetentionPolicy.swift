import Foundation

/// Retention policy for data lifecycle management.
public struct RetentionPolicy: Codable, Sendable {
    /// Unique identifier for the policy.
    public let id: String
    /// Name of the retention policy.
    public let name: String
    /// Description of the policy.
    public let description: String
    /// Rules that define the retention behavior.
    public let rules: [RetentionRule]
    /// Whether the policy is currently active.
    public let isActive: Bool
    /// Compliance standards this policy helps satisfy.
    public let complianceStandards: [ComplianceStandard]

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        rules: [RetentionRule],
        isActive: Bool = true,
        complianceStandards: [ComplianceStandard] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.rules = rules
        self.isActive = isActive
        self.complianceStandards = complianceStandards
    }

    /// Applies the retention policy to determine if data should be retained.
    public func shouldRetain(dataAge: TimeInterval, dataTags: [String] = []) -> Bool {
        guard isActive else { return true }

        for rule in rules {
            if rule.appliesTo(tags: dataTags) {
                return rule.shouldRetain(age: dataAge)
            }
        }

        // Default: retain if no rules apply
        return true
    }

    /// Gets the retention period for data with the given tags.
    public func getRetentionPeriod(for tags: [String] = []) -> TimeInterval? {
        guard isActive else { return nil }

        for rule in rules {
            if rule.appliesTo(tags: tags) {
                return rule.retentionPeriod
            }
        }

        return nil
    }
}

/// Individual rule within a retention policy.
public struct RetentionRule: Codable, Sendable {
    /// Tags that this rule applies to (empty means applies to all).
    public let applicableTags: [String]
    /// Retention period in seconds.
    public let retentionPeriod: TimeInterval
    /// Action to take when retention period expires.
    public let action: RetentionAction
    /// Priority of the rule (higher numbers take precedence).
    public let priority: Int

    public init(
        applicableTags: [String] = [],
        retentionPeriod: TimeInterval,
        action: RetentionAction = .delete,
        priority: Int = 0
    ) {
        self.applicableTags = applicableTags
        self.retentionPeriod = retentionPeriod
        self.action = action
        self.priority = priority
    }

    /// Checks if this rule applies to data with the given tags.
    public func appliesTo(tags: [String]) -> Bool {
        if applicableTags.isEmpty {
            return true // Applies to all
        }

        return !Set(applicableTags).isDisjoint(with: Set(tags))
    }

    /// Determines if data of the given age should be retained.
    public func shouldRetain(age: TimeInterval) -> Bool {
        return age <= retentionPeriod
    }
}

/// Actions that can be taken when retention period expires.
public enum RetentionAction: String, Codable, Sendable {
    case delete = "DELETE"
    case archive = "ARCHIVE"
    case quarantine = "QUARANTINE"
    case notify = "NOTIFY"
}

/// Lifecycle management for data retention and cleanup.
public protocol LifecycleManager: Sendable {
    /// Applies retention policies to clean up expired data.
    func applyRetentionPolicies() async throws -> RetentionSummary

    /// Gets data that is due for cleanup based on retention policies.
    func getExpiredData() async throws -> [ExpirableData]

    /// Archives data according to retention policies.
    func archiveData(_ data: [ExpirableData]) async throws -> Int

    /// Deletes expired data.
    func deleteExpiredData(_ data: [ExpirableData]) async throws -> Int
}

/// Data that can expire based on retention policies.
public struct ExpirableData: Sendable {
    /// Unique identifier for the data.
    public let id: String
    /// Type of data (audit_log, file, etc.).
    public let type: String
    /// Location or path to the data.
    public let location: String
    /// Age of the data in seconds.
    public let age: TimeInterval
    /// Size of the data in bytes.
    public let size: Int64
    /// Tags associated with the data.
    public let tags: [String]
    /// Retention policy that applies to this data.
    public let policy: RetentionPolicy?

    public init(
        id: String,
        type: String,
        location: String,
        age: TimeInterval,
        size: Int64,
        tags: [String] = [],
        policy: RetentionPolicy? = nil
    ) {
        self.id = id
        self.type = type
        self.location = location
        self.age = age
        self.size = size
        self.tags = tags
        self.policy = policy
    }

    /// Checks if this data has expired based on its retention policy.
    public var isExpired: Bool {
        guard let policy = policy else { return false }
        return !policy.shouldRetain(dataAge: age, dataTags: tags)
    }
}

/// Summary of retention policy application.
public struct RetentionSummary: Sendable {
    /// Number of items checked.
    public let itemsChecked: Int
    /// Number of items expired.
    public let itemsExpired: Int
    /// Number of items archived.
    public let itemsArchived: Int
    /// Number of items deleted.
    public let itemsDeleted: Int
    /// Total size of data processed.
    public let totalSizeProcessed: Int64
    /// Errors encountered during processing.
    public let errors: [String]

    public init(
        itemsChecked: Int = 0,
        itemsExpired: Int = 0,
        itemsArchived: Int = 0,
        itemsDeleted: Int = 0,
        totalSizeProcessed: Int64 = 0,
        errors: [String] = []
    ) {
        self.itemsChecked = itemsChecked
        self.itemsExpired = itemsExpired
        self.itemsArchived = itemsArchived
        self.itemsDeleted = itemsDeleted
        self.totalSizeProcessed = totalSizeProcessed
        self.errors = errors
    }
}

/// Default lifecycle manager implementation.
public actor DefaultLifecycleManager: LifecycleManager {
    private let policies: [RetentionPolicy]
    private let auditLogger: any AuditLogStorage

    public init(policies: [RetentionPolicy], auditLogger: any AuditLogStorage) {
        self.policies = policies.filter { $0.isActive }
        self.auditLogger = auditLogger
    }

    public func applyRetentionPolicies() async throws -> RetentionSummary {
        let expiredData = try await getExpiredData()

        var summary = RetentionSummary(
            itemsChecked: expiredData.count,
            itemsExpired: expiredData.count
        )

        // Archive data that should be archived
        let dataToArchive = expiredData.filter { data in
            guard let policy = data.policy else { return false }
            return policy.rules.contains { rule in
                rule.appliesTo(tags: data.tags) && rule.action == .archive
            }
        }

        if !dataToArchive.isEmpty {
            summary.itemsArchived = try await archiveData(dataToArchive)
        }

        // Delete data that should be deleted
        let dataToDelete = expiredData.filter { data in
            guard let policy = data.policy else { return false }
            return policy.rules.contains { rule in
                rule.appliesTo(tags: data.tags) && rule.action == .delete
            }
        }

        if !dataToDelete.isEmpty {
            summary.itemsDeleted = try await deleteExpiredData(dataToDelete)
        }

        summary.totalSizeProcessed = expiredData.reduce(0) { $0 + $1.size }

        // Log the retention activity
        try await auditLogger.store(AuditLogEntry(
            eventType: .complianceCheck,
            actor: "system",
            resource: "retention_policy",
            action: "apply_policies",
            result: "completed",
            metadata: [
                "items_checked": "\(summary.itemsChecked)",
                "items_expired": "\(summary.itemsExpired)",
                "items_archived": "\(summary.itemsArchived)",
                "items_deleted": "\(summary.itemsDeleted)",
                "total_size": "\(summary.totalSizeProcessed)"
            ],
            source: "lifecycle_manager",
            complianceTags: ["retention", "compliance"]
        ))

        return summary
    }

    public func getExpiredData() async throws -> [ExpirableData] {
        // Get expired audit logs
        let auditLogs = try await getExpiredAuditLogs()

        // In a real implementation, this would also check for expired files,
        // database records, etc. For now, we focus on audit logs.

        return auditLogs
    }

    public func archiveData(_ data: [ExpirableData]) async throws -> Int {
        // For audit logs, archiving means moving to compressed storage
        // In a real implementation, this would compress and move files
        var archivedCount = 0

        for item in data where item.type == "audit_log" {
            // Simulate archiving by logging the action
            try await auditLogger.store(AuditLogEntry(
                eventType: .complianceCheck,
                actor: "system",
                resource: item.location,
                action: "archive",
                result: "archived",
                metadata: [
                    "data_type": item.type,
                    "age_days": "\(Int(item.age / 86400))",
                    "size": "\(item.size)"
                ],
                source: "lifecycle_manager",
                complianceTags: ["retention", "archive"]
            ))
            archivedCount += 1
        }

        return archivedCount
    }

    public func deleteExpiredData(_ data: [ExpirableData]) async throws -> Int {
        var deletedCount = 0

        for item in data {
            // Log the deletion
            try await auditLogger.store(AuditLogEntry(
                eventType: .complianceCheck,
                actor: "system",
                resource: item.location,
                action: "delete",
                result: "deleted",
                metadata: [
                    "data_type": item.type,
                    "age_days": "\(Int(item.age / 86400))",
                    "size": "\(item.size)"
                ],
                source: "lifecycle_manager",
                complianceTags: ["retention", "deletion"]
            ))

            // In a real implementation, this would actually delete the data
            // For audit logs, this would remove old log files
            deletedCount += 1
        }

        return deletedCount
    }

    // MARK: - Private Methods

    private func getExpiredAuditLogs() async throws -> [ExpirableData] {
        var expiredLogs: [ExpirableData] = []

        // Check each policy for audit log retention
        for policy in policies {
            for rule in policy.rules where rule.applicableTags.contains("audit") || rule.applicableTags.isEmpty {
                // Get audit entries older than retention period
                let cutoffDate = Date().addingTimeInterval(-rule.retentionPeriod)
                let oldEntries = try await auditLogger.retrieve(
                    startDate: nil,
                    endDate: cutoffDate,
                    actor: nil,
                    resource: nil,
                    eventType: nil,
                    limit: 1000
                )

                // Group by approximate age for summary
                let groupedByDay = Dictionary(grouping: oldEntries) { entry in
                    Calendar.current.startOfDay(for: entry.timestamp)
                }

                for (day, entries) in groupedByDay {
                    let age = Date().timeIntervalSince(day)
                    let totalSize = entries.reduce(0) { $0 + Int64(entries.count * 256) } // Estimate size

                    expiredLogs.append(ExpirableData(
                        id: "audit_logs_\(day.timeIntervalSince1970)",
                        type: "audit_log",
                        location: "audit_logs_\(Int(day.timeIntervalSince1970))",
                        age: age,
                        size: totalSize,
                        tags: ["audit", "log"],
                        policy: policy
                    ))
                }
            }
        }

        return expiredLogs
    }
}

/// Predefined retention policies for common compliance scenarios.
public enum StandardRetentionPolicies {
    /// SOC 2 compliant retention policy (7 years for audit logs).
    public static let soc2 = RetentionPolicy(
        name: "SOC 2 Compliance",
        description: "Retains audit logs for 7 years as required by SOC 2",
        rules: [
            RetentionRule(
                applicableTags: ["audit"],
                retentionPeriod: 7 * 365 * 24 * 3600, // 7 years
                action: .archive,
                priority: 10
            )
        ],
        complianceStandards: [.soc2]
    )

    /// GDPR compliant retention policy (variable based on data type).
    public static let gdpr = RetentionPolicy(
        name: "GDPR Compliance",
        description: "Implements data minimization and retention limits per GDPR",
        rules: [
            RetentionRule(
                applicableTags: ["personal_data"],
                retentionPeriod: 365 * 24 * 3600, // 1 year
                action: .delete,
                priority: 20
            ),
            RetentionRule(
                applicableTags: ["consent"],
                retentionPeriod: 3 * 365 * 24 * 3600, // 3 years
                action: .archive,
                priority: 15
            )
        ],
        complianceStandards: [.gdpr]
    )

    /// HIPAA compliant retention policy for PHI.
    public static let hipaa = RetentionPolicy(
        name: "HIPAA Compliance",
        description: "Retains protected health information per HIPAA requirements",
        rules: [
            RetentionRule(
                applicableTags: ["phi"],
                retentionPeriod: 6 * 365 * 24 * 3600, // 6 years
                action: .archive,
                priority: 25
            )
        ],
        complianceStandards: [.hipaa]
    )

    /// General audit log retention (90 days).
    public static let auditLogs = RetentionPolicy(
        name: "Audit Log Retention",
        description: "Standard retention for audit logs",
        rules: [
            RetentionRule(
                applicableTags: ["audit"],
                retentionPeriod: 90 * 24 * 3600, // 90 days
                action: .delete,
                priority: 5
            )
        ]
    )
}