import XCTest
@testable import CybS3Lib

final class PerformanceHandlersTests: XCTestCase {

    // MARK: - Benchmark Handler Tests

    func testBenchmarkHandlerSuccess() async throws {
        // Given
        let mockPerformanceService = MockPerformanceTestingService()
        let expectedResults = [
            BenchmarkResult(operation: "upload", throughput: 100.5, latency: 0.01, successRate: 0.99),
            BenchmarkResult(operation: "download", throughput: 150.2, latency: 0.008, successRate: 0.98)
        ]
        let expectedSummary = BenchmarkSummary(
            totalOperations: 1000,
            duration: 10.5,
            averageThroughput: 125.35,
            averageLatency: 0.009,
            overallSuccessRate: 0.985
        )

        mockPerformanceService.benchmarkResult = .success(PerformanceBenchmarkOutput(
            success: true,
            message: "Benchmark completed successfully",
            results: expectedResults,
            summary: expectedSummary
        ))

        let handler = BenchmarkHandler(service: mockPerformanceService)
        let input = BenchmarkInput(options: BenchmarkOptions())

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Benchmark completed successfully")
        XCTAssertEqual(output.results.count, 2)
        XCTAssertEqual(output.results[0].operation, "upload")
        XCTAssertEqual(output.results[0].throughput, 100.5)
        XCTAssertEqual(output.results[1].operation, "download")
        XCTAssertEqual(output.results[1].throughput, 150.2)
        XCTAssertEqual(output.summary.totalOperations, 1000)
        XCTAssertEqual(output.summary.averageThroughput, 125.35)
    }

    func testBenchmarkHandlerFailure() async throws {
        // Given
        let mockPerformanceService = MockPerformanceTestingService()
        mockPerformanceService.benchmarkResult = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Benchmark failed"]))

        let handler = BenchmarkHandler(service: mockPerformanceService)
        let input = BenchmarkInput(options: BenchmarkOptions())

        // When/Then
        do {
            _ = try await handler.handle(input: input)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TestError")
        }
    }

    // MARK: - Load Test Handler Tests

    func testLoadTestHandlerSuccess() async throws {
        // Given
        let mockPerformanceService = MockPerformanceTestingService()
        let expectedMetrics = LoadTestMetrics(
            concurrentUsers: 50,
            totalRequests: 5000,
            successfulRequests: 4950,
            failedRequests: 50,
            averageResponseTime: 0.25,
            p95ResponseTime: 0.5,
            p99ResponseTime: 0.8,
            throughput: 476.19,
            errorRate: 0.01
        )

        mockPerformanceService.loadTestResult = .success(LoadTestOutput(
            success: true,
            message: "Load test completed successfully",
            metrics: expectedMetrics,
            recommendations: ["Consider increasing server capacity for higher loads"]
        ))

        let handler = LoadTestHandler(service: mockPerformanceService)
        let input = LoadTestInput(options: LoadTestOptions())

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Load test completed successfully")
        XCTAssertEqual(output.metrics.concurrentUsers, 50)
        XCTAssertEqual(output.metrics.totalRequests, 5000)
        XCTAssertEqual(output.metrics.successfulRequests, 4950)
        XCTAssertEqual(output.metrics.failedRequests, 50)
        XCTAssertEqual(output.metrics.averageResponseTime, 0.25)
        XCTAssertEqual(output.metrics.throughput, 476.19)
        XCTAssertEqual(output.metrics.errorRate, 0.01)
        XCTAssertEqual(output.recommendations, ["Consider increasing server capacity for higher loads"])
    }

    func testLoadTestHandlerHighLoad() async throws {
        // Given
        let mockPerformanceService = MockPerformanceTestingService()
        let highLoadMetrics = LoadTestMetrics(
            concurrentUsers: 100,
            totalRequests: 10000,
            successfulRequests: 9500,
            failedRequests: 500,
            averageResponseTime: 0.8,
            p95ResponseTime: 2.0,
            p99ResponseTime: 5.0,
            throughput: 250.0,
            errorRate: 0.05
        )

        mockPerformanceService.loadTestResult = .success(LoadTestOutput(
            success: true,
            message: "Load test completed with high error rate",
            metrics: highLoadMetrics,
            recommendations: ["High error rate detected", "Consider optimizing server performance"]
        ))

        let handler = LoadTestHandler(service: mockPerformanceService)
        let input = LoadTestInput(options: LoadTestOptions())

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.metrics.errorRate, 0.05)
        XCTAssertEqual(output.recommendations.count, 2)
    }

    // MARK: - Stress Test Handler Tests

    func testStressTestHandlerSuccess() async throws {
        // Given
        let mockPerformanceService = MockPerformanceTestingService()
        let expectedBreakingPoint = StressTestBreakingPoint(
            concurrentUsers: 200,
            errorRateThreshold: 0.05,
            responseTimeThreshold: 2.0
        )

        mockPerformanceService.stressTestResult = .success(StressTestOutput(
            success: true,
            message: "Stress test completed successfully",
            breakingPoint: expectedBreakingPoint,
            recommendations: ["System handles up to 200 concurrent users reliably"]
        ))

        let handler = StressTestHandler(service: mockPerformanceService)
        let input = StressTestInput(options: StressTestOptions())

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Stress test completed successfully")
        XCTAssertEqual(output.breakingPoint.concurrentUsers, 200)
        XCTAssertEqual(output.breakingPoint.errorRateThreshold, 0.05)
        XCTAssertEqual(output.breakingPoint.responseTimeThreshold, 2.0)
        XCTAssertEqual(output.recommendations, ["System handles up to 200 concurrent users reliably"])
    }

    func testStressTestHandlerFailure() async throws {
        // Given
        let mockPerformanceService = MockPerformanceTestingService()
        mockPerformanceService.stressTestResult = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stress test failed"]))

        let handler = StressTestHandler(service: mockPerformanceService)
        let input = StressTestInput(options: StressTestOptions())

        // When/Then
        do {
            _ = try await handler.handle(input: input)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TestError")
        }
    }
}