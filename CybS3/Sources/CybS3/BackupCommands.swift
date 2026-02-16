import Foundation
import ArgumentParser

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
        let console = ConsoleUI()

        do {
            // Parse providers
            guard let sourceProviderEnum = CloudProvider(rawValue: sourceProvider.lowercased()) else {
                console.error("Invalid source provider: \(sourceProvider)")
                throw ValidationError("Invalid source provider")
            }

            guard let destProviderEnum = CloudProvider(rawValue: destProvider.lowercased()) else {
                console.error("Invalid destination provider: \(destProvider)")
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
                backupSchedule = .daily
            case "daily":
                backupSchedule = .daily
            case "weekly":
                backupSchedule = .weekly
            case "monthly":
                backupSchedule = .monthly
            default:
                console.error("Invalid schedule: \(schedule)")
                throw ValidationError("Invalid schedule")
            }

            // Create retention policy
            let retentionPolicy = BackupRetentionPolicy(
                retentionPeriod: TimeInterval(retentionDays * 24 * 3600),
                maxBackups: maxBackups,
                complianceRetention: []
            )

            // Create compression settings
            let compressionSettings = BackupCompressionSettings(
                enabled: compression,
                algorithm: .gzip
            )

            // Create encryption settings
            let encryptionSettings = BackupEncryptionSettings(
                enabled: encryption,
                algorithm: .aes256
            )

            // Create backup configuration
            let config = BackupConfiguration(
                name: name,
                sourceConfig: sourceConfig,
                sourceBucket: sourceBucket,
                destinationConfig: destConfig,
                destinationBucket: destBucket,
                prefix: prefix,
                schedule: backupSchedule,
                retentionPolicy: retentionPolicy,
                compression: compressionSettings,
                encryption: encryptionSettings,
                isEnabled: true,
                tags: [:]
            )

            // Get backup manager from dependency container
            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            try await backupManager.createConfiguration(config)

            console.success("Backup configuration '\(name)' created successfully")
            console.info("Configuration ID: \(config.id)")

        } catch {
            console.error("Failed to create backup configuration: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            let configs = try await backupManager.listConfigurations()

            if configs.isEmpty {
                console.info("No backup configurations found")
                return
            }

            console.info("Backup Configurations:")
            console.info(String(repeating: "=", count: 80))

            for config in configs {
                console.info("Name: \(config.name)")
                console.info("ID: \(config.id)")
                console.info("Source: \(config.sourceConfig.provider.rawValue)/\(config.sourceBucket)")
                console.info("Destination: \(config.destinationConfig.provider.rawValue)/\(config.destinationBucket)")
                console.info("Schedule: \(config.schedule.description)")
                console.info("Enabled: \(config.isEnabled ? "Yes" : "No")")

                if detailed {
                    console.info("Retention: \(config.retentionPolicy.retentionPeriod / (24*3600)) days, max \(config.retentionPolicy.maxBackups) backups")
                    console.info("Compression: \(config.compression.enabled ? "Enabled" : "Disabled")")
                    console.info("Encryption: \(config.encryption.enabled ? "Enabled" : "Disabled")")
                    if let prefix = config.prefix {
                        console.info("Prefix: \(prefix)")
                    }
                }

                console.info("")
            }

        } catch {
            console.error("Failed to list backup configurations: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            guard var config = try await backupManager.listConfigurations()
                .first(where: { $0.id == configId }) else {
                console.error("Backup configuration not found: \(configId)")
                throw ValidationError("Configuration not found")
            }

            // Apply updates
            if let name = name {
                config.name = name
            }

            if let enabled = enabled {
                config.isEnabled = enabled
            }

            if let retentionDays = retentionDays {
                config.retentionPolicy.retentionPeriod = TimeInterval(retentionDays * 24 * 3600)
            }

            if let maxBackups = maxBackups {
                config.retentionPolicy.maxBackups = maxBackups
            }

            try await backupManager.updateConfiguration(config)

            console.success("Backup configuration updated successfully")

        } catch {
            console.error("Failed to update backup configuration: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            if !force {
                console.warning("This will delete the backup configuration and all associated jobs.")
                console.info("Use --force to skip this confirmation.")
                return
            }

            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            try await backupManager.deleteConfiguration(configId)

            console.success("Backup configuration deleted successfully")

        } catch {
            console.error("Failed to delete backup configuration: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            let jobId = try await backupManager.startBackup(configurationId: configId)

            console.success("Backup job started successfully")
            console.info("Job ID: \(jobId)")

        } catch {
            console.error("Failed to start backup: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            try await backupManager.cancelBackup(jobId: jobId)

            console.success("Backup job cancelled successfully")

        } catch {
            console.error("Failed to cancel backup: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            let jobs = try await backupManager.listJobs(for: configId)

            if jobs.isEmpty {
                console.info("No backup jobs found for configuration \(configId)")
                return
            }

            console.info("Backup Jobs for Configuration \(configId):")
            console.info(String(repeating: "=", count: 80))

            for job in jobs.sorted(by: { $0.createdAt > $1.createdAt }) {
                console.info("Job ID: \(job.id)")
                console.info("Status: \(job.status.rawValue)")
                console.info("Created: \(job.createdAt.formatted())")

                if let completedAt = job.completedAt {
                    console.info("Completed: \(completedAt.formatted())")
                }

                if detailed {
                    console.info("Progress: \(job.progress.objectsProcessed)/\(job.progress.objectsTotal) objects")
                    console.info("Size: \(job.progress.bytesProcessed.formattedByteCount()) / \(job.progress.bytesTotal.formattedByteCount())")
                    if let duration = job.duration {
                        console.info("Duration: \(String(format: "%.1f", duration))s")
                    }
                    if let error = job.errorMessage {
                        console.error("Error: \(error)")
                    }
                }

                console.info("")
            }

        } catch {
            console.error("Failed to list backup jobs: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            guard let job = try await backupManager.getJobStatus(jobId: jobId) else {
                console.error("Backup job not found: \(jobId)")
                throw ValidationError("Job not found")
            }

            console.info("Backup Job Status:")
            console.info("Job ID: \(job.id)")
            console.info("Configuration ID: \(job.configurationId)")
            console.info("Status: \(job.status.rawValue)")
            console.info("Created: \(job.createdAt.formatted())")

            if let completedAt = job.completedAt {
                console.info("Completed: \(completedAt.formatted())")
            }

            console.info("Progress: \(job.progress.objectsProcessed)/\(job.progress.objectsTotal) objects")
            console.info("Size: \(job.progress.bytesProcessed.formattedByteCount()) / \(job.progress.bytesTotal.formattedByteCount())")

            if let duration = job.duration {
                console.info("Duration: \(String(format: "%.1f", duration))s")
            }

            if let error = job.errorMessage {
                console.error("Error: \(error)")
            }

        } catch {
            console.error("Failed to get backup status: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let backupManager = try container.resolve(BackupManager.self)

            try await backupManager.cleanupOldBackups()

            console.success("Backup cleanup completed successfully")

        } catch {
            console.error("Failed to cleanup backups: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let recoveryManager = try container.resolve(DisasterRecoveryManager.self)

            let targetProviderEnum = targetProvider.flatMap { CloudProvider(rawValue: $0.lowercased()) }

            let plan = try await recoveryManager.initiateDisasterRecovery(
                configurationId: configId,
                targetRegion: targetRegion,
                targetProvider: targetProviderEnum
            )

            console.success("Disaster recovery plan created")
            console.info("Plan ID: \(plan.id)")
            console.info("Estimated Duration: \(String(format: "%.1f", plan.estimatedDuration / 3600)) hours")
            console.info("Risk Level: \(plan.riskAssessment.overallRisk.rawValue)")

            if !plan.riskAssessment.recommendations.isEmpty {
                console.warning("Recommendations:")
                for rec in plan.riskAssessment.recommendations {
                    console.info("  - \(rec)")
                }
            }

        } catch {
            console.error("Failed to initiate disaster recovery: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            // Note: This would need the plan object, which isn't stored yet
            // For now, this is a placeholder
            console.error("Execute recovery not yet implemented - need to store and retrieve plans")
            throw ValidationError("Not implemented")

        } catch {
            console.error("Failed to execute disaster recovery: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            let container = DependencyContainer.shared
            let recoveryManager = try container.resolve(DisasterRecoveryManager.self)

            let testResult = try await recoveryManager.testRecoveryReadiness(configurationId: configId)

            console.info("Disaster Recovery Test Results:")
            console.info("Configuration ID: \(testResult.configurationId)")
            console.info("Status: \(testResult.status.rawValue)")
            console.info("Readiness Score: \(String(format: "%.1f", testResult.readinessScore))%")
            console.info("Backup Available: \(testResult.backupAvailability ? "Yes" : "No")")
            console.info("Recent Backups: \(testResult.recentBackupCount)")
            console.info("Backup Objects: \(testResult.backupObjectCount)")
            console.info("Recovery Location Accessible: \(testResult.recoveryLocationAccessible ? "Yes" : "No")")

            if let error = testResult.errorMessage {
                console.error("Error: \(error)")
            }

        } catch {
            console.error("Failed to test disaster recovery: \(error.localizedDescription)")
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
        let console = ConsoleUI()

        do {
            // Note: This would need the plan object, which isn't stored yet
            console.error("Validate recovery not yet implemented - need to store and retrieve plans")
            throw ValidationError("Not implemented")

        } catch {
            console.error("Failed to validate disaster recovery plan: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Helper Functions

private func getCloudConfig(for provider: CloudProvider, region: String) async throws -> CloudConfiguration {
    // Get credentials from environment or keychain
    // This is a simplified version - in reality would be more sophisticated
    let accessKeyId = ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] ?? ""
    let secretAccessKey = ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"] ?? ""

    return CloudConfiguration(
        provider: provider,
        region: region,
        accessKeyId: accessKeyId,
        secretAccessKey: secretAccessKey,
        sessionToken: nil,
        endpoint: nil
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
        }
    }
}