import Foundation
import Compression

/// Protocol for backup configuration management
public protocol BackupConfigurationService {
    // func createConfiguration(_ config: BackupConfiguration) async throws
    // func updateConfiguration(_ config: BackupConfiguration) async throws
    // func getConfiguration(id: String) async throws -> BackupConfiguration?
    // func listConfigurations() async throws -> [BackupConfiguration]
    // func deleteConfiguration(id: String) async throws
}

/// Protocol for backup job execution
public protocol BackupExecutionService {
    // func startBackup(configurationId: String) async throws -> String
    // func cancelBackup(jobId: String) async throws
    // func getJobStatus(jobId: String) async throws -> BackupJob?
    // func listJobs(for configurationId: String) async throws -> [BackupJob]
}

/// Protocol for backup data persistence
public protocol BackupStorageService: Sendable {
    // func storeConfiguration(_ config: BackupConfiguration) async throws
    // func getConfiguration(id: String) async throws -> BackupConfiguration?
    // func listConfigurations() async throws -> [BackupConfiguration]
    // func deleteConfiguration(id: String) async throws

    // func storeJob(_ job: BackupJob) async throws
    // func getJob(id: String) async throws -> BackupJob?
    // func listJobs(for configurationId: String) async throws -> [BackupJob]
    // func updateJob(_ job: BackupJob) async throws
    // func deleteJob(id: String) async throws

    // func storeManifest(_ manifest: BackupManifest) async throws
    // func getManifest(id: String) async throws -> BackupManifest?
    // func listManifests(for jobId: String) async throws -> [BackupManifest]
}

/// Default implementation of BackupConfigurationService
public class DefaultBackupConfigurationService: BackupConfigurationService {
    // private let storage: any BackupStorage
    // private let auditLogger: any AuditLogStorage

    // public init(storage: any BackupStorage, auditLogger: any AuditLogStorage) {
    //     self.storage = storage
    //     self.auditLogger = auditLogger
    // }

    // public func createConfiguration(_ config: BackupConfiguration) async throws {
    //     try await storage.storeConfiguration(config)

    //     try await auditLogger.store(entry: AuditLogEntry(
    //         eventType: .configurationChange,
    //         actor: "system",
    //         resource: "backup_configuration",
    //         action: "create",
    //         result: "success",
    //         metadata: [
    //             "config_id": config.id,
    //             "config_name": config.name,
    //             "source_provider": config.sourceConfig.provider.rawValue,
    //             "destination_provider": config.destinationConfig.provider.rawValue
    //         ],
    //         source: "backup_config_service",
    //         complianceTags: ["backup", "configuration"]
    //     ))
    // }

    // public func updateConfiguration(_ config: BackupConfiguration) async throws {
    //     // Validate configuration exists
    //     guard try await storage.getConfiguration(id: config.id) != nil else {
    //         throw BackupError.configurationNotFound(config.id)
    //     }

    //     try await storage.storeConfiguration(config)

    //     try await auditLogger.store(entry: AuditLogEntry(
    //         eventType: .configurationChange,
    //         actor: "system",
    //         resource: "backup_configuration",
    //         action: "update",
    //         result: "success",
    //         metadata: ["config_id": config.id, "config_name": config.name],
    //         source: "backup_config_service",
    //         complianceTags: ["backup", "configuration"]
    //     ))
    // }

    // public func getConfiguration(id: String) async throws -> BackupConfiguration? {
    //     try await storage.getConfiguration(id: id)
    // }

    // public func listConfigurations() async throws -> [BackupConfiguration] {
    //     try await storage.listConfigurations()
    // }

    // public func deleteConfiguration(id: String) async throws {
    //     // Check if configuration exists
    //     guard try await storage.getConfiguration(id: id) != nil else {
    //         throw BackupError.configurationNotFound(id)
    //     }

    //     // Check for active jobs
    //     let jobs = try await storage.listJobs(for: id)
    //     let activeJobs = jobs.filter { $0.status == .running || $0.status == .pending }

    //     if !activeJobs.isEmpty {
    //         throw BackupError.invalidConfiguration("Cannot delete configuration with active jobs")
    //     }

    //     try await storage.deleteConfiguration(id: id)

    //     try await auditLogger.store(entry: AuditLogEntry(
    //         eventType: .configurationChange,
    //         actor: "system",
    //         resource: "backup_configuration",
    //         action: "delete",
    //         result: "success",
    //         metadata: ["config_id": id],
    //         source: "backup_config_service",
    //         complianceTags: ["backup", "configuration"]
    //     ))
    // }
}

/// Actor to manage active backup jobs
private actor ActiveJobsManager {
    // private var activeJobs: [String: Task<Void, Error>] = [:]
    // 
    // func addJob(id: String, task: Task<Void, Error>) {
    //     activeJobs[id] = task
    // }
    // 
    // func removeJob(id: String) {
    //     activeJobs.removeValue(forKey: id)
    // }
    // 
    // func getJob(id: String) -> Task<Void, Error>? {
    //     activeJobs[id]
    // }
    // 
    // func cancelJob(id: String) {
    //     if let task = activeJobs.removeValue(forKey: id) {
    //         task.cancel()
    //     }
    // }
}

/// Default implementation of BackupExecutionService
public actor DefaultBackupExecutionService: BackupExecutionService {
    // private let storage: any BackupStorageService
    // private let auditLogger: any AuditLogStorage
    // private let activeJobsManager = ActiveJobsManager()

    // public init(storage: any BackupStorageService, auditLogger: any AuditLogStorage) {
    //     self.storage = storage
    //     self.auditLogger = auditLogger
    // }

    // public func startBackup(configurationId: String) async throws -> String {
    //     // Get configuration
    //     guard let config = try await storage.getConfiguration(id: configurationId) else {
    //         throw BackupError.configurationNotFound(configurationId)
    //     }

    //     // Check for existing active jobs
    //     let existingJobs = try await storage.listJobs(for: configurationId)
    //     let runningJobs = existingJobs.filter { $0.status == .running || $0.status == .pending }

    //     if !runningJobs.isEmpty {
    //         throw BackupError.backupInProgress(configurationId)
    //     }

    //     // Create backup job
    //     let job = BackupJob(
    //         id: UUID().uuidString,
    //         configurationId: configurationId,
    //         startedAt: Date(),
    //         status: .pending,
    //         progress: BackupProgress()
    //     )

    //     try await storage.storeJob(job)

    //     // Start backup task
    //     let task = Task {
    //         do {
    //             try await self.executeBackup(job: job, config: config)
    //         } catch {
    //             // Update job status on failure
    //             var failedJob = job
    //             failedJob.status = .failed
    //             failedJob.completedAt = Date()
    //             failedJob.errorMessage = error.localizedDescription
    //             try await self.storage.updateJob(failedJob)

    //             try await self.auditLogger.store(entry: AuditLogEntry(
    //                 eventType: .operationFailed,
    //                 actor: "system",
    //                 resource: "backup_job",
    //                 action: "backup",
    //                 result: "failed",
    //                 metadata: [
    //                     "job_id": job.id,
    //                     "config_id": configurationId,
    //                     "error": error.localizedDescription
    //                 ],
    //                 source: "backup_execution_service",
    //                 complianceTags: ["backup", "error"]
    //             ))

    //             // Remove from active jobs on failure
    //             await self.activeJobsManager.removeJob(id: job.id)
    //         }
    //     }

    //     await activeJobsManager.addJob(id: job.id, task: task)

    //     try await auditLogger.store(entry: AuditLogEntry(
    //         eventType: .operationStart,
    //         actor: "system",
    //         resource: "backup_job",
    //         action: "backup",
    //         result: "started",
    //         metadata: ["job_id": job.id, "config_id": configurationId],
    //         source: "backup_execution_service",
    //         complianceTags: ["backup"]
    //     ))

    //     return job.id
    // }

    // public func cancelBackup(jobId: String) async throws {
    //     await activeJobsManager.cancelJob(id: jobId)

    //     if var job = try await storage.getJob(id: jobId) {
    //         job.status = .cancelled
    //         job.completedAt = Date()
    //         try await storage.updateJob(job)
    //     }

    //     try await auditLogger.store(entry: AuditLogEntry(
    //         eventType: .operationComplete,
    //         actor: "system",
    //         resource: "backup_job",
    //         action: "cancel_backup",
    //         result: "cancelled",
    //         metadata: ["job_id": jobId],
    //         source: "backup_execution_service",
    //         complianceTags: ["backup"]
    //     ))
    // }
    // }

    // public func getJobStatus(jobId: String) async throws -> BackupJob? {
    //     try await storage.getJob(id: jobId)
    // }

    // public func listJobs(for configurationId: String) async throws -> [BackupJob] {
    //     try await storage.listJobs(for: configurationId)
    // }

    // // private func executeBackup(job: BackupJob, config: BackupConfiguration) async throws {
    //     let startTime = Date()

    //     // Update job status to running
    //     var updatedJob = job
    //     updatedJob.status = .running
    //     try await self.storage.updateJob(updatedJob)

    //     // Create cloud clients
    //     // let sourceClient = try CloudClientFactory.createCloudClient(
    //     //     config: config.sourceConfig,
    //     //     bucket: config.sourceBucket,
    //     //     auditLogger: self.auditLogger,
    //     //     sessionId: job.id
    //     // )

    //     // let destClient = try CloudClientFactory.createCloudClient(
    //     //     config: config.destinationConfig,
    //     //     bucket: config.destinationBucket,
    //     //     auditLogger: self.auditLogger,
    //     //     sessionId: job.id
    //     // )

    //     // List objects to backup
    //     // let objects = try await sourceClient.list(prefix: config.prefix)
    //     // updatedJob.progress.objectsTotal = objects.count
    //     // updatedJob.progress.bytesTotal = objects.reduce(0) { $0 + $1.size }
    //     // try await self.storage.updateJob(updatedJob)

    //     // Backup objects
    //     // var backedUpObjects: [BackupObject] = []
    //     // var failedCount = 0

    //     // for (index, object) in objects.enumerated() {
    //     //     do {
    //     //         // Download from source
    //     //         let data = try await sourceClient.download(key: object.key)

    //     //         // Apply compression if enabled
    //     //         let processedData = try await processDataForBackup(data, config: config)

    //     //         // Generate backup key
    //     //         let backupKey = generateBackupKey(originalKey: object.key, config: config, timestamp: startTime)

    //     //         // Upload to destination
    //     //         try await destClient.upload(key: backupKey, data: processedData)

    //     //         let backupObject = BackupObject(
    //     //             key: object.key,
    //     //             size: object.size,
    //     //             lastModified: object.lastModified,
    //     //             etag: object.etag,
    //     //             metadata: [
    //     //                 "backup_key": backupKey,
    //     //                 "compressed": config.compression.enabled.description,
    //     //                 "compression_algorithm": config.compression.algorithm.rawValue,
    //     //                 "encrypted": config.encryption.enabled.description,
    //     //                 "encryption_algorithm": config.encryption.algorithm,
    //     //                 "config_id": config.id
    //     //             ]
    //     //         )
    //     //         backedUpObjects.append(backupObject)

    //     //         // Update progress
    //     //         updatedJob.progress.objectsProcessed = index + 1
    //     //         updatedJob.progress.bytesProcessed += object.size
    //     //         try await self.storage.updateJob(updatedJob)

    //     //     } catch {
    //     //         failedCount += 1
    //     //         try await self.auditLogger.store(entry: AuditLogEntry(
    //     //             eventType: .operationFailed,
    //     //             actor: "system",
    //     //             resource: object.key,
    //     //             action: "backup_object",
    //     //             result: "failed",
    //     //             metadata: [
    //     //             "job_id": job.id,
    //     //             "object_key": object.key,
    //     //             "error": error.localizedDescription
    //     //             ],
    //     //             source: "backup_execution_service",
    //     //             complianceTags: ["backup", "error"]
    //     //         ))
    //     //     }
    //     // }

    //     // Create backup manifest
    //     // let source = BackupSource(
    //     //     provider: config.sourceConfig.provider,
    //     //     bucket: config.sourceBucket,
    //     //     prefix: config.prefix,
    //     //     region: config.sourceConfig.region
    //     // )
    //     // let statistics = BackupStatistics(
    //     //     totalObjects: backedUpObjects.count,
    //     //     totalSize: backedUpObjects.reduce(0) { $0 + $1.size },
    //     //     failedObjects: failedCount,
    //     //     startTime: job.startedAt,
    //     //     endTime: Date()
    //     // )
    //     // let manifest = BackupManifest(
    //     //     id: UUID().uuidString,
    //     //     jobId: job.id,
    //     //     source: source,
    //     //     objects: backedUpObjects,
    //     //     statistics: statistics
    //     // )

    //     // try await self.storage.storeManifest(manifest)

    //     // Update job as completed
    //     updatedJob.status = .completed
    //     updatedJob.completedAt = Date()
    //     updatedJob.progress.objectsProcessed = 0
    //     updatedJob.progress.bytesProcessed = 0

// try await self.auditLogger.store(entry: AuditLogEntry(
    //     //     eventType: .operationComplete,
    //     //     actor: "system",
    //     //     resource: "backup_job",
    //     //     action: "backup",
    //     //     result: "completed",
    //     //     metadata: [
    //     //         "job_id": job.id,
    //     //         "objects_backed_up": String(backedUpObjects.count),
    //     //         "bytes_backed_up": String(updatedJob.progress.bytesProcessed),
    //     //         "failed_count": String(failedCount)
    //     //     ],
    //     //     source: "backup_execution_service",
    //     //     complianceTags: ["backup", "success"]
    //     // ))

    //         // Remove from active jobs on success
    //     // await self.activeJobsManager.removeJob(id: job.id)
    // private func processDataForBackup(_ data: Data, config: BackupConfiguration) async throws -> Data {
    //     var processedData = data

    //     // Apply compression
    //     if config.compression.enabled {
    //         processedData = try compressData(data, algorithm: config.compression.algorithm, level: config.compression.level)
    //     }

    //     // Apply encryption
    //     if config.encryption.enabled {
    //         // TODO: Implement encryption
    //         processedData = data
    //     }

    //     return processedData
    // }

    // private func compressData(_ data: Data, algorithm: CompressionAlgorithm, level: Int) throws -> Data {
    //     switch algorithm {
    //     case .gzip:
    //         return try gzipCompress(data)
    //     case .bzip2:
    //         return try bzip2Compress(data)
    //     case .xz:
    //         return try xzCompress(data)
    //     }
    // }

    // private func gzipCompress(_ data: Data) throws -> Data {
    //     let pageSize = 4096
    //     let destinationBufferSize = pageSize

    //     // Create destination buffer
    //     let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
    //     defer { destinationBuffer.deallocate() }

    //     // Create source buffer
    //     let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    //     defer { sourceBuffer.deallocate() }
    //     data.copyBytes(to: sourceBuffer, count: data.count)

    //     // Set up compression stream
    //     var stream = compression_stream(
    //         dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 0)!,
    //         dst_size: 0,
    //         src_ptr: UnsafePointer<UInt8>(bitPattern: 0)!,
    //         src_size: 0,
    //         state: UnsafeMutableRawPointer(bitPattern: 0)
    //     )
    //     var status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
    //     guard status != COMPRESSION_STATUS_ERROR else {
    //         throw CompressionError.compressionFailed("Failed to initialize compression stream")
    //     }

    //     stream.src_ptr = UnsafePointer(sourceBuffer)
    //     stream.src_size = data.count
    //     stream.dst_ptr = destinationBuffer
    //     stream.dst_size = destinationBufferSize

    //     var compressedData = Data()

    //     repeat {
    //         status = compression_stream_process(&stream, stream.src_size == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)

    //         switch status {
    //         case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
    //             compressedData.append(destinationBuffer, count: destinationBufferSize - stream.dst_size)
    //             stream.dst_ptr = destinationBuffer
    //             stream.dst_size = destinationBufferSize
    //         case COMPRESSION_STATUS_ERROR:
    //             compression_stream_destroy(&stream)
    //             throw CompressionError.compressionFailed("Compression failed")
    //         default:
    //             break
    //         }
    //     } while status == COMPRESSION_STATUS_OK

    //     compression_stream_destroy(&stream)
    //     return compressedData
    // }

    // private func decompressData(_ data: Data, algorithm: CompressionAlgorithm) throws -> Data {
    //     switch algorithm {
    //     case .gzip:
    //         return try gzipDecompress(data)
    //     case .bzip2:
    //         return try bzip2Decompress(data)
    //     case .xz:
    //         return try xzDecompress(data)
    //     }
    // }

    // private func gzipDecompress(_ data: Data) throws -> Data {
    //     let pageSize = 4096
    //     let destinationBufferSize = pageSize

    //     // Create destination buffer
    //     let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
    //     defer { destinationBuffer.deallocate() }

    //     // Create source buffer
    //     let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    //     defer { sourceBuffer.deallocate() }
    //     data.copyBytes(to: sourceBuffer, count: data.count)

    //     // Set up decompression stream
    //     var stream = compression_stream(
    //         dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 0)!,
    //         dst_size: 0,
    //         src_ptr: UnsafePointer<UInt8>(bitPattern: 0)!,
    //         src_size: 0,
    //         state: UnsafeMutableRawPointer(bitPattern: 0)
    //     )
    //     var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
    //     guard status != COMPRESSION_STATUS_ERROR else {
    //         throw CompressionError.compressionFailed("Failed to initialize decompression stream")
    //     }

    //     stream.src_ptr = UnsafePointer(sourceBuffer)
    //     stream.src_size = data.count
    //     stream.dst_ptr = destinationBuffer
    //     stream.dst_size = destinationBufferSize

    //     var decompressedData = Data()

    //     repeat {
    //         status = compression_stream_process(&stream, stream.src_size == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)

    //         switch status {
    //         case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
    //             decompressedData.append(destinationBuffer, count: destinationBufferSize - stream.dst_size)
    //             stream.dst_ptr = destinationBuffer
    //             stream.dst_size = destinationBufferSize
    //         case COMPRESSION_STATUS_ERROR:
    //             compression_stream_destroy(&stream)
    //             throw CompressionError.compressionFailed("Decompression failed")
    //         default:
    //             break
    //         }
    //     } while status == COMPRESSION_STATUS_OK

    //     compression_stream_destroy(&stream)
    //     return decompressedData
    // }

    // private func bzip2Compress(_ data: Data) throws -> Data {
    //     return try compressWithSystemTool(data: data, tool: "bzip2", args: ["-c", "-9"])
    // }

    // private func bzip2Decompress(_ data: Data) throws -> Data {
    //     return try decompressWithSystemTool(data: data, tool: "bunzip2", args: ["-c"])
    // }

    // private func xzCompress(_ data: Data) throws -> Data {
    //     return try compressWithSystemTool(data: data, tool: "xz", args: ["-c", "-9"])
    // }

    // private func xzDecompress(_ data: Data) throws -> Data {
    //     return try decompressWithSystemTool(data: data, tool: "unxz", args: ["-c"])
    // }

    // private func compressWithSystemTool(data: Data, tool: String, args: [String]) throws -> Data {
    //     let process = Process()
    //     process.executableURL = URL(fileURLWithPath: "/usr/bin/\(tool)")
    //     process.arguments = args

    //     let inputPipe = Pipe()
    //     let outputPipe = Pipe()
    //     let errorPipe = Pipe()

    //     process.standardInput = inputPipe
    //     process.standardOutput = outputPipe
    //     process.standardError = errorPipe

    //     try process.run()

    //     // Write data to input
    //     inputPipe.fileHandleForWriting.write(data)
    //     inputPipe.fileHandleForWriting.closeFile()

    //     // Read compressed output
    //     let compressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    //     let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    //     process.waitUntilExit()

    //     if process.terminationStatus != 0 {
    //         let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
    //         throw CompressionError.compressionFailed("\(tool) failed: \(errorMessage)")
    //     }

    //     return compressedData
    // }

    // private func decompressWithSystemTool(data: Data, tool: String, args: [String]) throws -> Data {
    //     let process = Process()
    //     process.executableURL = URL(fileURLWithPath: "/usr/bin/\(tool)")
    //     process.arguments = args

    //     let inputPipe = Pipe()
    //     let outputPipe = Pipe()
    //     let errorPipe = Pipe()

    //     process.standardInput = inputPipe
    //     process.standardOutput = outputPipe
    //     process.standardError = errorPipe

    //     try process.run()

    //     // Write data to input
    //     inputPipe.fileHandleForWriting.write(data)
    //     inputPipe.fileHandleForWriting.closeFile()

    //     // Read decompressed output
    //     let decompressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    //     let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    //     process.waitUntilExit()

    //     if process.terminationStatus != 0 {
    //         let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
    //         throw CompressionError.compressionFailed("\(tool) failed: \(errorMessage)")
    //     }

    //     return decompressedData
    // }

    // private func generateBackupKey(originalKey: String, config: BackupConfiguration, timestamp: Date) -> String {
    //     let dateFormatter = DateFormatter()
    //     dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    //     let timestampStr = dateFormatter.string(from: timestamp)

    //     let prefix = config.prefix ?? "backup"
    //     return "\(prefix)/\(timestampStr)/\(originalKey)"
    // }
}


/// Default implementation of BackupStorageService
public actor DefaultBackupStorageService: BackupStorageService {
    // private let storage: any BackupStorage

    // public init(storage: any BackupStorage) {
    //     self.storage = storage
    // }

    // // Configuration methods
    // public func storeConfiguration(_ config: BackupConfiguration) async throws {
    //     try await storage.storeConfiguration(config)
    // }

    // public func getConfiguration(id: String) async throws -> BackupConfiguration? {
    //     try await storage.getConfiguration(id: id)
    // }

    // public func listConfigurations() async throws -> [BackupConfiguration] {
    //     try await storage.listConfigurations()
    // }

    // public func deleteConfiguration(id: String) async throws {
    //     try await storage.deleteConfiguration(id: id)
    // }

    // // Job methods
    // public func storeJob(_ job: BackupJob) async throws {
    //     try await storage.storeJob(job)
    // }

    // public func getJob(id: String) async throws -> BackupJob? {
    //     try await storage.getJob(id: id)
    // }

    // public func listJobs(for configurationId: String) async throws -> [BackupJob] {
    //     try await storage.listJobs(for: configurationId)
    // }

    // public func updateJob(_ job: BackupJob) async throws {
    //     try await storage.updateJob(job)
    // }

    // public func deleteJob(id: String) async throws {
    //     try await storage.deleteJob(id: id)
    // }

    // // Manifest methods
    // public func storeManifest(_ manifest: BackupManifest) async throws {
    //     try await storage.storeManifest(manifest)
    // }

    // public func getManifest(id: String) async throws -> BackupManifest? {
    //     try await storage.getManifest(id: id)
    // }

    // public func listManifests(for jobId: String) async throws -> [BackupManifest] {
    //     try await storage.listManifests(for: jobId)
    // }
}