import Foundation

/// Mock services for unit testing handlers
/// These mocks implement the service protocols with controllable behavior for testing

// MARK: - Authentication Service Mock

public class MockAuthenticationService: AuthenticationServiceProtocol {
    public var loginResult: Result<LoginOutput, Error> = .success(LoginOutput(success: true, message: "Login successful"))
    public var logoutResult: Result<LogoutOutput, Error> = .success(LogoutOutput(success: true, message: "Logout successful"))

    public init() {}

    public func login(mnemonic: String) async throws -> LoginOutput {
        try loginResult.get()
    }

    public func logout() async throws -> LogoutOutput {
        try logoutResult.get()
    }
}

// MARK: - Configuration Service Mock

public class MockConfigurationService: ConfigurationServiceProtocol {
    public var configResult: Result<ConfigOutput, Error> = .success(ConfigOutput(
        success: true,
        message: "Configuration retrieved",
        config: Configuration(
            dataKey: Data(repeating: 0x01, count: 32),
            vaults: [VaultConfig(
                name: "test-vault",
                endpoint: "https://test.endpoint.com",
                accessKey: "test-key",
                secretKey: "test-secret",
                region: "us-east-1"
            )],
            settings: AppSettings()
        )
    ))

    public var updateResult: Result<ConfigOutput, Error> = .success(ConfigOutput(
        success: true,
        message: "Configuration updated",
        config: nil
    ))

    public var resetResult: Result<Void, Error> = .success(())
    public var createVaultResult: Result<Void, Error> = .success(())
    public var setActiveVaultResult: Result<Void, Error> = .success(())

    public init() {}

    public func getConfig(mnemonic: String) async throws -> Configuration {
        // Mock implementation - return a basic configuration
        return Configuration(
            dataKey: Data(repeating: 0x01, count: 32), // Mock 32-byte key
            vaults: [VaultConfig(
                name: "test-vault",
                endpoint: "https://test.endpoint.com",
                accessKey: "test-key",
                secretKey: "test-secret",
                region: "us-east-1"
            )],
            settings: AppSettings()
        )
    }

    public func updateConfig(mnemonic: String, updates: ConfigInput) async throws -> ConfigOutput {
        try updateResult.get()
    }

    public func resetConfig() async throws {
        try resetResult.get()
    }

    public func createVault(mnemonic: String, name: String) async throws {
        try createVaultResult.get()
    }

    public func setActiveVault(mnemonic: String, name: String) async throws {
        try setActiveVaultResult.get()
    }

    // Legacy methods for backward compatibility
    public func getConfiguration(list: Bool, reset: Bool, accessKey: String?, secretKey: String?) async throws -> ConfigOutput {
        try configResult.get()
    }

    public func setConfiguration(mnemonic: String, accessKey: String?, secretKey: String?) async throws -> ConfigOutput {
        try configResult.get()
    }
}

// MARK: - File Operations Service Mock

public class MockFileOperationsService: FileOperationsServiceProtocol {
    public var listResult: Result<ListFilesOutput, Error> = .success(ListFilesOutput(
        objects: [S3Object(key: "test-file.txt", size: 1024, lastModified: Date(), isDirectory: false, etag: "test-etag")],
        success: true,
        message: "Files listed successfully"
    ))

    public var getResult: Result<GetFileOutput, Error> = .success(GetFileOutput(
        success: true,
        message: "File retrieved successfully",
        bytesDownloaded: 1024,
        fileSize: 1024
    ))

    public var putResult: Result<PutFileOutput, Error> = .success(PutFileOutput(
        success: true,
        message: "File uploaded successfully",
        bytesUploaded: 1024,
        encryptedSize: 1040
    ))

    public var deleteResult: Result<DeleteFileOutput, Error> = .success(DeleteFileOutput(
        success: true,
        message: "File deleted successfully"
    ))

    public var copyResult: Result<CopyFileOutput, Error> = .success(CopyFileOutput(
        success: true,
        message: "File copied successfully"
    ))

    public init() {}

    public func listFiles(input: ListFilesInput) async throws -> ListFilesOutput {
        try listResult.get()
    }

    public func getFile(input: GetFileInput) async throws -> GetFileOutput {
        try getResult.get()
    }

    public func putFile(input: PutFileInput) async throws -> PutFileOutput {
        try putResult.get()
    }

    public func deleteFile(input: DeleteFileInput) async throws -> DeleteFileOutput {
        try deleteResult.get()
    }

    public func copyFile(input: CopyFileInput) async throws -> CopyFileOutput {
        try copyResult.get()
    }
}

// MARK: - Bucket Operations Service Mock

public class MockBucketOperationsService: BucketOperationsServiceProtocol {
    public var createBucketResult: Result<Void, Error> = .success(())
    public var deleteBucketResult: Result<Void, Error> = .success(())
    public var listBucketsResult: Result<[String], Error> = .success(["test-bucket1", "test-bucket2"])

    public init() {}

    public func createBucket(name: String) async throws {
        try createBucketResult.get()
    }

    public func deleteBucket(name: String) async throws {
        try deleteBucketResult.get()
    }

    public func listBuckets() async throws -> [String] {
        try listBucketsResult.get()
    }
}

// MARK: - Server Process Service Mock

public class MockServerProcessService: ServerProcessServiceProtocol {
    public var startResult: Result<ServerStartResult, Error> = .success(ServerStartResult(
        port: 8080,
        hostname: "localhost",
        pid: 12345,
        background: true
    ))

    public var stopResult: Result<ServerStopResult, Error> = .success(ServerStopResult(
        port: 8080,
        pid: 12345
    ))

    public var statusResult: Result<ServerStatusResult, Error> = .success(ServerStatusResult(
        port: 8080,
        running: true,
        pid: 12345,
        httpStatus: 200
    ))

    public var logsResult: Result<ServerLogsResult, Error> = .success(ServerLogsResult(
        port: 8080,
        pid: 12345,
        logs: "Mock server logs",
        follow: false
    ))

    public init() {}

    public func startServer(config: ServerStartConfig) async throws -> ServerStartResult {
        try startResult.get()
    }

    public func stopServer(port: Int) async throws -> ServerStopResult {
        try stopResult.get()
    }

    public func getServerStatus(port: Int) async throws -> ServerStatusResult {
        try statusResult.get()
    }

    public func getServerLogs(port: Int, lines: Int, follow: Bool) async throws -> ServerLogsResult {
        try logsResult.get()
    }
}

// MARK: - Performance Testing Service Mock

public class MockPerformanceTestingService: PerformanceTestingServiceProtocol {
    public var benchmarkResult: Result<BenchmarkResult, Error> = .success(BenchmarkResult(
        config: BenchmarkConfig(duration: 10, concurrency: 5, fileSize: 1024, swiftS3Mode: false, endpoint: "test", bucket: "test"),
        success: true,
        metrics: ["throughput": 100.5, "latency": 0.01],
        errorMessage: nil
    ))

    public var regressionResult: Result<RegressionResult, Error> = .success(RegressionResult(
        hasRegression: false,
        details: "No regression detected",
        baselineMetrics: ["throughput": 95.0],
        currentMetrics: ["throughput": 100.5]
    ))

    public var baselineUpdateResult: Result<BaselineUpdateResult, Error> = .success(BaselineUpdateResult(
        success: true,
        message: "Baseline updated successfully"
    ))

    public var reportResult: Result<PerformanceReport, Error> = .success(PerformanceReport(
        reportData: "Performance report data",
        format: "json"
    ))

    public init() {}

    public func runBenchmark(config: BenchmarkConfig) async throws -> BenchmarkResult {
        try benchmarkResult.get()
    }

    public func checkRegression() async throws -> RegressionResult {
        try regressionResult.get()
    }

    public func updateBaseline() async throws -> BaselineUpdateResult {
        try baselineUpdateResult.get()
    }

    public func generateReport() async throws -> PerformanceReport {
        try reportResult.get()
    }
}