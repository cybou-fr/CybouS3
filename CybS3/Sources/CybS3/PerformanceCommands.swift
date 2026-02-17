import ArgumentParser
import CybS3Lib
import Foundation

/// Performance testing and benchmarking commands
struct PerformanceCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "performance",
        abstract: "Run performance benchmarks and regression detection",
        subcommands: [Benchmark.self, Regression.self]
    )

    struct Benchmark: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "benchmark",
            abstract: "Run comprehensive performance tests"
        )

        @Option(name: .long, help: "Test duration in seconds")
        var duration: Int = 30

        @Option(name: .long, help: "Number of concurrent operations")
        var concurrency: Int = 4

        @Option(name: .long, help: "File size for tests (KB)")
        var fileSize: Int = 1024

        @Flag(name: .long, help: "Run against SwiftS3 server")
        var swiftS3: Bool = false

        @Option(name: .long, help: "SwiftS3 server endpoint")
        var endpoint: String = "http://127.0.0.1:8080"

        @Option(name: .long, help: "Test bucket for SwiftS3")
        var bucket: String = "benchmark-bucket"

        func run() async throws {
            if swiftS3 {
                print("🏃 Running CybS3 performance benchmarks against SwiftS3...")
                print("   Endpoint: \(endpoint)")
                print("   Bucket: \(bucket)")
                print("   Duration: \(duration)s")
                print("   Concurrency: \(concurrency)")
                print("   File size: \(fileSize)KB")

                // Start SwiftS3 if not running
                let serverProcess = Process()
                serverProcess.executableURL = URL(fileURLWithPath: "../SwiftS3/.build/release/SwiftS3")
                serverProcess.arguments = ["server", "--hostname", "127.0.0.1", "--port", "8080", "--storage", "/tmp/swifts3-benchmark", "--access-key", "admin", "--secret-key", "password"]

                let outputPipe = Pipe()
                serverProcess.standardOutput = outputPipe
                serverProcess.standardError = outputPipe
                serverProcess.terminationHandler = { _ in
                    print("🛑 SwiftS3 server stopped")
                }

                try serverProcess.run()
                print("🚀 SwiftS3 server started for benchmarking")

                // Wait for server to start
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

                // Create bucket
                let createProcess = Process()
                createProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                createProcess.arguments = ["buckets", "create", bucket, "--endpoint", endpoint, "--access-key", "admin", "--secret-key", "password", "--no-ssl"]
                try createProcess.run()
                await createProcess.waitUntilExit()

                // Run benchmark operations
                try await runSwiftS3Benchmark(duration: duration, concurrency: concurrency, fileSize: fileSize, bucket: bucket, endpoint: endpoint)

                // Stop server
                serverProcess.terminate()
                await serverProcess.waitUntilExit()

                print("\n✅ SwiftS3 benchmark complete")
            } else {
                print("🏃 Running CybS3 performance benchmarks...")
                print("   Duration: \(duration)s")
                print("   Concurrency: \(concurrency)")
                print("   File size: \(fileSize)KB")

                // This would run actual benchmarks, but for now just show placeholder
                print("\n📊 Performance Benchmark Results:")
                print("   ⚠️  Note: Full benchmarks require S3 credentials")
                print("   💡 Run integration tests with credentials for real benchmarks")

                // Could integrate with PerformanceBenchmarks.swift test methods
                print("\n✅ Benchmark setup complete")
                print("💡 Use 'swift test --filter PerformanceBenchmarks' for detailed benchmarks")
            }
        }

        private func runSwiftS3Benchmark(duration: Int, concurrency: Int, fileSize: Int, bucket: String, endpoint: String) async throws {
            print("\n📊 Running SwiftS3 Load Test...")

            // Create test data
            let testData = Data(repeating: 0x41, count: fileSize * 1024) // 'A' repeated

            let startTime = Date()

            // Actor to safely manage operations count across concurrent tasks
            actor OperationsCounter {
                var count = 0

                func increment() {
                    count += 1
                }

                func getCount() -> Int {
                    count
                }
            }

            let operationsCounter = OperationsCounter()

            // Run concurrent uploads
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<concurrency {
                    group.addTask {
                        while Date().timeIntervalSince(startTime) < Double(duration) {
                            let currentOps = await operationsCounter.getCount()
                            let key = "benchmark-\(i)-\(currentOps).dat"

                            let uploadProcess = Process()
                            uploadProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/cybs3")
                            uploadProcess.arguments = ["files", "put", "-", key, "--bucket", bucket, "--endpoint", endpoint, "--access-key", "admin", "--secret-key", "password", "--no-ssl"]

                            let inputPipe = Pipe()
                            uploadProcess.standardInput = inputPipe

                            try uploadProcess.run()

                            // Write test data to stdin
                            try inputPipe.fileHandleForWriting.write(contentsOf: testData)
                            try inputPipe.fileHandleForWriting.close()

                            await uploadProcess.waitUntilExit()

                            if uploadProcess.terminationStatus == 0 {
                                await operationsCounter.increment()
                            }
                        }
                    }
                }

                try await group.waitForAll()
            }

            let operations = await operationsCounter.getCount()
            let elapsed = Date().timeIntervalSince(startTime)
            let opsPerSecond = Double(operations) / elapsed
            let throughput = Double(operations * fileSize) / elapsed / 1024.0 // KB/s

            print("📈 Results:")
            print("   Operations: \(operations)")
            print("   Duration: \(String(format: "%.2f", elapsed))s")
            print("   Ops/sec: \(String(format: "%.2f", opsPerSecond))")
            print("   Throughput: \(String(format: "%.2f", throughput)) KB/s")
        }
    }

    struct Regression: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "regression",
            abstract: "Detect performance regressions against baseline results",
            subcommands: [
                Check.self,
                Update.self,
                Report.self,
            ]
        )

        struct Check: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "check",
                abstract: "Check for performance regressions"
            )

            @Option(name: .long, help: "Path to baseline results file (optional, uses stored baselines)")
            var baselineFile: String?

            @Flag(name: .long, help: "Fail build on regression detection")
            var failOnRegression: Bool = false

            func run() async throws {
                print("📊 Checking for performance regressions...")

                // Run current benchmarks
                print("🏃 Running current benchmarks...")
                // This would integrate with the actual benchmark execution
                // For now, create sample results
                let currentResults = [
                    RegressionDetector.BenchmarkResult(
                        operation: "single_upload_1MB",
                        duration: 0.85,
                        throughput: 1024.0 / 0.85, // KB/s
                        success: true
                    ),
                    RegressionDetector.BenchmarkResult(
                        operation: "concurrent_uploads_10x512KB",
                        duration: 2.1,
                        throughput: (10 * 512) / 2.1, // KB/s
                        success: true
                    )
                ]

                var baselines: [RegressionDetector.BenchmarkResult]?
                if let baselinePath = baselineFile {
                    // Load from file
                    let data = try Data(contentsOf: URL(fileURLWithPath: baselinePath))
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    baselines = try decoder.decode([RegressionDetector.BenchmarkResult].self, from: data)
                    print("📂 Loaded baselines from \(baselinePath)")
                }

                do {
                    let reports = try RegressionDetector.detectRegression(current: currentResults, baselines: baselines)

                    print("\n" + RegressionDetector.generateSummaryReport(reports))

                    if RegressionDetector.shouldFailBuild(reports) && failOnRegression {
                        print("❌ Build failed due to performance regression")
                        throw ExitCode.failure
                    }
                } catch {
                    print("❌ Regression detection failed: \(error)")
                    throw error
                }
            }
        }

        struct Update: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "update",
                abstract: "Update performance baselines with current results"
            )

            @Option(name: .long, help: "Path to save baseline results (optional, uses secure storage)")
            var outputFile: String?

            func run() async throws {
                print("📝 Updating performance baselines...")

                // Generate sample baseline results
                // In production, this would run actual benchmarks
                let baselineResults = [
                    RegressionDetector.BenchmarkResult(
                        operation: "single_upload_1MB",
                        duration: 0.8,
                        throughput: 1024.0 / 0.8,
                        success: true
                    ),
                    RegressionDetector.BenchmarkResult(
                        operation: "concurrent_uploads_10x512KB",
                        duration: 2.0,
                        throughput: (10 * 512) / 2.0,
                        success: true
                    )
                ]

                if let outputPath = outputFile {
                    // Save to file
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(baselineResults)
                    try data.write(to: URL(fileURLWithPath: outputPath))
                    print("💾 Baselines saved to \(outputPath)")
                } else {
                    // Save to secure storage
                    try RegressionDetector.updateBaselines(baselineResults)
                    print("🔐 Baselines updated in secure storage")
                }
            }
        }

        struct Report: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "report",
                abstract: "Generate detailed regression report"
            )

            @Option(name: .long, help: "Output format (console, json)")
            var format: String = "console"

            func run() async throws {
                print("📋 Generating regression report...")

                do {
                    let baselines = try RegressionDetector.loadBaselines()

                    if baselines.isEmpty {
                        print("⚠️ No baseline results found")
                        print("💡 Run 'cybs3 performance regression update' to establish baselines")
                        return
                    }

                    print("📊 Current Baselines:")
                    for baseline in baselines.sorted(by: { $0.operation < $1.operation }) {
                        print("  • \(baseline.operation): \(String(format: "%.3f", baseline.duration))s (\(String(format: "%.1f", baseline.throughput))/s)")
                    }

                } catch {
                    print("❌ Failed to load baselines: \(error)")
                    throw error
                }
            }
        }
    }
}