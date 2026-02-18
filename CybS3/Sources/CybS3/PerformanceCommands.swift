import ArgumentParser
import CybS3Lib
import Foundation

/// Performance testing and benchmarking commands
struct PerformanceCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "performance",
        abstract: "Run performance benchmarks and regression detection",
        subcommands: [Benchmark.self, Compression.self, Regression.self]
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
            let service = DefaultPerformanceTestingService()
            let handler = RunBenchmarkHandler(service: service)

            let config = BenchmarkConfig(
                duration: duration,
                concurrency: concurrency,
                fileSize: fileSize,
                swiftS3Mode: swiftS3,
                endpoint: endpoint,
                bucket: bucket
            )

            let input = RunBenchmarkInput(config: config)
            let output = try await handler.handle(input: input)

            if output.result.config.swiftS3Mode {
                print("🏃 Running CybS3 performance benchmarks against SwiftS3...")
                print("   Endpoint: \(output.result.config.endpoint)")
                print("   Bucket: \(output.result.config.bucket)")
                print("   Duration: \(output.result.config.duration)s")
                print("   Concurrency: \(output.result.config.concurrency)")
                print("   File size: \(output.result.config.fileSize)KB")

                // For now, just show that the handler worked
                if output.result.success {
                    print("\n✅ SwiftS3 benchmark complete")
                    if let metrics = output.result.metrics {
                        print("📊 Results:")
                        for (key, value) in metrics {
                            print("   \(key): \(value)")
                        }
                    }
                } else {
                    print("❌ Benchmark failed: \(output.result.errorMessage ?? "Unknown error")")
                }
            } else {
                print("🏃 Running CybS3 performance benchmarks...")
                print("   Duration: \(duration)s")
                print("   Concurrency: \(concurrency)")
                print("   File size: \(fileSize)KB")

                if output.result.success {
                    print("\n📊 Performance Benchmark Results:")
                    print("   ⚠️  Note: Full benchmarks require S3 credentials")
                    print("   💡 Run integration tests with credentials for real benchmarks")

                    if let metrics = output.result.metrics {
                        for (key, value) in metrics {
                            print("   \(key): \(value)")
                        }
                    }

                    print("\n✅ Benchmark setup complete")
                    print("💡 Use 'swift test --filter PerformanceBenchmarks' for detailed benchmarks")
                } else {
                    print("❌ Benchmark failed: \(output.result.errorMessage ?? "Unknown error")")
                }
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

    struct Compression: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compression",
            abstract: "Run compression and encryption performance benchmarks"
        )

        @Option(name: .long, help: "Test data size in MB")
        var dataSize: Int = 10

        @Option(name: .long, help: "Number of benchmark iterations")
        var iterations: Int = 3

        @Flag(name: .long, help: "Include encryption benchmarks")
        var includeEncryption: Bool = true

        @Flag(name: .long, help: "Include combined compression+encryption benchmarks")
        var includeCombined: Bool = true

        @Option(name: .long, help: "Data type for testing (random, text, binary)")
        var dataType: String = "random"

        func run() async throws {
            print("🗜️  Running compression and encryption benchmarks...")
            print("   Data size: \(dataSize)MB")
            print("   Iterations: \(iterations)")
            print("   Data type: \(dataType)")
            print("   Include encryption: \(includeEncryption)")
            print("   Include combined: \(includeCombined)")

            let service = DefaultPerformanceTestingService()
            let handler = RunCompressionBenchmarkHandler(service: service)

            // Build algorithms list based on flags
            var algorithms = ["gzip", "bzip2", "xz"]
            if includeEncryption {
                algorithms.append(contentsOf: ["aes-gcm", "chacha20"])
            }
            if includeCombined {
                algorithms.append("combined")
            }

            let config = CompressionBenchmarkConfig(
                dataSizes: [dataSize * 1024 * 1024], // Convert MB to bytes
                iterations: iterations,
                algorithms: algorithms,
                dataPatterns: [dataType]
            )

            let input = RunCompressionBenchmarkInput(config: config)
            let output = try await handler.handle(input: input)

            if output.result.success {
                print("\n✅ Compression benchmark complete")
                print("📊 Results:")

                if let results = output.result.results {
                    for result in results {
                        print("\n🔧 Algorithm: \(result.algorithm)")
                        print("   📏 Compression Ratio: \(String(format: "%.3f", result.compressionRatio ?? 0))x")
                        print("   ⚡ Compression Throughput: \(String(format: "%.2f", result.compressionThroughput)) MB/s")
                        print("   📤 Decompression Throughput: \(String(format: "%.2f", result.decompressionThroughput)) MB/s")

                        if result.encryptionThroughput > 0 {
                            print("   🔐 Encryption Throughput: \(String(format: "%.2f", result.encryptionThroughput)) MB/s")
                        }

                        if result.decryptionThroughput > 0 {
                            print("   🔓 Decryption Throughput: \(String(format: "%.2f", result.decryptionThroughput)) MB/s")
                        }

                        print("   ⏱️  Average Time: \(String(format: "%.3f", result.totalTime))s")
                    }
                }

                if let summary = output.result.summary {
                    print("\n📋 Summary:")
                    print("   🏆 Best Compression: \(summary.bestCompressionAlgorithm) (\(String(format: "%.3f", summary.bestCompressionRatio))x)")
                    print("   🚀 Fastest Compression: \(summary.fastestCompressionAlgorithm) (\(String(format: "%.2f", summary.fastestCompressionThroughput)) MB/s)")
                    print("   💡 Recommendation: \(summary.recommendation)")
                }
            } else {
                print("❌ Benchmark failed: \(output.result.errorMessage ?? "Unknown error")")
            }
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

                let service = DefaultPerformanceTestingService()
                let handler = CheckRegressionHandler(service: service)

                let input = CheckRegressionInput()
                let output = try await handler.handle(input: input)

                if output.result.hasRegression {
                    print("⚠️  Performance regression detected!")
                    print("Details: \(output.result.details)")
                } else {
                    print("✅ No performance regression detected")
                    print("Details: \(output.result.details)")
                }

                if let baseline = output.result.baselineMetrics,
                   let current = output.result.currentMetrics {
                    print("\n📊 Metrics Comparison:")
                    for (key, baselineValue) in baseline {
                        if let currentValue = current[key] {
                            let change = ((currentValue - baselineValue) / baselineValue) * 100
                            let symbol = change > 0 ? "📈" : change < 0 ? "📉" : "➡️"
                            print("   \(key): \(String(format: "%.2f", baselineValue)) → \(String(format: "%.2f", currentValue)) (\(symbol) \(String(format: "%.1f", change))%)")
                        }
                    }
                }

                if output.result.hasRegression && failOnRegression {
                    print("❌ Build failed due to performance regression")
                    throw ExitCode.failure
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

                let service = DefaultPerformanceTestingService()
                let handler = UpdateBaselineHandler(service: service)

                let input = UpdateBaselineInput()
                let output = try await handler.handle(input: input)

                if output.result.success {
                    print("✅ \(output.result.message)")
                } else {
                    print("❌ Failed to update baseline: \(output.result.message)")
                    throw ExitCode.failure
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

                let service = DefaultPerformanceTestingService()
                let handler = GenerateReportHandler(service: service)

                let input = GenerateReportInput()
                let output = try await handler.handle(input: input)

                print("📊 Performance Report:")
                print(output.result.reportData)
            }
        }
    }
}