import Foundation

/// Backup configuration and scheduling.
public struct BackupConfiguration: Codable, Sendable {
    /// Unique identifier for the backup configuration.
    public let id: String
    /// Name of the backup configuration.
    public let name: String
    /// Description of the backup purpose.
    public let description: String
    /// Source cloud configuration.
    public let sourceConfig: CloudConfig
    /// Source bucket/container name.
    public let sourceBucket: String
    /// Destination cloud configuration (can be same or different provider).
    public let destinationConfig: CloudConfig
    /// Destination bucket/container name.
    public let destinationBucket: String
    /// Backup schedule (cron expression or predefined schedule).
    public let schedule: BackupSchedule
    /// Retention policy for backups.
    public let retentionPolicy: BackupRetentionPolicy
    /// Whether the backup is currently enabled.
    public let isEnabled: Bool
    /// Optional prefix for backup objects.
    public let prefix: String?
    /// Compression settings.
    public let compression: CompressionSettings
    /// Encryption settings for backups.
    public let encryption: BackupEncryptionSettings

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        sourceConfig: CloudConfig,
        sourceBucket: String,
        destinationConfig: CloudConfig,
        destinationBucket: String,
        schedule: BackupSchedule,
        retentionPolicy: BackupRetentionPolicy,
        isEnabled: Bool = true,
        prefix: String? = nil,
        compression: CompressionSettings = .default,
        encryption: BackupEncryptionSettings = .default
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sourceConfig = sourceConfig
        self.sourceBucket = sourceBucket
        self.destinationConfig = destinationConfig
        self.destinationBucket = destinationBucket
        self.schedule = schedule
        self.retentionPolicy = retentionPolicy
        self.isEnabled = isEnabled
        self.prefix = prefix
        self.compression = compression
        self.encryption = encryption
    }
}

/// Backup scheduling options.
public enum BackupSchedule: Codable, Sendable {
    /// Run backup at specific hour every day.
    case daily(hour: Int, minute: Int = 0)
    /// Run backup on specific day of week at specific time.
    case weekly(dayOfWeek: Int, hour: Int, minute: Int = 0)
    /// Run backup on specific day of month at specific time.
    case monthly(dayOfMonth: Int, hour: Int, minute: Int = 0)
    /// Custom cron expression.
    case cron(String)
    /// Manual backups only.
    case manual

    /// Calculates the next backup date from the given date.
    public func nextBackupDate(from date: Date = Date()) -> Date? {
        let calendar = Calendar.current

        switch self {
        case .daily(let hour, let minute):
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            var nextDate = calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: components.day,
                hour: hour,
                minute: minute
            ))!

            if nextDate <= date {
                nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate)!
            }
            return nextDate

        case .weekly(let dayOfWeek, let hour, let minute):
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            var nextDate = calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: components.day,
                hour: hour,
                minute: minute
            ))!

            // Find the next occurrence of the specified day of week
            let currentDayOfWeek = calendar.component(.weekday, from: nextDate)
            let daysToAdd = (dayOfWeek - currentDayOfWeek + 7) % 7
            if daysToAdd == 0 && nextDate <= date {
                nextDate = calendar.date(byAdding: .day, value: 7, to: nextDate)!
            } else {
                nextDate = calendar.date(byAdding: .day, value: daysToAdd, to: nextDate)!
            }
            return nextDate

        case .monthly(let dayOfMonth, let hour, let minute):
            let components = calendar.dateComponents([.year, .month], from: date)
            var nextDate = calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: dayOfMonth,
                hour: hour,
                minute: minute
            ))!

            if nextDate <= date {
                nextDate = calendar.date(byAdding: .month, value: 1, to: nextDate)!
            }
            return nextDate

        case .cron:
            // For simplicity, return next hour for cron expressions
            // In production, this would parse and calculate proper cron scheduling
            return calendar.date(byAdding: .hour, value: 1, to: date)

        case .manual:
            return nil
        }
    }
}

/// Backup retention policy.
public struct BackupRetentionPolicy: Codable, Sendable {
    /// Keep all backups for this many days.
    public let keepDaily: Int
    /// Keep weekly backups for this many weeks.
    public let keepWeekly: Int
    /// Keep monthly backups for this many months.
    public let keepMonthly: Int
    /// Keep yearly backups for this many years.
    public let keepYearly: Int
    /// Maximum number of backups to keep (0 = unlimited).
    public let maxBackups: Int

    public init(
        keepDaily: Int = 7,
        keepWeekly: Int = 4,
        keepMonthly: Int = 12,
        keepYearly: Int = 7,
        maxBackups: Int = 0
    ) {
        self.keepDaily = keepDaily
        self.keepWeekly = keepWeekly
        self.keepMonthly = keepMonthly
        self.keepYearly = keepYearly
        self.maxBackups = maxBackups
    }

    /// Determines if a backup should be retained based on its age and the policy.
    public func shouldRetain(backupDate: Date, currentDate: Date = Date()) -> Bool {
        let age = currentDate.timeIntervalSince(backupDate)
        let calendar = Calendar.current

        // Check yearly retention
        if keepYearly > 0 {
            let yearsAgo = calendar.date(byAdding: .year, value: -keepYearly, to: currentDate)!
            if backupDate >= yearsAgo {
                return true
            }
        }

        // Check monthly retention
        if keepMonthly > 0 {
            let monthsAgo = calendar.date(byAdding: .month, value: -keepMonthly, to: currentDate)!
            if backupDate >= monthsAgo {
                return true
            }
        }

        // Check weekly retention
        if keepWeekly > 0 {
            let weeksAgo = calendar.date(byAdding: .day, value: -keepWeekly * 7, to: currentDate)!
            if backupDate >= weeksAgo {
                return true
            }
        }

        // Check daily retention
        if keepDaily > 0 {
            let daysAgo = calendar.date(byAdding: .day, value: -keepDaily, to: currentDate)!
            if backupDate >= daysAgo {
                return true
            }
        }

        return false
    }
}

/// Compression settings for backups.
public struct CompressionSettings: Codable, Sendable {
    /// Compression algorithm to use.
    public let algorithm: CompressionAlgorithm
    /// Compression level (1-9, where 9 is maximum compression).
    public let level: Int
    /// Whether to enable compression.
    public let enabled: Bool

    public init(algorithm: CompressionAlgorithm = .gzip, level: Int = 6, enabled: Bool = true) {
        self.algorithm = algorithm
        self.level = level
        self.enabled = enabled
    }

    public static let `default` = CompressionSettings()
    public static let disabled = CompressionSettings(enabled: false)
}

/// Compression algorithms.
public enum CompressionAlgorithm: String, Codable, Sendable {
    case gzip = "gzip"
    case bzip2 = "bzip2"
    case xz = "xz"
}

/// Encryption settings for backups.
public struct BackupEncryptionSettings: Codable, Sendable {
    /// Whether to enable encryption for backups.
    public let enabled: Bool
    /// Encryption algorithm.
    public let algorithm: String
    /// Key derivation function.
    public let kdf: String
    /// Additional encryption parameters.
    public let parameters: [String: String]

    public init(
        enabled: Bool = true,
        algorithm: String = "AES-256-GCM",
        kdf: String = "PBKDF2",
        parameters: [String: String] = [:]
    ) {
        self.enabled = enabled
        self.algorithm = algorithm
        self.kdf = kdf
        self.parameters = parameters
    }

    public static let `default` = BackupEncryptionSettings()
    public static let disabled = BackupEncryptionSettings(enabled: false)
}

/// Backup job status and metadata.
public struct BackupJob: Codable, Sendable {
    /// Unique identifier for the backup job.
    public let id: String
    /// Reference to the backup configuration.
    public let configurationId: String
    /// Timestamp when the backup was started.
    public let startedAt: Date
    /// Timestamp when the backup completed (nil if still running).
    public var completedAt: Date?
    /// Current status of the backup job.
    public var status: BackupStatus
    /// Progress information.
    public var progress: BackupProgress
    /// Error message if the backup failed.
    public let errorMessage: String?
    /// Backup metadata.
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        configurationId: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        status: BackupStatus = .running,
        progress: BackupProgress = .init(),
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.configurationId = configurationId
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.metadata = metadata
    }

    /// Duration of the backup job.
    public var duration: TimeInterval? {
        guard let completedAt = completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }
}

/// Backup job status.
public enum BackupStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case running = "RUNNING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

/// Backup progress information.
public struct BackupProgress: Codable, Sendable {
    /// Number of objects processed.
    public var objectsProcessed: Int
    /// Total number of objects to process.
    public let objectsTotal: Int
    /// Number of bytes processed.
    public var bytesProcessed: Int64
    /// Total number of bytes to process.
    public let bytesTotal: Int64
    /// Current operation being performed.
    public let currentOperation: String

    public init(
        objectsProcessed: Int = 0,
        objectsTotal: Int = 0,
        bytesProcessed: Int64 = 0,
        bytesTotal: Int64 = 0,
        currentOperation: String = ""
    ) {
        self.objectsProcessed = objectsProcessed
        self.objectsTotal = objectsTotal
        self.bytesProcessed = bytesProcessed
        self.bytesTotal = bytesTotal
        self.currentOperation = currentOperation
    }

    /// Progress percentage (0-100).
    public var percentage: Double {
        guard bytesTotal > 0 else { return 0 }
        return Double(bytesProcessed) / Double(bytesTotal) * 100.0
    }
}

/// Backup manifest containing metadata about backed up objects.
public struct BackupManifest: Codable, Sendable {
    /// Unique identifier for the backup.
    public let id: String
    /// Reference to the backup job.
    public let jobId: String
    /// Timestamp when the backup was created.
    public let createdAt: Date
    /// Source information.
    public let source: BackupSource
    /// List of backed up objects.
    public let objects: [BackupObject]
    /// Backup statistics.
    public let statistics: BackupStatistics

    public init(
        id: String = UUID().uuidString,
        jobId: String,
        createdAt: Date = Date(),
        source: BackupSource,
        objects: [BackupObject],
        statistics: BackupStatistics
    ) {
        self.id = id
        self.jobId = jobId
        self.createdAt = createdAt
        self.source = source
        self.objects = objects
        self.statistics = statistics
    }
}

/// Backup source information.
public struct BackupSource: Codable, Sendable {
    /// Cloud provider.
    public let provider: CloudProvider
    /// Bucket/container name.
    public let bucket: String
    /// Optional prefix for objects to backup.
    public let prefix: String?
    /// Region of the source.
    public let region: String

    public init(provider: CloudProvider, bucket: String, prefix: String? = nil, region: String) {
        self.provider = provider
        self.bucket = bucket
        self.prefix = prefix
        self.region = region
    }
}

/// Information about a backed up object.
public struct BackupObject: Codable, Sendable {
    /// Original key of the object.
    public let key: String
    /// Size of the object in bytes.
    public let size: Int64
    /// Last modified timestamp.
    public let lastModified: Date
    /// ETag of the object.
    public let etag: String?
    /// Backup-specific metadata.
    public let metadata: [String: String]

    public init(
        key: String,
        size: Int64,
        lastModified: Date,
        etag: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
        self.etag = etag
        self.metadata = metadata
    }
}

/// Backup statistics.
public struct BackupStatistics: Codable, Sendable {
    /// Total number of objects backed up.
    public let totalObjects: Int
    /// Total size of all objects in bytes.
    public let totalSize: Int64
    /// Number of objects that failed to backup.
    public let failedObjects: Int
    /// Start time of the backup.
    public let startTime: Date
    /// End time of the backup.
    public let endTime: Date

    public init(
        totalObjects: Int,
        totalSize: Int64,
        failedObjects: Int = 0,
        startTime: Date,
        endTime: Date
    ) {
        self.totalObjects = totalObjects
        self.totalSize = totalSize
        self.failedObjects = failedObjects
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Duration of the backup.
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Backup throughput in bytes per second.
    public var throughput: Double {
        guard duration > 0 else { return 0 }
        return Double(totalSize) / duration
    }
}