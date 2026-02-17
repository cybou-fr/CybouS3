import ArgumentParser
import CybS3Lib
import Foundation

struct Chaos: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chaos",
        abstract: "Run chaos engineering tests to validate system resilience",
        subcommands: [
            Resilience.self,
            Inject.self,
            Clear.self,
        ]
    )

    struct Resilience: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resilience",
            abstract: "Run comprehensive resilience test with multiple fault scenarios"
        )

        @Option(name: .long, help: "Test duration in seconds")
        var duration: Int = 300

        func run() async throws {
            print("🧪 Starting Chaos Engineering Resilience Test")
            print("   Duration: \(duration)s")

            do {
                let report = try await ChaosEngine.testResilience(testDuration: TimeInterval(duration))
                print("\n" + report.description)

                if !report.success {
                    print("❌ Resilience test failed - system may not be resilient to failures")
                    throw ExitCode.failure
                } else {
                    print("✅ Resilience test passed - system is fault-tolerant")
                }
            } catch {
                print("❌ Chaos resilience test failed: \(error)")
                throw error
            }
        }
    }

    struct Inject: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "inject",
            abstract: "Inject a specific fault for testing"
        )

        @Option(name: .long, help: "Fault type (latency, failure, exhaustion, service)")
        var type: String

        @Option(name: .long, help: "Fault duration in seconds")
        var duration: Double = 30.0

        @Option(name: .long, help: "Additional parameters (e.g., delay=2.0, dropRate=0.1)")
        var params: [String] = []

        func run() async throws {
            print("🔥 Injecting chaos fault: \(type)")

            let fault: ChaosEngine.FaultType
            switch type.lowercased() {
            case "latency":
                let delay = params.first(where: { $0.hasPrefix("delay=") })?
                    .split(separator: "=").last.flatMap { Double($0) } ?? 2.0
                fault = .networkLatency(delay: delay)
            case "failure":
                let dropRate = params.first(where: { $0.hasPrefix("dropRate=") })?
                    .split(separator: "=").last.flatMap { Double($0) } ?? 0.1
                fault = .networkFailure(dropRate: dropRate)
            case "exhaustion":
                let memoryLimit = params.first(where: { $0.hasPrefix("memoryLimit=") })?
                    .split(separator: "=").last.flatMap { Int($0) } ?? 100
                fault = .resourceExhaustion(memoryLimit: memoryLimit)
            case "service":
                let component = params.first(where: { $0.hasPrefix("component=") })?
                    .split(separator: "=").last ?? "S3Client"
                fault = .serviceFailure(component: String(component))
            case "delays":
                let minDelay = params.first(where: { $0.hasPrefix("minDelay=") })?
                    .split(separator: "=").last.flatMap { Double($0) } ?? 0.1
                let maxDelay = params.first(where: { $0.hasPrefix("maxDelay=") })?
                    .split(separator: "=").last.flatMap { Double($0) } ?? 1.0
                fault = .randomDelays(minDelay: minDelay, maxDelay: maxDelay)
            default:
                print("❌ Unknown fault type: \(type)")
                print("   Available types: latency, failure, exhaustion, service, delays")
                throw ExitCode.failure
            }

            try await ChaosEngine.injectFault(fault, duration: duration)
            print("✅ Fault injection complete")
        }
    }

    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear all active chaos faults"
        )

        @MainActor
        func run() async throws {
            ChaosEngine.clearAllFaults()
            print("🧹 All chaos faults cleared")
        }
    }
}
