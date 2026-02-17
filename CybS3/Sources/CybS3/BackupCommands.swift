import Foundation
import ArgumentParser
import CybS3Lib

/// Backup and disaster recovery commands.
struct BackupCommands: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Manage backup configurations and disaster recovery operations",
        subcommands: [
            CreateBackupConfig.self,
            ListBackupConfigs.self,
            UpdateBackupConfig.self,
            DeleteBackupConfig.self,
            StartBackup.self,
            CancelBackup.self,
            ListBackupJobs.self,
            GetBackupStatus.self,
            CleanupBackups.self,
            InitiateRecovery.self,
            ExecuteRecovery.self,
            TestRecovery.self,
            ValidateRecovery.self
        ]
    )
}

/// Create a new backup configuration.
struct CreateBackupConfig: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-config",
        abstract: "Create a new backup configuration"
    )

    @Option(name: .shortAndLong, help: "Name of the backup configuration")
    var name: String

    @Option(name: .shortAndLong, help: "Source cloud provider (aws, gcp, azure, etc.)")
    var sourceProvider: String

    @Option(name: .shortAndLong, help: "Source region")
    var sourceRegion: String

    @Option(name: .shortAndLong, help: "Source bucket name")
    var sourceBucket: String

    @Option(name: .shortAndLong, help: "Destination cloud provider")
    var destProvider: String

    @Option(name: .shortAndLong, help: "Destination region")
    var destRegion: String

    @Option(name: .shortAndLong, help: "Destination bucket name")
    var destBucket: String

    @Option(name: .long, help: "Object prefix to backup (optional)")
    var prefix: String?

    @Option(name: .long, help: "Backup schedule (cron, daily, weekly, monthly)")
    var schedule: String = "daily"

    @Option(name: .long, help: "Retention period in days")
    var retentionDays: Int = 30

    @Option(name: .long, help: "Maximum number of backups to keep")
    var maxBackups: Int = 10

    @Option(name: .long, help: "Enable compression (true/false)")
    var compression: Bool = true

    @Option(name: .long, help: "Enable encryption (true/false)")
    var encryption: Bool = true

    func run() async throws {
        do {
            // Parse providers
            guard let sourceProviderEnum = CloudProvider(rawValue: sourceProvider.lowercased()) else {
                ConsoleUI.error("Invalid source provider: \(sourceProvider)")
                throw ValidationError("Invalid source provider")
            }

            guard let destProviderEnum = CloudProvider(rawValue: destProvider.lowercased()) else {
                ConsoleUI.error("Invalid destination provider: \(destProvider)")
                throw ValidationError("Invalid destination provider")
            }

            // Get credentials from environment/keychain
            let sourceConfig = try await getCloudConfig(for: sourceProviderEnum, region: sourceRegion)
            let destConfig = try await getCloudConfig(for: destProviderEnum, region: destRegion)

            // Parse schedule
            let backupSchedule: BackupSchedule
            switch schedule.lowercased() {
            case "cron":
                // For simplicity, use daily for cron
                backupSchedule = .daily(hour: 2, minute: 0)
            case "daily":
                backupSchedule = .daily(hour: 2, minute: 0)
            case "weekly":
                backupSchedule = .weekly(dayOfWeek: 1, hour: 2, minute: 0)
            case "monthly":
                backupSchedule = .monthly(dayOfMonth: 1, hour: 2, minute: 0)
            default:
                ConsoleUI.error("Invalid schedule: \(schedule)")
                throw ValidationError("Invalid schedule")
            }

            // Create retention policy
            let retentionPolicy = BackupRetentionPolicy(
                keepDaily: retentionDays,
                keepWeekly: 4,
                keepMonthly: 12,
                keepYearly: 7,
                maxBackups: maxBackups
            )

            // Create compression settings
            let compressionSettings = CompressionSettings(
                algorithm: .gzip,
                enabled: compression
            )

            // Create encryption settings
            let encryptionSettings = BackupEncryptionSettings(
                enabled: encryption,
                algorithm: "AES-256-GCM"
            )

            // Create backup configuration
            let config = BackupConfiguration(
                name: name,
                description: "Backup configuration created via CLI",
                sourceConfig: sourceConfig,
                sourceBucket: sourceBucket,
                destinationConfig: destConfig,
                destinationBucket: destBucket,
                schedule: backupSchedule,
                retentionPolicy: retentionPolicy,
                compression: compressionSettings,
                encryption: encryptionSettings
            )

            // Get backup manager from dependency container
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            try await backupManager.createConfiguration(config)

            ConsoleUI.success("Backup configuration '\(name)' created successfully")
            ConsoleUI.info("Configuration ID: \(config.id)")

        } catch {
            ConsoleUI.error("Failed to create backup configuration: \(error.localizedDescription)")
            throw error
        }
    }
}

/// List all backup configurations.
struct ListBackupConfigs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-configs",
        abstract: "List all backup configurations"
    )

    @Flag(name: .long, help: "Show detailed information")
    var detailed: Bool = false

    func run() async throws {
        do {
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            let configs = try await backupManager.listConfigurations()

            if configs.isEmpty {
                ConsoleUI.info("No backup configurations found")
                return
            }

            ConsoleUI.info("Backup Configurations:")
            ConsoleUI.info(String(repeating: "=", count: 80))

            for config in configs {
                ConsoleUI.info("Name: \(config.name)")
                ConsoleUI.info("ID: \(config.id)")
                ConsoleUI.info("Source: \(config.sourceConfig.provider.rawValue)/\(config.sourceBucket)")
                ConsoleUI.info("Destination: \(config.destinationConfig.provider.rawValue)/\(config.destinationBucket)")
                ConsoleUI.info("Schedule: \(config.schedule.description)")
                ConsoleUI.info("Enabled: \(config.isEnabled ? "Yes" : "No")")

                if detailed {
                    ConsoleUI.info("Retention: Daily=\(config.retentionPolicy.keepDaily), Weekly=\(config.retentionPolicy.keepWeekly), Monthly=\(config.retentionPolicy.keepMonthly), Max=\(config.retentionPolicy.maxBackups)")
                    ConsoleUI.info("Compression: \(config.compression.enabled ? "Enabled" : "Disabled")")
                    ConsoleUI.info("Encryption: \(config.encryption.enabled ? "Enabled" : "Disabled")")
                    if let prefix = config.prefix {
                        ConsoleUI.info("Prefix: \(prefix)")
                    }
                }

                ConsoleUI.info("")
            }

        } catch {
            ConsoleUI.error("Failed to list backup configurations: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Update an existing backup configuration.
struct UpdateBackupConfig: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-config",
        abstract: "Update an existing backup configuration"
    )

    @Argument(help: "Configuration ID to update")
    var configId: String

    @Option(name: .shortAndLong, help: "New name for the configuration")
    var name: String?

    @Option(name: .long, help: "Enable or disable the configuration (true/false)")
    var enabled: Bool?

    @Option(name: .long, help: "New retention period in days")
    var retentionDays: Int?

    @Option(name: .long, help: "New maximum number of backups")
    var maxBackups: Int?

    func run() async throws {
        do {
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            guard let existingConfig = try await backupManager.listConfigurations()
                .first(where: { $0.id == configId }) else {
                ConsoleUI.error("Backup configuration not found: \(configId)")
                throw ValidationError("Configuration not found")
            }

            // Create updated configuration
            let updatedConfig = BackupConfiguration(
                id: existingConfig.id,
                name: name ?? existingConfig.name,
                description: existingConfig.description,
                sourceConfig: existingConfig.sourceConfig,
                sourceBucket: existingConfig.sourceBucket,
                destinationConfig: existingConfig.destinationConfig,
                destinationBucket: existingConfig.destinationBucket,
                schedule: existingConfig.schedule,
                retentionPolicy: BackupRetentionPolicy(
                    keepDaily: retentionDays ?? existingConfig.retentionPolicy.keepDaily,
                    keepWeekly: existingConfig.retentionPolicy.keepWeekly,
                    keepMonthly: existingConfig.retentionPolicy.keepMonthly,
                    keepYearly: existingConfig.retentionPolicy.keepYearly,
                    maxBackups: maxBackups ?? existingConfig.retentionPolicy.maxBackups
                ),
                isEnabled: enabled ?? existingConfig.isEnabled,
                prefix: existingConfig.prefix,
                compression: existingConfig.compression,
                encryption: existingConfig.encryption
            )

            try await backupManager.updateConfiguration(updatedConfig)

            ConsoleUI.success("Backup configuration updated successfully")

        } catch {
            ConsoleUI.error("Failed to update backup configuration: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Delete a backup configuration.
struct DeleteBackupConfig: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-config",
        abstract: "Delete a backup configuration"
    )

    @Argument(help: "Configuration ID to delete")
    var configId: String

    @Flag(name: .shortAndLong, help: "Force deletion without confirmation")
    var force: Bool = false

    func run() async throws {
        do {
            if !force {
                ConsoleUI.warning("This will delete the backup configuration and all associated jobs.")
                ConsoleUI.info("Use --force to skip this confirmation.")
                return
            }

            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            try await backupManager.deleteConfiguration(id: configId)

            ConsoleUI.success("Backup configuration deleted successfully")

        } catch {
            ConsoleUI.error("Failed to delete backup configuration: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Start a backup job.
struct StartBackup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start a backup job for a configuration"
    )

    @Argument(help: "Configuration ID to backup")
    var configId: String

    func run() async throws {
        do {
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            let jobId = try await backupManager.startBackup(configurationId: configId)

            ConsoleUI.success("Backup job started successfully")
            ConsoleUI.info("Job ID: \(jobId)")

        } catch {
            ConsoleUI.error("Failed to start backup: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Cancel a running backup job.
struct CancelBackup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cancel",
        abstract: "Cancel a running backup job"
    )

    @Argument(help: "Job ID to cancel")
    var jobId: String

    func run() async throws {
        do {
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            try await backupManager.cancelBackup(jobId: jobId)

            ConsoleUI.success("Backup job cancelled successfully")

        } catch {
            ConsoleUI.error("Failed to cancel backup: \(error.localizedDescription)")
            throw error
        }
    }
}

/// List backup jobs for a configuration.
struct ListBackupJobs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-jobs",
        abstract: "List backup jobs for a configuration"
    )

    @Argument(help: "Configuration ID")
    var configId: String

    @Flag(name: .long, help: "Show detailed information")
    var detailed: Bool = false

    func run() async throws {
        do {
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            let jobs = try await backupManager.listJobs(for: configId)

            if jobs.isEmpty {
                ConsoleUI.info("No backup jobs found for configuration \(configId)")
                return
            }

            ConsoleUI.info("Backup Jobs for Configuration \(configId):")
            ConsoleUI.info(String(repeating: "=", count: 80))

            for job in jobs.sorted(by: { $0.startedAt > $1.startedAt }) {
                ConsoleUI.info("Job ID: \(job.id)")
                ConsoleUI.info("Status: \(job.status.rawValue)")
                ConsoleUI.info("Started: \(job.startedAt.formatted())")

                if let completedAt = job.completedAt {
                    ConsoleUI.info("Completed: \(completedAt.formatted())")
                }

                if detailed {
                    ConsoleUI.info("Progress: \(job.progress.objectsProcessed)/\(job.progress.objectsTotal) objects")
                    ConsoleUI.info("Size: \(job.progress.bytesProcessed.formattedByteCount()) / \(job.progress.bytesTotal.formattedByteCount())")
                    if let duration = job.duration {
                        ConsoleUI.info("Duration: \(String(format: "%.1f", duration))s")
                    }
                    if let error = job.errorMessage {
                        ConsoleUI.error("Error: \(error)")
                    }
                }

                ConsoleUI.info("")
            }

        } catch {
            ConsoleUI.error("Failed to list backup jobs: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Get the status of a backup job.
struct GetBackupStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Get the status of a backup job"
    )

    @Argument(help: "Job ID")
    var jobId: String

    func run() async throws {
        do {
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            guard let job = try await backupManager.getJobStatus(jobId: jobId) else {
                ConsoleUI.error("Backup job not found: \(jobId)")
                throw ValidationError("Job not found")
            }

            ConsoleUI.info("Backup Job Status:")
            ConsoleUI.info("Job ID: \(job.id)")
            ConsoleUI.info("Configuration ID: \(job.configurationId)")
            ConsoleUI.info("Status: \(job.status.rawValue)")
            ConsoleUI.info("Started: \(job.startedAt.formatted())")

            if let completedAt = job.completedAt {
                ConsoleUI.info("Completed: \(completedAt.formatted())")
            }

            ConsoleUI.info("Progress: \(job.progress.objectsProcessed)/\(job.progress.objectsTotal) objects")
            ConsoleUI.info("Size: \(job.progress.bytesProcessed.formattedByteCount()) / \(job.progress.bytesTotal.formattedByteCount())")

            if let duration = job.duration {
                ConsoleUI.info("Duration: \(String(format: "%.1f", duration))s")
            }

            if let error = job.errorMessage {
                ConsoleUI.error("Error: \(error)")
            }

        } catch {
            ConsoleUI.error("Failed to get backup status: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Clean up old backups based on retention policies.
struct CleanupBackups: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Clean up old backups based on retention policies"
    )

    func run() async throws {
        do {
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }

            try await backupManager.cleanupOldBackups()

            ConsoleUI.success("Backup cleanup completed successfully")

        } catch {
            ConsoleUI.error("Failed to cleanup backups: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Initiate disaster recovery.
struct InitiateRecovery: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "initiate-recovery",
        abstract: "Initiate disaster recovery for a configuration"
    )

    @Argument(help: "Configuration ID to recover")
    var configId: String

    @Option(name: .long, help: "Target region for recovery")
    var targetRegion: String?

    @Option(name: .long, help: "Target provider for recovery")
    var targetProvider: String?

    func run() async throws {
        do {
            let backupManager = await MainActor.run { ServiceLocator.getShared().backupManager }
            let recoveryManager = await MainActor.run { ServiceLocator.getShared().disasterRecoveryManager }

            let targetProviderEnum = targetProvider.flatMap { CloudProvider(rawValue: $0.lowercased()) }

            let plan = try await recoveryManager.initiateDisasterRecovery(
                configurationId: configId,
                targetRegion: targetRegion,
                targetProvider: targetProviderEnum
            )

            ConsoleUI.success("Disaster recovery plan created")
            ConsoleUI.info("Plan ID: \(plan.id)")
            ConsoleUI.info("Estimated Duration: \(String(format: "%.1f", plan.estimatedDuration / 3600)) hours")
            ConsoleUI.info("Risk Level: \(plan.riskAssessment.overallRisk.rawValue)")

            if !plan.riskAssessment.recommendations.isEmpty {
                ConsoleUI.warning("Recommendations:")
                for rec in plan.riskAssessment.recommendations {
                    ConsoleUI.info("  - \(rec)")
                }
            }

        } catch {
            ConsoleUI.error("Failed to initiate disaster recovery: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Execute a disaster recovery plan.
struct ExecuteRecovery: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "execute-recovery",
        abstract: "Execute a disaster recovery plan"
    )

    @Argument(help: "Recovery plan ID to execute")
    var planId: String

    func run() async throws {
        do {
            // Note: This would need the plan object, which isn't stored yet
            // For now, this is a placeholder
            ConsoleUI.error("Execute recovery not yet implemented - need to store and retrieve plans")
            throw ValidationError("Not implemented")

        } catch {
            ConsoleUI.error("Failed to execute disaster recovery: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Test disaster recovery readiness.
struct TestRecovery: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-recovery",
        abstract: "Test disaster recovery readiness"
    )

    @Argument(help: "Configuration ID to test")
    var configId: String

    func run() async throws {
        do {
            let recoveryManager = await MainActor.run { ServiceLocator.getShared().disasterRecoveryManager }

            let testResult = try await recoveryManager.testRecoveryReadiness(configurationId: configId)

            ConsoleUI.info("Disaster Recovery Test Results:")
            ConsoleUI.info("Configuration ID: \(testResult.configurationId)")
            ConsoleUI.info("Status: \(testResult.status.rawValue)")
            ConsoleUI.info("Readiness Score: \(String(format: "%.1f", testResult.readinessScore))%")
            ConsoleUI.info("Backup Available: \(testResult.backupAvailability ? "Yes" : "No")")
            ConsoleUI.info("Recent Backups: \(testResult.recentBackupCount)")
            ConsoleUI.info("Backup Objects: \(testResult.backupObjectCount)")
            ConsoleUI.info("Recovery Location Accessible: \(testResult.recoveryLocationAccessible ? "Yes" : "No")")

            if let error = testResult.errorMessage {
                ConsoleUI.error("Error: \(error)")
            }
        } catch {
            ConsoleUI.error("Failed to test disaster recovery: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Validate a disaster recovery plan.
struct ValidateRecovery: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate-recovery",
        abstract: "Validate a disaster recovery plan"
    )

    @Argument(help: "Recovery plan ID to validate")
    var planId: String

    func run() async throws {
        do {
            // Note: This would need the plan object, which isn't stored yet
            ConsoleUI.error("Validate recovery not yet implemented - need to store and retrieve plans")
            throw ValidationError("Not implemented")

        } catch {
            ConsoleUI.error("Failed to validate disaster recovery plan: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Helper Functions

private func getCloudConfig(for provider: CloudProvider, region: String) async throws -> CloudConfig {
    // Get credentials from environment or keychain
    // This is a simplified version - in reality would be more sophisticated
    let accessKey = ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] ?? ""
    let secretKey = ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"] ?? ""

    return CloudConfig(
        provider: provider,
        accessKey: accessKey,
        secretKey: secretKey,
        region: region
    )
}

private extension Date {
    func formatted() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: self)
    }
}

private extension Int64 {
    func formattedByteCount() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

private extension BackupSchedule {
    var description: String {
        switch self {
        case .cron(_):
            return "Custom cron schedule"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .manual:
            return "Manual"
        }
    }
}