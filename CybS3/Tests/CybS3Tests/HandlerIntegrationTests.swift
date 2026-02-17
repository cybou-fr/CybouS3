import XCTest
@testable import CybS3Lib

final class HandlerIntegrationTests: XCTestCase {

    // MARK: - Cross-Component Health Check Integration Tests

    func testEcosystemHealthCheckStructure() async throws {
        // This test verifies that the ecosystem health check can be performed
        // and returns a properly structured result, even if servers are not running

        let health = await EcosystemMonitor.checkCrossComponentHealth()

        // Verify the health structure
        XCTAssertNotNil(health.overallStatus)
        XCTAssertNotNil(health.componentHealth)
        XCTAssertNotNil(health.dependencies)
        XCTAssertNotNil(health.crossComponentIssues)

        // Should have health status for expected components
        XCTAssertNotNil(health.componentHealth["CybS3-Core"])
        XCTAssertNotNil(health.componentHealth["CybS3-Encryption"])
        XCTAssertNotNil(health.componentHealth["CybS3-Storage"])
        XCTAssertNotNil(health.componentHealth["SwiftS3-Server"])
        XCTAssertNotNil(health.componentHealth["SwiftS3-Storage"])
        XCTAssertNotNil(health.componentHealth["CybKMS-Server"])
    }

    func testEcosystemHealthCheckDependencies() async throws {
        // Test that dependency validation works
        let dependencies = await EcosystemMonitor.validateDependencies()

        // Should check the expected dependencies
        XCTAssertTrue(dependencies.checkedDependencies.contains("CybS3-SwiftS3-Connectivity"))
        XCTAssertTrue(dependencies.checkedDependencies.contains("Unified-Authentication"))
        XCTAssertTrue(dependencies.checkedDependencies.contains("Encryption-Compatibility"))
    }

    func testEcosystemHealthCheckReportGeneration() async throws {
        // Test that a monitoring report can be generated
        let report = await EcosystemMonitor.generateUnifiedReport()

        // Verify report structure
        XCTAssertNotNil(report.timestamp)
        XCTAssertNotNil(report.ecosystemHealth)
        XCTAssertNotNil(report.performanceMetrics)
        XCTAssertNotNil(report.recommendations)

        // Report should have a summary
        XCTAssertFalse(report.summary.isEmpty)
    }

    // MARK: - Handler Integration Tests

    func testHandlerWithMockServices() async throws {
        // Test that handlers work with mock services
        let mockAuthService = MockAuthenticationService()
        mockAuthService.loginResult = .success(LoginOutput(success: true, message: "Mock login successful"))

        let handler = LoginHandler(authService: mockAuthService)
        let input = LoginInput(mnemonic: "test mnemonic")

        let output = try await handler.handle(input: input)

        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Mock login successful")
    }

    func testFileHandlerIntegration() async throws {
        // Test file operations with mock service
        let mockFileService = MockFileOperationsService()
        mockFileService.uploadResult = .success(FileUploadOutput(
            success: true,
            message: "Mock upload successful",
            filePath: "/mock/path",
            bucket: "mock-bucket",
            key: "mock-key",
            size: 1234
        ))

        let handler = UploadHandler(fileService: mockFileService)
        let input = UploadInput(
            localPath: "/mock/path",
            bucket: "mock-bucket",
            key: "mock-key",
            options: UploadOptions()
        )

        let output = try await handler.handle(input: input)

        XCTAssertTrue(output.success)
        XCTAssertEqual(output.size, 1234)
    }

    func testBucketHandlerIntegration() async throws {
        // Test bucket operations with mock service
        let mockBucketService = MockBucketOperationsService()
        mockBucketService.listResult = .success(BucketListOutput(
            success: true,
            message: "Mock buckets listed",
            buckets: [
                BucketInfo(name: "bucket1", creationDate: Date()),
                BucketInfo(name: "bucket2", creationDate: Date())
            ]
        ))

        let handler = ListBucketsHandler(service: mockBucketService)
        let input = ListBucketsInput(options: BucketListOptions())

        let output = try await handler.handle(input: input)

        XCTAssertTrue(output.success)
        XCTAssertEqual(output.buckets.count, 2)
    }

    func testServerHandlerIntegration() async throws {
        // Test server operations with mock service
        let mockServerService = MockServerProcessService()
        mockServerService.statusSwiftS3Result = .success(ServerStatusOutput(
            success: true,
            message: "Mock server running",
            running: true,
            pid: 12345,
            port: 8080,
            uptime: 300
        ))

        let handler = StatusSwiftS3Handler(service: mockServerService)
        let input = StatusSwiftS3Input()

        let output = try await handler.handle(input: input)

        XCTAssertTrue(output.success)
        XCTAssertTrue(output.running)
        XCTAssertEqual(output.port, 8080)
    }

    func testPerformanceHandlerIntegration() async throws {
        // Test performance operations with mock service
        let mockPerformanceService = MockPerformanceTestingService()
        mockPerformanceService.benchmarkResult = .success(PerformanceBenchmarkOutput(
            success: true,
            message: "Mock benchmark completed",
            results: [
                BenchmarkResult(operation: "upload", throughput: 100.0, latency: 0.01, successRate: 0.99)
            ],
            summary: BenchmarkSummary(
                totalOperations: 1000,
                duration: 10.0,
                averageThroughput: 100.0,
                averageLatency: 0.01,
                overallSuccessRate: 0.99
            )
        ))

        let handler = BenchmarkHandler(service: mockPerformanceService)
        let input = BenchmarkInput(options: BenchmarkOptions())

        let output = try await handler.handle(input: input)

        XCTAssertTrue(output.success)
        XCTAssertEqual(output.results.count, 1)
        XCTAssertEqual(output.summary.totalOperations, 1000)
    }
}