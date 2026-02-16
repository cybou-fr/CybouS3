import Foundation
import Network

/// Chaos engineering framework for testing system resilience under failure conditions.
public struct ChaosEngine {
    /// Types of faults that can be injected into the system.
    public enum FaultType {
        /// Introduce network latency by delaying requests.
        case networkLatency(delay: TimeInterval)
        /// Simulate network failures by dropping packets.
        case networkFailure(dropRate: Double)
        /// Exhaust system resources by limiting memory.
        case resourceExhaustion(memoryLimit: Int)
        /// Simulate service component failures.
        case serviceFailure(component: String)
        /// Introduce random delays in operations.
        case randomDelays(minDelay: TimeInterval, maxDelay: TimeInterval)
    }

    /// Resilience test results.
    public struct ResilienceReport {
        public let testDuration: TimeInterval
        public let faultsInjected: [FaultType]
        public let operationsPerformed: Int
        public let failuresEncountered: Int
        public let recoveryTime: TimeInterval
        public let success: Bool

        public var description: String {
            """
            Chaos Engineering Resilience Report
            ===================================
            Duration: \(String(format: "%.2f", testDuration))s
            Faults Injected: \(faultsInjected.count)
            Operations: \(operationsPerformed)
            Failures: \(failuresEncountered)
            Recovery Time: \(String(format: "%.2f", recoveryTime))s
            Status: \(success ? "✅ PASSED" : "❌ FAILED")
            """
        }
    }

    private static var activeFaults = [String: FaultType]()
    private static let faultQueue = DispatchQueue(label: "com.cybs3.chaos.faults")

    /// Inject a fault into the system for testing purposes.
    ///
    /// - Parameters:
    ///   - fault: The type of fault to inject.
    ///   - duration: How long the fault should persist.
    ///   - identifier: Unique identifier for the fault (auto-generated if nil).
    public static func injectFault(_ fault: FaultType, duration: TimeInterval, identifier: String? = nil) async throws {
        let faultId = identifier ?? UUID().uuidString

        faultQueue.async {
            activeFaults[faultId] = fault
        }

        print("🔥 Chaos: Injected fault '\(faultId)' for \(String(format: "%.1f", duration))s")

        // Apply the fault
        try await applyFault(fault, identifier: faultId)

        // Schedule fault removal
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        faultQueue.async {
            activeFaults.removeValue(forKey: faultId)
        }

        print("🛑 Chaos: Removed fault '\(faultId)'")
    }

    /// Check if a specific fault is currently active.
    public static func isFaultActive(_ identifier: String) -> Bool {
        faultQueue.sync {
            activeFaults[identifier] != nil
        }
    }

    /// Get all currently active faults.
    public static func getActiveFaults() -> [String: FaultType] {
        faultQueue.sync {
            activeFaults
        }
    }

    /// Clear all active faults.
    public static func clearAllFaults() {
        faultQueue.async {
            activeFaults.removeAll()
        }
        print("🧹 Chaos: Cleared all active faults")
    }

    /// Run a comprehensive resilience test with multiple fault scenarios.
    public static func testResilience(testDuration: TimeInterval = 300) async throws -> ResilienceReport {
        print("🧪 Starting Chaos Engineering Resilience Test")
        print("   Duration: \(String(format: "%.0f", testDuration))s")

        let startTime = Date()
        var operationsPerformed = 0
        var failuresEncountered = 0
        var injectedFaults = [FaultType]()

        // Define test scenarios
        let scenarios = [
            FaultType.networkLatency(delay: 2.0),
            FaultType.networkFailure(dropRate: 0.1),
            FaultType.randomDelays(minDelay: 0.1, maxDelay: 1.0),
            FaultType.serviceFailure(component: "S3Client")
        ]

        // Run test with periodic fault injection
        let faultInterval = testDuration / Double(scenarios.count)

        for (index, scenario) in scenarios.enumerated() {
            let faultDuration = min(30.0, faultInterval * 0.8) // Fault lasts 80% of interval, max 30s

            do {
                try await injectFault(scenario, duration: faultDuration)
                injectedFaults.append(scenario)
            } catch {
                print("⚠️  Failed to inject fault \(scenario): \(error)")
            }

            // Wait for next fault injection
            if index < scenarios.count - 1 {
                try await Task.sleep(nanoseconds: UInt64((faultInterval - faultDuration) * 1_000_000_000))
            }
        }

        // Run continuous operations during chaos
        let chaosTask = Task {
            var localOperations = 0
            var localFailures = 0

            while !Task.isCancelled && Date().timeIntervalSince(startTime) < testDuration {
                do {
                    // Simulate a typical operation that might be affected by chaos
                    try await simulateOperationUnderChaos()
                    localOperations += 1
                } catch {
                    localFailures += 1
                    print("❌ Operation failed under chaos: \(error.localizedDescription)")
                }

                // Small delay between operations
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }

            return (localOperations, localFailures)
        }

        // Wait for test completion
        let (ops, fails) = await chaosTask.result.get()
        operationsPerformed = ops
        failuresEncountered = fails

        let totalDuration = Date().timeIntervalSince(startTime)

        // Calculate recovery time (time after last fault until end)
        let lastFaultEnd = startTime.addingTimeInterval(testDuration - 30.0) // Approximate
        let recoveryTime = Date().timeIntervalSince(lastFaultEnd)

        // Determine success based on reasonable failure rate
        let failureRate = Double(failuresEncountered) / Double(operationsPerformed)
        let success = failureRate < 0.5 && operationsPerformed > 10 // Allow up to 50% failures but require minimum operations

        let report = ResilienceReport(
            testDuration: totalDuration,
            faultsInjected: injectedFaults,
            operationsPerformed: operationsPerformed,
            failuresEncountered: failuresEncountered,
            recoveryTime: recoveryTime,
            success: success
        )

        print("✅ Chaos Engineering Test Complete")
        print(report.description)

        return report
    }

    /// Simulate network partition between components.
    public static func simulateNetworkPartition(duration: TimeInterval = 60) async throws {
        print("🌐 Simulating network partition for \(String(format: "%.0f", duration))s")

        // This would typically involve:
        // 1. Blocking network connections between CybS3 and SwiftS3
        // 2. Testing system behavior during partition
        // 3. Restoring connections and testing recovery

        // For now, simulate with delays and failures
        try await injectFault(.networkFailure(dropRate: 1.0), duration: duration, identifier: "network_partition")

        print("🔄 Network partition simulation complete")
    }

    // MARK: - Private Methods

    private static func applyFault(_ fault: FaultType, identifier: String) async throws {
        switch fault {
        case .networkLatency(let delay):
            // This would typically intercept network calls and add delays
            print("   📡 Injecting \(String(format: "%.1f", delay))s network latency")

        case .networkFailure(let dropRate):
            print("   📡 Injecting \(String(format: "%.1f", dropRate * 100))% packet loss")

        case .resourceExhaustion(let memoryLimit):
            print("   🧠 Limiting memory to \(memoryLimit)MB")

        case .serviceFailure(let component):
            print("   💥 Simulating \(component) failure")

        case .randomDelays(let minDelay, let maxDelay):
            print("   ⏰ Injecting random delays (\(String(format: "%.1f", minDelay))-\(String(format: "%.1f", maxDelay))s)")
        }
    }

    private static func simulateOperationUnderChaos() async throws {
        // Simulate a typical operation that could be affected by chaos
        let activeFaults = getActiveFaults()

        for (_, fault) in activeFaults {
            switch fault {
            case .networkLatency(let delay):
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            case .networkFailure(let dropRate):
                if Double.random(in: 0...1) < dropRate {
                    throw ChaosError.networkFailure
                }

            case .randomDelays(let minDelay, let maxDelay):
                let randomDelay = Double.random(in: minDelay...maxDelay)
                try await Task.sleep(nanoseconds: UInt64(randomDelay * 1_000_000_000))

            case .serviceFailure(let component):
                if component == "S3Client" && Double.random(in: 0...1) < 0.3 {
                    throw ChaosError.serviceFailure(component: component)
                }

            case .resourceExhaustion:
                // Simulate memory pressure
                if Double.random(in: 0...1) < 0.1 {
                    throw ChaosError.resourceExhaustion
                }
            }
        }

        // Simulate successful operation
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms operation
    }
}

/// Errors that can occur during chaos testing.
public enum ChaosError: Error {
    case networkFailure
    case serviceFailure(component: String)
    case resourceExhaustion
    case invalidFaultConfiguration
}