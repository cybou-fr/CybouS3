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
        vaults: ["test-vault"],
        currentVault: "test-vault",
        accessKey: "test-key",
        secretKey: "test-secret"
    ))

    func getConfiguration(list: Bool, reset: Bool, accessKey: String?, secretKey: String?) async throws -> ConfigOutput {
        try configResult.get()
    }

    func setConfiguration(mnemonic: String, accessKey: String?, secretKey: String?) async throws -> ConfigOutput {
        try configResult.get()
    }
}

// MARK: - File Operations Service Mock

class MockFileOperationsService: FileOperationsServiceProtocol {
    var uploadResult: Result<FileUploadOutput, Error> = .success(FileUploadOutput(
        success: true,
        message: "File uploaded successfully",
        filePath: "/test/path",
        bucket: "test-bucket",
        key: "test-key",
        size: 1024
    ))

    var downloadResult: Result<FileDownloadOutput, Error> = .success(FileDownloadOutput(
        success: true,
        message: "File downloaded successfully",
        localPath: "/local/test/path",
        remotePath: "s3://test-bucket/test-key",
        size: 1024
    ))

    var listResult: Result<FileListOutput, Error> = .success(FileListOutput(
        success: true,
        message: "Files listed successfully",
        files: [
            FileInfo(name: "test1.txt", size: 100, lastModified: Date(), etag: "etag1"),
            FileInfo(name: "test2.txt", size: 200, lastModified: Date(), etag: "etag2")
        ],
        totalSize: 300
    ))

    var deleteResult: Result<FileDeleteOutput, Error> = .success(FileDeleteOutput(
        success: true,
        message: "File deleted successfully",
        deletedFiles: ["test-file.txt"]
    ))

    var syncResult: Result<FileSyncOutput, Error> = .success(FileSyncOutput(
        success: true,
        message: "Sync completed successfully",
        uploaded: 5,
        downloaded: 3,
        deleted: 1,
        errors: []
    ))

    func upload(localPath: String, bucket: String, key: String?, options: UploadOptions) async throws -> FileUploadOutput {
        try uploadResult.get()
    }

    func download(remotePath: String, localPath: String?, options: DownloadOptions) async throws -> FileDownloadOutput {
        try downloadResult.get()
    }

    func list(bucket: String, prefix: String?, options: ListOptions) async throws -> FileListOutput {
        try listResult.get()
    }

    func delete(paths: [String], options: DeleteOptions) async throws -> FileDeleteOutput {
        try deleteResult.get()
    }

    func sync(localPath: String, bucket: String, options: SyncOptions) async throws -> FileSyncOutput {
        try syncResult.get()
    }
}

// MARK: - Bucket Operations Service Mock

class MockBucketOperationsService: BucketOperationsServiceProtocol {
    var createResult: Result<BucketCreateOutput, Error> = .success(BucketCreateOutput(
        success: true,
        message: "Bucket created successfully",
        bucket: "test-bucket"
    ))

    var listResult: Result<BucketListOutput, Error> = .success(BucketListOutput(
        success: true,
        message: "Buckets listed successfully",
        buckets: [
            BucketInfo(name: "bucket1", creationDate: Date()),
            BucketInfo(name: "bucket2", creationDate: Date())
        ]
    ))

    var deleteResult: Result<BucketDeleteOutput, Error> = .success(BucketDeleteOutput(
        success: true,
        message: "Bucket deleted successfully",
        bucket: "test-bucket"
    ))

    func create(name: String, options: BucketCreateOptions) async throws -> BucketCreateOutput {
        try createResult.get()
    }

    func list(options: BucketListOptions) async throws -> BucketListOutput {
        try listResult.get()
    }

    func delete(name: String, options: BucketDeleteOptions) async throws -> BucketDeleteOutput {
        try deleteResult.get()
    }
}

// MARK: - Server Process Service Mock

class MockServerProcessService: ServerProcessServiceProtocol {
    var startSwiftS3Result: Result<ServerStartOutput, Error> = .success(ServerStartOutput(
        success: true,
        message: "SwiftS3 server started successfully",
        pid: 12345,
        port: 8080
    ))

    var startCybKMSResult: Result<ServerStartOutput, Error> = .success(ServerStartOutput(
        success: true,
        message: "CybKMS server started successfully",
        pid: 12346,
        port: 8081
    ))

    var stopResult: Result<ServerStopOutput, Error> = .success(ServerStopOutput(
        success: true,
        message: "Server stopped successfully"
    ))

    var statusResult: Result<ServerStatusOutput, Error> = .success(ServerStatusOutput(
        success: true,
        message: "Server status retrieved",
        running: true,
        pid: 12345,
        port: 8080,
        uptime: 3600
    ))

    func startSwiftS3(options: ServerStartOptions) async throws -> ServerStartOutput {
        try startSwiftS3Result.get()
    }

    func startCybKMS(options: ServerStartOptions) async throws -> ServerStartOutput {
        try startCybKMSResult.get()
    }

    func stopSwiftS3() async throws -> ServerStopOutput {
        try stopResult.get()
    }

    func stopCybKMS() async throws -> ServerStopOutput {
        try stopResult.get()
    }

    func statusSwiftS3() async throws -> ServerStatusOutput {
        try statusResult.get()
    }

    func statusCybKMS() async throws -> ServerStatusOutput {
        try statusResult.get()
    }
}

// MARK: - Performance Testing Service Mock

class MockPerformanceTestingService: PerformanceTestingServiceProtocol {
    var benchmarkResult: Result<PerformanceBenchmarkOutput, Error> = .success(PerformanceBenchmarkOutput(
        success: true,
        message: "Benchmark completed successfully",
        results: [
            BenchmarkResult(operation: "upload", throughput: 100.5, latency: 0.01, successRate: 0.99),
            BenchmarkResult(operation: "download", throughput: 150.2, latency: 0.008, successRate: 0.98)
        ],
        summary: BenchmarkSummary(
            totalOperations: 1000,
            duration: 10.5,
            averageThroughput: 125.35,
            averageLatency: 0.009,
            overallSuccessRate: 0.985
        )
    ))

    var loadTestResult: Result<LoadTestOutput, Error> = .success(LoadTestOutput(
        success: true,
        message: "Load test completed successfully",
        metrics: LoadTestMetrics(
            concurrentUsers: 50,
            totalRequests: 5000,
            successfulRequests: 4950,
            failedRequests: 50,
            averageResponseTime: 0.25,
            p95ResponseTime: 0.5,
            p99ResponseTime: 0.8,
            throughput: 476.19,
            errorRate: 0.01
        ),
        recommendations: ["Consider increasing server capacity for higher loads"]
    ))

    var stressTestResult: Result<StressTestOutput, Error> = .success(StressTestOutput(
        success: true,
        message: "Stress test completed successfully",
        breakingPoint: StressTestBreakingPoint(
            concurrentUsers: 200,
            errorRateThreshold: 0.05,
            responseTimeThreshold: 2.0
        ),
        recommendations: ["System handles up to 200 concurrent users reliably"]
    ))

    func runBenchmark(options: BenchmarkOptions) async throws -> PerformanceBenchmarkOutput {
        try benchmarkResult.get()
    }

    func runLoadTest(options: LoadTestOptions) async throws -> LoadTestOutput {
        try loadTestResult.get()
    }

    func runStressTest(options: StressTestOptions) async throws -> StressTestOutput {
        try stressTestResult.get()
    }
}