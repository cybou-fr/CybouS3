import Foundation
import Compression

/// Disaster recovery manager for handling failover and restoration operations.
public actor DisasterRecoveryManager {
    private let backupManager: BackupManager
    private let auditLogger: any AuditLogStorage
    private let cloudClientFactory: CloudClientFactory

    public init(backupManager: BackupManager, auditLogger: any AuditLogStorage, cloudClientFactory: CloudClientFactory) {
        self.backupManager = backupManager
        self.auditLogger = auditLogger
        self.cloudClientFactory = cloudClientFactory
    }

    /// Initiates disaster recovery for a failed primary system.
    public func initiateDisasterRecovery(
        configurationId: String,
        targetRegion: String? = nil,
        targetProvider: CloudProvider? = nil
    ) async throws -> DisasterRecoveryPlan {
        guard let config = try await backupManager.listConfigurations()
            .first(where: { $0.id == configurationId }) else {
            throw DisasterRecoveryError.configurationNotFound(configurationId)
        }

        // Find the most recent successful backup
        let jobs = try await backupManager.listJobs(for: configurationId)
        guard let latestBackup = jobs
            .filter({ $0.status == .completed })
            .sorted(by: { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) })
            .first else {
            throw DisasterRecoveryError.noValidBackup(configurationId)
        }

        // Create recovery plan
        let recoveryConfig = createRecoveryConfiguration(
            originalConfig: config,
            targetRegion: targetRegion,
            targetProvider: targetProvider
        )

        let plan = DisasterRecoveryPlan(
            id: UUID().uuidString,
            originalConfigurationId: configurationId,
            backupJobId: latestBackup.id,
            recoveryConfiguration: recoveryConfig,
            estimatedDuration: estimateRecoveryDuration(config),
            riskAssessment: assessRecoveryRisks(config, recoveryConfig),
            createdAt: Date()
        )

        try await auditLogger.store(entry: AuditLogEntry(
            eventType: .operationStart,
            actor: "system",
            resource: "disaster_recovery",
            action: "initiate_recovery",
            result: "plan_created",
            metadata: [
                "plan_id": plan.id,
                "config_id": configurationId,
                "backup_job_id": latestBackup.id,
                "target_region": targetRegion ?? "same",
                "target_provider": targetProvider?.rawValue ?? "same"
            ],
            source: "disaster_recovery_manager",
            complianceTags: ["disaster_recovery", "failover"]
        ))

        return plan
    }

    /// Executes a disaster recovery plan.
    public func executeRecoveryPlan(_ plan: DisasterRecoveryPlan) async throws -> DisasterRecoveryResult {
        var result = DisasterRecoveryResult(planId: plan.id, startedAt: Date())

        do {
            // Create recovery client
            let recoveryClient = try CloudClientFactory.createCloudClient(
                config: plan.recoveryConfiguration,
                bucket: plan.recoveryConfiguration.region, // Use region as bucket for recovery
                auditLogger: auditLogger,
                sessionId: plan.id
            )

            // Get backup manifest
            guard let manifest = try await getBackupManifest(for: plan.backupJobId) else {
                throw DisasterRecoveryError.manifestNotFound(plan.backupJobId)
            }

            result.totalObjects = manifest.objects.count
            result.totalSize = manifest.statistics.totalSize

            // Restore objects
            var restoredCount = 0
            var failedCount = 0

            for backupObject in manifest.objects {
                do {
                    // Download from backup location
                    let backupKey = backupObject.metadata["backup_key"] ?? backupObject.key
                    let data = try await recoveryClient.download(key: backupKey)

                    // Process data (decompress/decrypt if needed)
                    let processedData = try await processDataForRecovery(data, metadata: backupObject.metadata)

                    // Upload to recovery location
                    try await recoveryClient.upload(key: backupObject.key, data: processedData)

                    restoredCount += 1
                    result.restoredObjects = restoredCount
                    result.restoredSize += backupObject.size

                } catch {
                    failedCount += 1
                    result.failedObjects.append(DisasterRecoveryFailure(
                        key: backupObject.key,
                        error: error.localizedDescription
                    ))

                    try await auditLogger.store(entry: AuditLogEntry(
                        eventType: .operationFailed,
                        actor: "system",
                        resource: backupObject.key,
                        action: "restore_object",
                        result: "failed",
                        metadata: [
                            "plan_id": plan.id,
                            "error": error.localizedDescription
                        ],
                        source: "disaster_recovery_manager",
                        complianceTags: ["disaster_recovery", "error"]
                    ))
                }
            }

            result.completedAt = Date()
            result.status = .completed
            result.duration = result.completedAt!.timeIntervalSince(result.startedAt)

            try await auditLogger.store(entry: AuditLogEntry(
                eventType: .operationComplete,
                actor: "system",
                resource: "disaster_recovery",
                action: "execute_recovery",
                result: "completed",
                metadata: [
                    "plan_id": plan.id,
                    "objects_restored": "\(restoredCount)",
                    "objects_failed": "\(failedCount)",
                    "total_size": "\(result.restoredSize)",
                    "duration": "\(result.duration ?? 0)"
                ],
                source: "disaster_recovery_manager",
                complianceTags: ["disaster_recovery", "success"]
            ))

        } catch {
            result.completedAt = Date()
            result.status = .failed
            result.errorMessage = error.localizedDescription
            result.duration = result.completedAt!.timeIntervalSince(result.startedAt)

            try await auditLogger.store(entry: AuditLogEntry(
                eventType: .operationFailed,
                actor: "system",
                resource: "disaster_recovery",
                action: "execute_recovery",
                result: "failed",
                metadata: [
                    "plan_id": plan.id,
                    "error": error.localizedDescription
                ],
                source: "disaster_recovery_manager",
                complianceTags: ["disaster_recovery", "error"]
            ))
        }

        return result
    }

    /// Tests disaster recovery readiness by performing a dry run.
    public func testRecoveryReadiness(configurationId: String) async throws -> DisasterRecoveryTestResult {
        guard let config = try await backupManager.listConfigurations()
            .first(where: { $0.id == configurationId }) else {
            throw DisasterRecoveryError.configurationNotFound(configurationId)
        }

        var testResult = DisasterRecoveryTestResult(configurationId: configurationId, startedAt: Date())

        do {
            // Check backup availability
            let jobs = try await backupManager.listJobs(for: configurationId)
            let recentBackups = jobs.filter { $0.status == .completed }
                .filter { $0.completedAt ?? Date.distantPast > Date().addingTimeInterval(-7*24*3600) } // Last 7 days

            testResult.backupAvailability = recentBackups.count > 0
            testResult.recentBackupCount = recentBackups.count

            // Test connectivity to backup destination
            let destClient = try CloudClientFactory.createCloudClient(
                config: config.destinationConfig,
                bucket: config.destinationBucket,
                auditLogger: auditLogger,
                sessionId: UUID().uuidString
            )

            // Try to list backup objects
            let backupObjects = try await destClient.list(prefix: config.prefix ?? "backup")
            testResult.backupObjectCount = backupObjects.count

            // Test recovery location accessibility
            let recoveryConfig = createRecoveryConfiguration(originalConfig: config)
            let recoveryClient = try CloudClientFactory.createCloudClient(
                config: recoveryConfig,
                bucket: recoveryConfig.region,
                auditLogger: auditLogger,
                sessionId: UUID().uuidString
            )

            // Try a simple operation
            _ = try await recoveryClient.list(prefix: "")

            testResult.recoveryLocationAccessible = true
            testResult.completedAt = Date()
            testResult.status = .passed

            // Calculate readiness score
            testResult.readinessScore = calculateReadinessScore(testResult)

            try await auditLogger.store(entry: AuditLogEntry(
                eventType: .complianceCheck,
                actor: "system",
                resource: "disaster_recovery",
                action: "test_readiness",
                result: "passed",
                metadata: [
                    "config_id": configurationId,
                    "readiness_score": "\(testResult.readinessScore)",
                    "backup_count": "\(testResult.recentBackupCount)",
                    "backup_objects": "\(testResult.backupObjectCount)"
                ],
                source: "disaster_recovery_manager",
                complianceTags: ["disaster_recovery", "test"]
            ))

        } catch {
            testResult.completedAt = Date()
            testResult.status = .failed
            testResult.errorMessage = error.localizedDescription
            testResult.readinessScore = 0

            try await auditLogger.store(entry: AuditLogEntry(
                eventType: .operationFailed,
                actor: "system",
                resource: "disaster_recovery",
                action: "test_readiness",
                result: "failed",
                metadata: [
                    "config_id": configurationId,
                    "error": error.localizedDescription
                ],
                source: "disaster_recovery_manager",
                complianceTags: ["disaster_recovery", "test", "error"]
            ))
        }

        return testResult
    }

    /// Validates a disaster recovery plan without executing it.
    public func validateRecoveryPlan(_ plan: DisasterRecoveryPlan) async throws -> [DisasterRecoveryValidationIssue] {
        var issues: [DisasterRecoveryValidationIssue] = []

        // Check backup manifest exists
        if try await getBackupManifest(for: plan.backupJobId) == nil {
            issues.append(DisasterRecoveryValidationIssue(
                severity: .critical,
                category: .backupIntegrity,
                message: "Backup manifest not found for job \(plan.backupJobId)",
                recommendation: "Ensure backup completed successfully and manifest was created"
            ))
        }

        // Check recovery configuration
        do {
            let _ = try CloudClientFactory.createCloudClient(
                config: plan.recoveryConfiguration,
                bucket: plan.recoveryConfiguration.region,
                auditLogger: auditLogger,
                sessionId: UUID().uuidString
            )
        } catch {
            issues.append(DisasterRecoveryValidationIssue(
                severity: .critical,
                category: .configuration,
                message: "Recovery configuration is invalid: \(error.localizedDescription)",
                recommendation: "Verify recovery provider credentials and configuration"
            ))
        }

        // Check estimated duration is reasonable
        if plan.estimatedDuration > 24 * 3600 { // More than 24 hours
            issues.append(DisasterRecoveryValidationIssue(
                severity: .warning,
                category: .performance,
                message: "Estimated recovery time is very long: \(plan.estimatedDuration / 3600) hours",
                recommendation: "Consider optimizing backup size or using faster storage tiers"
            ))
        }

        // Check risk assessment
        if plan.riskAssessment.overallRisk == .high {
            issues.append(DisasterRecoveryValidationIssue(
                severity: .warning,
                category: .risk,
                message: "High risk assessment for recovery plan",
                recommendation: plan.riskAssessment.recommendations.joined(separator: "; ")
            ))
        }

        try await auditLogger.store(entry: AuditLogEntry(
            eventType: .complianceCheck,
            actor: "system",
            resource: "disaster_recovery",
            action: "validate_plan",
            result: issues.isEmpty ? "passed" : "issues_found",
            metadata: [
                "plan_id": plan.id,
                "issues_count": "\(issues.count)",
                "critical_issues": "\(issues.filter { $0.severity == .critical }.count)"
            ],
            source: "disaster_recovery_manager",
            complianceTags: ["disaster_recovery", "validation"]
        ))

        return issues
    }

    // MARK: - Private Methods

    private func getBackupManifest(for jobId: String) async throws -> BackupManifest? {
        // This would need to be implemented in the backup storage
        // For now, return nil as a placeholder
        return nil
    }

    private func createRecoveryConfiguration(
        originalConfig: BackupConfiguration,
        targetRegion: String? = nil,
        targetProvider: CloudProvider? = nil
    ) -> CloudConfig {
        // Create a recovery configuration based on the original
        // In a real implementation, this would use predefined failover configurations
        CloudConfig(
            provider: targetProvider ?? originalConfig.destinationConfig.provider,
            accessKey: originalConfig.destinationConfig.accessKey,
            secretKey: originalConfig.destinationConfig.secretKey,
            region: targetRegion ?? originalConfig.destinationConfig.region,
            customEndpoint: originalConfig.destinationConfig.customEndpoint
        )
    }

    private func estimateRecoveryDuration(_ config: BackupConfiguration) -> TimeInterval {
        // Simple estimation based on configuration
        // In a real implementation, this would be more sophisticated
        let baseTimePerGB = 300.0 // 5 minutes per GB
        let estimatedSizeGB = 10.0 // Placeholder - would calculate from backup history
        return baseTimePerGB * estimatedSizeGB
    }

    private func assessRecoveryRisks(_ original: BackupConfiguration, _ recovery: CloudConfig) -> DisasterRecoveryRiskAssessment {
        var risks: [DisasterRecoveryRisk] = []
        var recommendations: [String] = []

        // Check if recovery provider is different from primary
        if recovery.provider != original.sourceConfig.provider {
            risks.append(.crossProviderComplexity)
            recommendations.append("Test cross-provider recovery thoroughly")
        }

        // Check if recovery region is different
        if recovery.region != original.sourceConfig.region {
            risks.append(.regionalFailover)
            recommendations.append("Verify data transfer compliance and costs")
        }

        // Determine overall risk level
        let overallRisk: DisasterRecoveryRiskLevel
        if risks.contains(.crossProviderComplexity) {
            overallRisk = .high
        } else if risks.contains(.regionalFailover) {
            overallRisk = .medium
        } else {
            overallRisk = .low
        }

        return DisasterRecoveryRiskAssessment(
            overallRisk: overallRisk,
            specificRisks: risks,
            recommendations: recommendations
        )
    }

    private func processDataForRecovery(_ data: Data, metadata: [String: String]) async throws -> Data {
        var processedData = data

        // Apply decryption if needed
        if metadata["encrypted"] == "true" {
            processedData = try decryptDataForRecovery(processedData)
        }

        // Apply decompression if needed
        if metadata["compressed"] == "true" {
            let algorithm = CompressionAlgorithm(rawValue: metadata["compression_algorithm"] ?? "gzip") ?? .gzip
            processedData = try decompressData(processedData, algorithm: algorithm)
        }
        }

        return processedData
    }

    private func decryptDataForRecovery(_ data: Data) throws -> Data {
        // Placeholder - would implement proper decryption
        return data
    }

    private func decompressData(_ data: Data, algorithm: CompressionAlgorithm) throws -> Data {
        switch algorithm {
        case .gzip:
            return try gzipDecompress(data)
        case .bzip2:
            // TODO: Implement bzip2 decompression (requires external library)
            return data // Return uncompressed for now
        case .xz:
            // TODO: Implement xz decompression (requires external library)
            return data // Return uncompressed for now
        }
    }

    private func gzipDecompress(_ data: Data) throws -> Data {
        let pageSize = 4096
        let destinationBufferSize = pageSize

        // Create destination buffer
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        // Create source buffer
        let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { sourceBuffer.deallocate() }
        data.copyBytes(to: sourceBuffer, count: data.count)

        // Set up decompression stream
        var stream = compression_stream()
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_GZIP)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw NSError(domain: "DisasterRecoveryManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize decompression stream"])
        }

        stream.src_ptr = sourceBuffer
        stream.src_size = data.count
        stream.dst_ptr = destinationBuffer
        stream.dst_size = destinationBufferSize

        var decompressedData = Data()

        repeat {
            status = compression_stream_process(&stream, stream.src_size == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)

            switch status {
            case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                decompressedData.append(destinationBuffer, count: destinationBufferSize - stream.dst_size)
                stream.dst_ptr = destinationBuffer
                stream.dst_size = destinationBufferSize
            case COMPRESSION_STATUS_ERROR:
                compression_stream_destroy(&stream)
                throw NSError(domain: "DisasterRecoveryManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
            default:
                break
            }
        } while status == COMPRESSION_STATUS_OK

        compression_stream_destroy(&stream)
        return decompressedData
    }

    private func calculateReadinessScore(_ testResult: DisasterRecoveryTestResult) -> Double {
        var score = 0.0

        if testResult.backupAvailability { score += 40.0 }
        if testResult.recoveryLocationAccessible { score += 30.0 }
        if testResult.recentBackupCount > 0 { score += 20.0 }
        if testResult.backupObjectCount > 0 { score += 10.0 }

        return min(score, 100.0)
    }
}

/// Disaster recovery plan structure.
public struct DisasterRecoveryPlan: Codable, Sendable {
    public let id: String
    public let originalConfigurationId: String
    public let backupJobId: String
    public let recoveryConfiguration: CloudConfig
    public let estimatedDuration: TimeInterval
    public let riskAssessment: DisasterRecoveryRiskAssessment
    public let createdAt: Date
}

/// Result of executing a disaster recovery plan.
public struct DisasterRecoveryResult: Codable, Sendable {
    public let planId: String
    public let startedAt: Date
    public var completedAt: Date?
    public var status: DisasterRecoveryStatus = .inProgress
    public var totalObjects: Int = 0
    public var totalSize: Int64 = 0
    public var restoredObjects: Int = 0
    public var restoredSize: Int64 = 0
    public var failedObjects: [DisasterRecoveryFailure] = []
    public var duration: TimeInterval?
    public var errorMessage: String?
}

/// Failure details for disaster recovery.
public struct DisasterRecoveryFailure: Codable, Sendable {
    public let key: String
    public let error: String
}

/// Status of disaster recovery operation.
public enum DisasterRecoveryStatus: String, Codable, Sendable {
    case inProgress
    case completed
    case failed
    case cancelled
}

/// Result of disaster recovery readiness test.
public struct DisasterRecoveryTestResult: Codable, Sendable {
    public let configurationId: String
    public let startedAt: Date
    public var completedAt: Date?
    public var status: DisasterRecoveryTestStatus = .inProgress
    public var backupAvailability: Bool = false
    public var recentBackupCount: Int = 0
    public var backupObjectCount: Int = 0
    public var recoveryLocationAccessible: Bool = false
    public var readinessScore: Double = 0
    public var errorMessage: String?
}

/// Status of disaster recovery test.
public enum DisasterRecoveryTestStatus: String, Codable, Sendable {
    case inProgress
    case passed
    case failed
}

/// Risk assessment for disaster recovery.
public struct DisasterRecoveryRiskAssessment: Codable, Sendable {
    public let overallRisk: DisasterRecoveryRiskLevel
    public let specificRisks: [DisasterRecoveryRisk]
    public let recommendations: [String]
}

/// Risk level for disaster recovery.
public enum DisasterRecoveryRiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

/// Specific disaster recovery risks.
public enum DisasterRecoveryRisk: String, Codable, Sendable {
    case crossProviderComplexity
    case regionalFailover
    case dataTransferCosts
    case complianceBoundaryCrossing
}

/// Validation issue for disaster recovery plan.
public struct DisasterRecoveryValidationIssue: Codable, Sendable {
    public let severity: DisasterRecoveryValidationSeverity
    public let category: DisasterRecoveryValidationCategory
    public let message: String
    public let recommendation: String
}

/// Severity of validation issue.
public enum DisasterRecoveryValidationSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

/// Category of validation issue.
public enum DisasterRecoveryValidationCategory: String, Codable, Sendable {
    case backupIntegrity
    case configuration
    case performance
    case risk
    case compliance
}

/// Disaster recovery related errors.
public enum DisasterRecoveryError: Error, LocalizedError {
    case configurationNotFound(String)
    case noValidBackup(String)
    case manifestNotFound(String)
    case recoveryInProgress(String)
    case invalidPlan(String)

    public var errorDescription: String? {
        switch self {
        case .configurationNotFound(let id):
            return "Disaster recovery configuration not found: \(id)"
        case .noValidBackup(let id):
            return "No valid backup found for configuration: \(id)"
        case .manifestNotFound(let id):
            return "Backup manifest not found for job: \(id)"
        case .recoveryInProgress(let id):
            return "Disaster recovery already in progress: \(id)"
        case .invalidPlan(let reason):
            return "Invalid disaster recovery plan: \(reason)"
        }
    }
}