import Foundation

/// Mock services for unit testing handlers
/// These mocks implement the service protocols with controllable behavior for testing

// MARK: - Authentication Service Mock

class MockAuthenticationService: AuthenticationServiceProtocol {
    var loginResult: Result<LoginOutput, Error> = .success(LoginOutput(success: true, message: "Login successful"))
    var logoutResult: Result<LogoutOutput, Error> = .success(LogoutOutput(success: true, message: "Logout successful"))

    func login(mnemonic: String) async throws -> LoginOutput {
        try loginResult.get()
    }

    func logout() async throws -> LogoutOutput {
        try logoutResult.get()
    }
}

// MARK: - Configuration Service Mock

class MockConfigurationService: ConfigurationServiceProtocol {
    var configResult: Result<ConfigOutput, Error> = .success(ConfigOutput(
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

    var updateResult: Result<ConfigOutput, Error> = .success(ConfigOutput(
        success: true,
        message: "Configuration updated",
        config: nil
    ))

    var resetResult: Result<Void, Error> = .success(())
    var createVaultResult: Result<Void, Error> = .success(())
    var setActiveVaultResult: Result<Void, Error> = .success(())

    func getConfig(mnemonic: String) async throws -> Configuration {
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

    func updateConfig(mnemonic: String, updates: ConfigInput) async throws -> ConfigOutput {
        try updateResult.get()
    }

    func resetConfig() async throws {
        try resetResult.get()
    }

    func createVault(mnemonic: String, name: String) async throws {
        try createVaultResult.get()
    }

    func setActiveVault(mnemonic: String, name: String) async throws {
        try setActiveVaultResult.get()
    }

    // Legacy methods for backward compatibility
    func getConfiguration(list: Bool, reset: Bool, accessKey: String?, secretKey: String?) async throws -> ConfigOutput {
        try configResult.get()
    }

    func setConfiguration(mnemonic: String, accessKey: String?, secretKey: String?) async throws -> ConfigOutput {
        try configResult.get()
    }
}

// MARK: - File Operations Service Mock

class MockFileOperationsService: FileOperationsServiceProtocol {
    var listResult: Result<ListFilesOutput, Error> = .success(ListFilesOutput(
        objects: [S3Object(key: "test-file.txt", size: 1024, lastModified: Date(), isDirectory: false, etag: "test-etag")],
        success: true,
        message: "Files listed successfully"
    ))

    var getResult: Result<GetFileOutput, Error> = .success(GetFileOutput(
        success: true,
        message: "File retrieved successfully",
        bytesDownloaded: 1024,
        fileSize: 1024
    ))

    var putResult: Result<PutFileOutput, Error> = .success(PutFileOutput(
        success: true,
        message: "File uploaded successfully",
        bytesUploaded: 1024,
        encryptedSize: 1040
    ))

    var deleteResult: Result<DeleteFileOutput, Error> = .success(DeleteFileOutput(
        success: true,
        message: "File deleted successfully"
    ))

    var copyResult: Result<CopyFileOutput, Error> = .success(CopyFileOutput(
        success: true,
        message: "File copied successfully"
    ))

    func listFiles(input: ListFilesInput) async throws -> ListFilesOutput {
        try listResult.get()
    }

    func getFile(input: GetFileInput) async throws -> GetFileOutput {
        try getResult.get()
    }

    func putFile(input: PutFileInput) async throws -> PutFileOutput {
        try putResult.get()
    }

    func deleteFile(input: DeleteFileInput) async throws -> DeleteFileOutput {
        try deleteResult.get()
    }

    func copyFile(input: CopyFileInput) async throws -> CopyFileOutput {
        try copyResult.get()
    }
}

// MARK: - Bucket Operations Service Mock

class MockBucketOperationsService: BucketOperationsServiceProtocol {
    var createBucketResult: Result<Void, Error> = .success(())
    var deleteBucketResult: Result<Void, Error> = .success(())
    var listBucketsResult: Result<[String], Error> = .success(["test-bucket1", "test-bucket2"])

    func createBucket(name: String) async throws {
        try createBucketResult.get()
    }

    func deleteBucket(name: String) async throws {
        try deleteBucketResult.get()
    }

    func listBuckets() async throws -> [String] {
        try listBucketsResult.get()
    }
}

// MARK: - Server Process Service Mock

class MockServerProcessService: ServerProcessServiceProtocol {
    var startResult: Result<ServerStartResult, Error> = .success(ServerStartResult(
        port: 8080,
        hostname: "localhost",
        pid: 12345,
        background: true
    ))

    var stopResult: Result<ServerStopResult, Error> = .success(ServerStopResult(
        port: 8080,
        pid: 12345
    ))

    var statusResult: Result<ServerStatusResult, Error> = .success(ServerStatusResult(
        port: 8080,
        running: true,
        pid: 12345,
        httpStatus: 200
    ))

    var logsResult: Result<ServerLogsResult, Error> = .success(ServerLogsResult(
        port: 8080,
        pid: 12345,
        logs: "Mock server logs",
        follow: false
    ))

    func startServer(config: ServerStartConfig) async throws -> ServerStartResult {
        try startResult.get()
    }

    func stopServer(port: Int) async throws -> ServerStopResult {
        try stopResult.get()
    }

    func getServerStatus(port: Int) async throws -> ServerStatusResult {
        try statusResult.get()
    }

    func getServerLogs(port: Int, lines: Int, follow: Bool) async throws -> ServerLogsResult {
        try logsResult.get()
    }
}

// MARK: - Performance Testing Service Mock

class MockPerformanceTestingService: PerformanceTestingServiceProtocol {
    var benchmarkResult: Result<BenchmarkResult, Error> = .success(BenchmarkResult(
        config: BenchmarkConfig(duration: 10, concurrency: 5, fileSize: 1024, swiftS3Mode: false, endpoint: "test", bucket: "test"),
        success: true,
        metrics: ["throughput": 100.5, "latency": 0.01],
        errorMessage: nil
    ))

    var regressionResult: Result<RegressionResult, Error> = .success(RegressionResult(
        hasRegression: false,
        details: "No regression detected",
        baselineMetrics: ["throughput": 95.0],
        currentMetrics: ["throughput": 100.5]
    ))

    var baselineUpdateResult: Result<BaselineUpdateResult, Error> = .success(BaselineUpdateResult(
        success: true,
        message: "Baseline updated successfully"
    ))

    var reportResult: Result<PerformanceReport, Error> = .success(PerformanceReport(
        reportData: "Performance report data",
        format: "json"
    ))

    func runBenchmark(config: BenchmarkConfig) async throws -> BenchmarkResult {
        try benchmarkResult.get()
    }

    func checkRegression() async throws -> RegressionResult {
        try regressionResult.get()
    }

    func updateBaseline() async throws -> BaselineUpdateResult {
        try baselineUpdateResult.get()
    }

    func generateReport() async throws -> PerformanceReport {
        try reportResult.get()
    }
}