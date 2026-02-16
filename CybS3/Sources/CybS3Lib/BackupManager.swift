import Foundation

/// Protocol for backup storage implementations.
public protocol BackupStorage: Sendable {
    /// Stores a backup configuration.
    func storeConfiguration(_ config: BackupConfiguration) async throws

    /// Retrieves a backup configuration by ID.
    func getConfiguration(id: String) async throws -> BackupConfiguration?

    /// Lists all backup configurations.
    func listConfigurations() async throws -> [BackupConfiguration]

    /// Deletes a backup configuration.
    func deleteConfiguration(id: String) async throws

    /// Stores a backup job.
    func storeJob(_ job: BackupJob) async throws

    /// Retrieves a backup job by ID.
    func getJob(id: String) async throws -> BackupJob?

    /// Lists backup jobs for a configuration.
    func listJobs(for configurationId: String) async throws -> [BackupJob]

    /// Updates a backup job.
    func updateJob(_ job: BackupJob) async throws

    /// Deletes a backup job.
    func deleteJob(id: String) async throws

    /// Stores a backup manifest.
    func storeManifest(_ manifest: BackupManifest) async throws

    /// Retrieves a backup manifest by ID.
    func getManifest(id: String) async throws -> BackupManifest?

    /// Lists manifests for a job.
    func listManifests(for jobId: String) async throws -> [BackupManifest]
}

/// In-memory backup storage for testing.
public actor MemoryBackupStorage: BackupStorage {
    private var configurations: [String: BackupConfiguration] = [:]
    private var jobs: [String: BackupJob] = [:]
    private var manifests: [String: BackupManifest] = [:]

    public init() {}

    public func storeConfiguration(_ config: BackupConfiguration) async throws {
        configurations[config.id] = config
    }

    public func getConfiguration(id: String) async throws -> BackupConfiguration? {
        configurations[id]
    }

    public func listConfigurations() async throws -> [BackupConfiguration] {
        Array(configurations.values)
    }

    public func deleteConfiguration(id: String) async throws {
        configurations.removeValue(forKey: id)
    }

    public func storeJob(_ job: BackupJob) async throws {
        jobs[job.id] = job
    }

    public func getJob(id: String) async throws -> BackupJob? {
        jobs[id]
    }

    public func listJobs(for configurationId: String) async throws -> [BackupJob] {
        jobs.values.filter { $0.configurationId == configurationId }
    }

    public func updateJob(_ job: BackupJob) async throws {
        jobs[job.id] = job
    }

    public func deleteJob(id: String) async throws {
        jobs.removeValue(forKey: id)
    }

    public func storeManifest(_ manifest: BackupManifest) async throws {
        manifests[manifest.id] = manifest
    }

    public func getManifest(id: String) async throws -> BackupManifest? {
        manifests[id]
    }

    public func listManifests(for jobId: String) async throws -> [BackupManifest] {
        manifests.values.filter { $0.jobId == jobId }
    }

    /// Clears all data (for testing).
    public func clear() {
        configurations.removeAll()
        jobs.removeAll()
        manifests.removeAll()
    }
}

/// Backup manager for coordinating backup operations.
public actor BackupManager {
    private let storage: any BackupStorage
    private let auditLogger: any AuditLogStorage
    private var activeJobs: [String: Task<Void, Error>] = [:]

    public init(storage: any BackupStorage, auditLogger: any AuditLogStorage) {
        self.storage = storage
        self.auditLogger = auditLogger
    }

    /// Creates a new backup configuration.
    public func createConfiguration(_ config: BackupConfiguration) async throws {
        try await storage.storeConfiguration(config)

        try await auditLogger.store(entry: AuditLogEntry(
            eventType: .configurationChange,
            actor: "system",
            resource: "backup_configuration",
            action: "create",
            result: "success",
            metadata: [
                "config_id": config.id,
                "config_name": config.name,
                "source_provider": config.sourceConfig.provider.rawValue,
                "destination_provider": config.destinationConfig.provider.rawValue
            ],
            source: "backup_manager",
            complianceTags: ["backup", "configuration"]
        ))
    }

    /// Updates an existing backup configuration.
    public func updateConfiguration(_ config: BackupConfiguration) async throws {
        try await storage.storeConfiguration(config)

        try await auditLogger.store(entry: AuditLogEntry(
            eventType: .configurationChange,
            actor: "system",
            resource: "backup_configuration",
            action: "update",
            result: "success",
            metadata: ["config_id": config.id, "config_name": config.name],
            source: "backup_manager",
            complianceTags: ["backup", "configuration"]
        ))
    }

    /// Deletes a backup configuration.
    public func deleteConfiguration(id: String) async throws {
        try await storage.deleteConfiguration(id)

        try await auditLogger.store(entry: AuditLogEntry(
            eventType: .configurationChange,
            actor: "system",
            resource: "backup_configuration",
            action: "delete",
            result: "success",
            metadata: ["config_id": id],
            source: "backup_manager",
            complianceTags: ["backup", "configuration"]
        ))
    }

    /// Lists all backup configurations.
    public func listConfigurations() async throws -> [BackupConfiguration] {
        try await storage.listConfigurations()
    }

    /// Starts a backup job for the given configuration.
    public func startBackup(configurationId: String) async throws -> String {
        guard let config = try await storage.getConfiguration(id: configurationId) else {
            throw BackupError.configurationNotFound(configurationId)
        }

        let job = BackupJob(configurationId: configurationId)
        try await storage.storeJob(job)

        let task = Task {
            do {
                try await self.performBackup(job: job, config: config)
            } catch {
                // Update job status on failure
                var failedJob = job
                failedJob.status = .failed
                failedJob.completedAt = Date()
                failedJob.errorMessage = error.localizedDescription
                try await storage.updateJob(failedJob)

                try await auditLogger.store(entry: AuditLogEntry(
                    eventType: .operationFailed,
                    actor: "system",
                    resource: "backup_job",
                    action: "backup",
                    result: "failed",
                    metadata: [
                        "job_id": job.id,
                        "config_id": configurationId,
                        "error": error.localizedDescription
                    ],
                    source: "backup_manager",
                    complianceTags: ["backup", "error"]
                ))
            }
        }

        activeJobs[job.id] = task

        try await auditLogger.store(entry: AuditLogEntry(
            eventType: .operationStart,
            actor: "system",
            resource: "backup_job",
            action: "backup",
            result: "started",
            metadata: ["job_id": job.id, "config_id": configurationId],
            source: "backup_manager",
            complianceTags: ["backup"]
        ))

        return job.id
    }

    /// Cancels a running backup job.
    public func cancelBackup(jobId: String) async throws {
        if let task = activeJobs[jobId] {
            task.cancel()
            activeJobs.removeValue(forKey: jobId)

            if var job = try await storage.getJob(id: jobId) {
                job.status = .cancelled
                job.completedAt = Date()
                try await storage.updateJob(job)
            }

            try await auditLogger.store(entry: AuditLogEntry(
                eventType: .operationComplete,
                actor: "system",
                resource: "backup_job",
                action: "cancel_backup",
                result: "cancelled",
                metadata: ["job_id": jobId],
                source: "backup_manager",
                complianceTags: ["backup"]
            ))
        }
    }

    /// Gets the status of a backup job.
    public func getJobStatus(jobId: String) async throws -> BackupJob? {
        try await storage.getJob(id: jobId)
    }

    /// Lists backup jobs for a configuration.
    public func listJobs(for configurationId: String) async throws -> [BackupJob] {
        try await storage.listJobs(for: configurationId)
    }

    /// Cleans up old backups based on retention policies.
    public func cleanupOldBackups() async throws {
        let configurations = try await storage.listConfigurations()

        for config in configurations where config.isEnabled {
            try await cleanupConfigurationBackups(config)
        }

        try await auditLogger.store(entry: AuditLogEntry(
            eventType: .complianceCheck,
            actor: "system",
            resource: "backup_cleanup",
            action: "cleanup",
            result: "completed",
            source: "backup_manager",
            complianceTags: ["backup", "retention"]
        ))
    }

    // MARK: - Private Methods

    private func performBackup(job: BackupJob, config: BackupConfiguration) async throws {
        var updatedJob = job
        updatedJob.status = .running
        try await storage.updateJob(updatedJob)

        let startTime = Date()

        do {
            // Create cloud clients
            let sourceClient = try CloudClientFactory.createCloudClient(
                config: config.sourceConfig,
                bucket: config.sourceBucket,
                auditLogger: auditLogger,
                sessionId: job.id
            )

            let destClient = try CloudClientFactory.createCloudClient(
                config: config.destinationConfig,
                bucket: config.destinationBucket,
                auditLogger: auditLogger,
                sessionId: job.id
            )

            // List objects to backup
            let objects = try await sourceClient.list(prefix: config.prefix)
            updatedJob.progress.objectsTotal = objects.count
            updatedJob.progress.bytesTotal = objects.reduce(0) { $0 + $1.size }
            try await storage.updateJob(updatedJob)

            // Backup objects
            var backedUpObjects: [BackupObject] = []
            var failedCount = 0

            for (index, object) in objects.enumerated() {
                do {
                    // Download from source
                    let data = try await sourceClient.download(key: object.key)

                    // Apply compression if enabled
                    let processedData = try await processDataForBackup(data, config: config)

                    // Generate backup key
                    let backupKey = generateBackupKey(originalKey: object.key, config: config, timestamp: startTime)

                    // Upload to destination
                    try await destClient.upload(key: backupKey, data: processedData)

                    let backupObject = BackupObject(
                        key: object.key,
                        size: object.size,
                        lastModified: object.lastModified ?? Date(),
                        etag: object.etag,
                        metadata: [
                            "backup_key": backupKey,
                            "compressed": config.compression.enabled.description,
                            "encrypted": config.encryption.enabled.description
                        ]
                    )
                    backedUpObjects.append(backupObject)

                } catch {
                    failedCount += 1
                    try await auditLogger.store(entry: AuditLogEntry(
                        eventType: .operationFailed,
                        actor: "system",
                        resource: object.key,
                        action: "backup_object",
                        result: "failed",
                        metadata: [
                            "job_id": job.id,
                            "error": error.localizedDescription
                        ],
                        source: "backup_manager",
                        complianceTags: ["backup", "error"]
                    ))
                }

                // Update progress
                updatedJob.progress.objectsProcessed = index + 1
                updatedJob.progress.bytesProcessed = backedUpObjects.reduce(0) { $0 + $1.size }
                updatedJob.progress.currentOperation = "Backing up \(object.key)"
                try await storage.updateJob(updatedJob)
            }

            // Create backup manifest
            let manifest = BackupManifest(
                jobId: job.id,
                source: BackupSource(
                    provider: config.sourceConfig.provider,
                    bucket: config.sourceBucket,
                    prefix: config.prefix,
                    region: config.sourceConfig.region
                ),
                objects: backedUpObjects,
                statistics: BackupStatistics(
                    totalObjects: backedUpObjects.count,
                    totalSize: backedUpObjects.reduce(0) { $0 + $1.size },
                    failedObjects: failedCount,
                    startTime: startTime,
                    endTime: Date()
                )
            )

            try await storage.storeManifest(manifest)

            // Complete the job
            updatedJob.status = .completed
            updatedJob.completedAt = Date()
            updatedJob.progress.objectsProcessed = objects.count
            updatedJob.progress.bytesProcessed = updatedJob.progress.bytesTotal
            try await storage.updateJob(updatedJob)

            try await auditLogger.store(entry: AuditLogEntry(
                eventType: .operationComplete,
                actor: "system",
                resource: "backup_job",
                action: "backup",
                result: "completed",
                metadata: [
                    "job_id": job.id,
                    "objects_backed_up": "\(backedUpObjects.count)",
                    "total_size": "\(updatedJob.progress.bytesTotal)",
                    "duration": "\(updatedJob.duration ?? 0)"
                ],
                source: "backup_manager",
                complianceTags: ["backup", "success"]
            ))

        } catch {
            updatedJob.status = .failed
            updatedJob.completedAt = Date()
            updatedJob.errorMessage = error.localizedDescription
            try await storage.updateJob(updatedJob)
            throw error
        }
    }

    private func processDataForBackup(_ data: Data, config: BackupConfiguration) async throws -> Data {
        var processedData = data

        // Apply compression
        if config.compression.enabled {
            processedData = try compressData(processedData, algorithm: config.compression.algorithm)
        }

        // Apply encryption
        if config.encryption.enabled {
            // In a real implementation, this would use proper encryption
            // For now, we'll just add a simple marker
            processedData = try encryptDataForBackup(processedData, config: config.encryption)
        }

        return processedData
    }

    private func compressData(_ data: Data, algorithm: CompressionAlgorithm) throws -> Data {
        // Placeholder - compression not implemented yet
        // TODO: Implement compression using appropriate library
        return data
    }

    private func encryptDataForBackup(_ data: Data, config: BackupEncryptionSettings) throws -> Data {
        // Simple encryption marker
        // In production, this would use proper encryption
        return data // Placeholder - return unencrypted for now
    }

    private func generateBackupKey(originalKey: String, config: BackupConfiguration, timestamp: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestampStr = dateFormatter.string(from: timestamp)

        let prefix = config.prefix ?? "backup"
        return "\(prefix)/\(timestampStr)/\(originalKey)"
    }

    private func cleanupConfigurationBackups(_ config: BackupConfiguration) async throws {
        let jobs = try await storage.listJobs(for: config.id)
        let completedJobs = jobs.filter { $0.status == BackupStatus.completed }

        // Sort by completion date (newest first)
        let sortedJobs = completedJobs.sorted { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) }

        // Apply retention policy
        var jobsToDelete: [BackupJob] = []

        for (index, job) in sortedJobs.enumerated() {
            if let completedAt = job.completedAt,
               !config.retentionPolicy.shouldRetain(backupDate: completedAt) {
                jobsToDelete.append(job)
            }

            // Check max backups limit
            if config.retentionPolicy.maxBackups > 0 && index >= config.retentionPolicy.maxBackups {
                jobsToDelete.append(job)
            }
        }

        // Delete old jobs and their manifests
        for job in jobsToDelete {
            try await storage.deleteJob(id: job.id)

            // In a real implementation, we would also delete the actual backup files
            // from the destination storage

            try await auditLogger.store(entry: AuditLogEntry(
                eventType: .complianceCheck,
                actor: "system",
                resource: "backup_job",
                action: "cleanup",
                result: "deleted",
                metadata: [
                    "job_id": job.id,
                    "config_id": config.id,
                    "completed_at": job.completedAt?.description ?? "unknown"
                ],
                source: "backup_manager",
                complianceTags: ["backup", "retention", "cleanup"]
            ))
        }
    }
}

/// Backup-related errors.
public enum BackupError: Error, LocalizedError {
    case configurationNotFound(String)
    case jobNotFound(String)
    case backupInProgress(String)
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .configurationNotFound(let id):
            return "Backup configuration not found: \(id)"
        case .jobNotFound(let id):
            return "Backup job not found: \(id)"
        case .backupInProgress(let id):
            return "Backup already in progress: \(id)"
        case .invalidConfiguration(let reason):
            return "Invalid backup configuration: \(reason)"
        }
    }
}