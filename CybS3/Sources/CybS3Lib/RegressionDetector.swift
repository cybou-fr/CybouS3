import Foundation

/// Performance regression detection system for automated benchmark monitoring.
public struct RegressionDetector {
    /// Benchmark result data structure.
    public struct BenchmarkResult: Codable {
        public let timestamp: Date
        public let operation: String
        public let duration: TimeInterval
        public let throughput: Double
        public let success: Bool
        public let metadata: [String: String]

        public init(operation: String, duration: TimeInterval, throughput: Double, success: Bool, metadata: [String: String] = [:]) {
            self.timestamp = Date()
            self.operation = operation
            self.duration = duration
            self.throughput = throughput
            self.success = success
            self.metadata = metadata
        }
    }

    /// Regression analysis report.
    public struct RegressionReport {
        public let operation: String
        public let baseline: BenchmarkResult?
        public let current: BenchmarkResult
        public let regressionDetected: Bool
        public let regressionPercentage: Double
        public let confidence: Double
        public let recommendations: [String]

        public var description: String {
            var report = """
            Performance Regression Report
            =============================
            Operation: \(operation)
            Current: \(String(format: "%.3f", current.duration))s (\(String(format: "%.2f", current.throughput))/s)
            """

            if let baseline = baseline {
                report += """
            Baseline: \(String(format: "%.3f", baseline.duration))s (\(String(format: "%.2f", baseline.throughput))/s)
            Change: \(String(format: "%.1f", regressionPercentage))%
            Confidence: \(String(format: "%.1f", confidence * 100))%
            Status: \(regressionDetected ? "⚠️ REGRESSION DETECTED" : "✅ NO REGRESSION")
            """
            } else {
                report += "\nBaseline: Not available (first run)\n"
            }

            if !recommendations.isEmpty {
                report += "\nRecommendations:\n"
                for recommendation in recommendations {
                    report += "  • \(recommendation)\n"
                }
            }

            return report
        }
    }

    /// Statistical analysis result.
    private struct StatisticalAnalysis {
        let mean: Double
        let standardDeviation: Double
        let confidenceInterval: (lower: Double, upper: Double)
    }

    private static let baselineKey = "performance_baselines"
    private static let regressionThreshold = 0.10 // 10% regression threshold
    private static let minimumConfidence = 0.80 // 80% confidence required

    /// Store benchmark results as new baselines.
    ///
    /// - Parameter results: Array of benchmark results to store as baselines.
    public static func updateBaselines(_ results: [BenchmarkResult]) throws {
        let storage = SecureStorageFactory.create()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(results)
        try storage.store(data, for: baselineKey)

        print("📊 Updated performance baselines for \(results.count) operations")
    }

    /// Load stored baseline results.
    ///
    /// - Returns: Array of baseline benchmark results.
    public static func loadBaselines() throws -> [BenchmarkResult] {
        let storage = SecureStorageFactory.create()

        guard let data = try storage.retrieve(for: baselineKey) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([BenchmarkResult].self, from: data)
    }

    /// Detect performance regression by comparing current results against baselines.
    ///
    /// - Parameters:
    ///   - current: Current benchmark results.
    ///   - baselines: Baseline results to compare against (optional, loads from storage if nil).
    /// - Returns: Array of regression reports for each operation.
    public static func detectRegression(current: [BenchmarkResult], baselines: [BenchmarkResult]? = nil) throws -> [RegressionReport] {
        let baselineResults = try baselines ?? loadBaselines()
        let baselineMap = Dictionary(grouping: baselineResults, by: { $0.operation })

        return current.map { currentResult in
            let operationBaselines = baselineMap[currentResult.operation] ?? []

            // Use the most recent baseline for this operation
            let baseline = operationBaselines.sorted(by: { $0.timestamp > $1.timestamp }).first

            return analyzeRegression(current: currentResult, baseline: baseline)
        }
    }

    /// Check if any regression in the reports should fail the build.
    ///
    /// - Parameter reports: Array of regression reports.
    /// - Returns: True if build should fail due to regressions.
    public static func shouldFailBuild(_ reports: [RegressionReport]) -> Bool {
        reports.contains { report in
            report.regressionDetected && report.confidence >= minimumConfidence
        }
    }

    /// Generate a summary report for multiple regression analyses.
    ///
    /// - Parameter reports: Array of regression reports.
    /// - Returns: Summary string.
    public static func generateSummaryReport(_ reports: [RegressionReport]) -> String {
        let regressions = reports.filter { $0.regressionDetected }
        let totalOperations = reports.count
        let failedOperations = reports.filter { !$0.current.success }.count

        var summary = """
        Performance Regression Summary
        ===============================
        Total Operations: \(totalOperations)
        Failed Operations: \(failedOperations)
        Regressions Detected: \(regressions.count)
        """

        if !regressions.isEmpty {
            summary += "\n\nRegressions:\n"
            for regression in regressions.sorted(by: { $0.regressionPercentage > $1.regressionPercentage }) {
                summary += "  • \(regression.operation): \(String(format: "%.1f", regression.regressionPercentage))% slower\n"
            }
        }

        let shouldFail = shouldFailBuild(reports)
        summary += "\nBuild Status: \(shouldFail ? "❌ FAILED" : "✅ PASSED")"

        return summary
    }

    // MARK: - Private Methods

    private static func analyzeRegression(current: BenchmarkResult, baseline: BenchmarkResult?) -> RegressionReport {
        guard let baseline = baseline else {
            return RegressionReport(
                operation: current.operation,
                baseline: nil,
                current: current,
                regressionDetected: false,
                regressionPercentage: 0.0,
                confidence: 0.0,
                recommendations: ["First benchmark run - establishing baseline"]
            )
        }

        // Calculate regression percentage (positive = slower/worse)
        let regressionPercentage: Double
        if current.operation.contains("throughput") || current.operation.contains("bandwidth") {
            // For throughput metrics, lower is worse
            regressionPercentage = ((baseline.throughput - current.throughput) / baseline.throughput) * 100
        } else {
            // For duration metrics, higher is worse
            regressionPercentage = ((current.duration - baseline.duration) / baseline.duration) * 100
        }

        // Simple statistical analysis (in production, use more sophisticated methods)
        let confidence = calculateConfidence(baseline: baseline, current: current)

        let regressionDetected = regressionPercentage > (regressionThreshold * 100) && confidence >= minimumConfidence

        var recommendations = [String]()
        if regressionDetected {
            recommendations.append("Performance regression detected: \(String(format: "%.1f", regressionPercentage))% change")
            recommendations.append("Review recent code changes for performance impacts")
            recommendations.append("Consider profiling the \(current.operation) operation")

            if regressionPercentage > 50 {
                recommendations.append("🚨 Critical: Performance degraded by >50% - immediate investigation required")
            }
        }

        if !current.success {
            recommendations.append("Current benchmark failed - check system stability")
        }

        return RegressionReport(
            operation: current.operation,
            baseline: baseline,
            current: current,
            regressionDetected: regressionDetected,
            regressionPercentage: regressionPercentage,
            confidence: confidence,
            recommendations: recommendations
        )
    }

    private static func calculateConfidence(baseline: BenchmarkResult, current: BenchmarkResult) -> Double {
        // Simple confidence calculation based on result stability
        // In production, this would use statistical tests like t-test

        let durationDiff = abs(current.duration - baseline.duration)
        let throughputDiff = abs(current.throughput - baseline.throughput)

        // If differences are small relative to baseline values, high confidence
        let durationConfidence = min(1.0, baseline.duration / max(durationDiff, 0.001))
        let throughputConfidence = min(1.0, baseline.throughput / max(throughputDiff, 0.001))

        // Average confidence, but weight duration more for timing-critical operations
        return (durationConfidence * 0.7 + throughputConfidence * 0.3)
    }
}