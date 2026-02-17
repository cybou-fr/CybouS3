import ArgumentParser
import CybS3Lib
import Foundation

/// Command to perform system health checks.
struct Health: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "Perform system health checks",
        subcommands: [Check.self, Ecosystem.self]
    )

    struct Check: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "check",
            abstract: "Run comprehensive system diagnostics"
        )

        @Option(name: .long, help: "Check specific component (encryption, network, storage)")
        var component: String?

        @Flag(name: .long, help: "Verbose output")
        var verbose: Bool = false

        func run() async throws {
            print("🔍 Performing CybS3 health check...")

            let status = await HealthChecker.performHealthCheck()

            print("\n\(status.description)")

            if verbose || !status.isHealthy {
                print("\n📊 Details:")
                switch status {
                case .healthy(let details):
                    for (component, info) in details.sorted(by: { $0.key < $1.key }) {
                        print("  ✅ \(component): \(info)")
                    }
                case .degraded(let details, let issues), .unhealthy(let details, let issues):
                    for (component, info) in details.sorted(by: { $0.key < $1.key }) {
                        print("  📋 \(component): \(info)")
                    }
                    if !issues.isEmpty {
                        print("\n⚠️ Issues found:")
                        for issue in issues {
                            print("  • \(issue)")
                        }
                    }
                }
            }

            print("\n💡 For more information, run with --verbose")
        }
    }

    struct Ecosystem: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ecosystem",
            abstract: "Check unified ecosystem health across CybS3 and SwiftS3"
        )

        @Flag(name: .long, help: "Include detailed performance metrics")
        var detailed: Bool = false

        func run() async throws {
            print("🔍 Performing unified ecosystem health check...")

            let ecosystemHealth = await EcosystemMonitor.checkCrossComponentHealth()

            print("\n" + ecosystemHealth.description)

            if detailed {
                print("\n📊 Detailed Ecosystem Report:")
                let report = await EcosystemMonitor.generateUnifiedReport()
                print("\n" + report.summary)
            }

            if !ecosystemHealth.overallStatus.isHealthy {
                print("\n❌ Ecosystem health issues detected")
                throw ExitCode.failure
            } else {
                print("\n✅ Ecosystem is healthy")
            }
        }
    }
}
