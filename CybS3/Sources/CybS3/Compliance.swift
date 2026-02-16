import ArgumentParser
import CybS3Lib
import Foundation

/// Compliance and audit management commands.
struct Compliance: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compliance",
        abstract: "Compliance auditing and reporting for enterprise standards",
        subcommands: [
            Check.self,
            Report.self,
            Audit.self,
            Retention.self,
        ]
    )
}

extension Compliance {
    /// Run compliance checks for specified standards.
    struct Check: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "check",
            abstract: "Run compliance checks for SOC2, GDPR, HIPAA, and other standards"
        )

        @Option(name: .shortAndLong, help: "Compliance standard to check (soc2, gdpr, hipaa, pci-dss, iso27001)")
        var standard: String?

        @Flag(name: .long, help: "Run checks for all supported standards")
        var all: Bool = false

        @Option(name: .shortAndLong, help: "Output format (text, json)")
        var format: String = "text"

        func run() async throws {
            ConsoleUI.header("Compliance Checks")

            let auditLogger = try FileAuditLogStorage(
                logDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("cybs3")
                    .appendingPathComponent("audit")
            )

            let complianceManager = ComplianceManager(auditLogger: auditLogger)

            var standardsToCheck: [ComplianceStandard] = []

            if all {
                standardsToCheck = ComplianceStandard.allCases.filter { $0 != .custom }
            } else if let standardStr = standard {
                guard let standard = ComplianceStandard(rawValue: standardStr.uppercased()) else {
                    ConsoleUI.error("Unknown compliance standard: \(standardStr)")
                    ConsoleUI.info("Supported standards: soc2, gdpr, hipaa, pci-dss, iso27001")
                    return
                }
                standardsToCheck = [standard]
            } else {
                // Default to SOC2 if no standard specified
                standardsToCheck = [.soc2]
            }

            for standard in standardsToCheck {
                ConsoleUI.info("Running \(standard.displayName) compliance checks...")

                do {
                    let checks = try await complianceManager.runComplianceChecks(for: standard)

                    if format == "json" {
                        let jsonData = try JSONEncoder().encode(checks)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            print(jsonString)
                        }
                    } else {
                        displayTextResults(checks, for: standard)
                    }
                } catch {
                    ConsoleUI.error("Failed to run \(standard.displayName) checks: \(error.localizedDescription)")
                }

                print() // Add spacing between standards
            }
        }

        private func displayTextResults(_ checks: [ComplianceCheck], for standard: ComplianceStandard) {
            ConsoleUI.success("\(standard.displayName) Compliance Results:")

            let passed = checks.filter { $0.result == .pass }
            let failed = checks.filter { $0.result == .fail }
            let warnings = checks.filter { $0.result == .warning }

            ConsoleUI.info("✅ Passed: \(passed.count)")
            ConsoleUI.info("❌ Failed: \(failed.count)")
            ConsoleUI.info("⚠️  Warnings: \(warnings.count)")

            if !failed.isEmpty {
                ConsoleUI.error("\nFailed Checks:")
                for check in failed {
                    ConsoleUI.error("  • \(check.name): \(check.details)")
                    if let remediation = check.remediation {
                        ConsoleUI.info("    💡 \(remediation)")
                    }
                }
            }

            if !warnings.isEmpty {
                ConsoleUI.warning("\nWarnings:")
                for check in warnings {
                    ConsoleUI.warning("  • \(check.name): \(check.details)")
                }
            }
        }
    }

    /// Generate compliance reports.
    struct Report: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "report",
            abstract: "Generate detailed compliance reports for audit and certification"
        )

        @Option(name: .shortAndLong, help: "Compliance standard (soc2, gdpr, hipaa, pci-dss, iso27001)")
        var standard: String

        @Option(name: .long, help: "Report title")
        var title: String?

        @Option(name: .long, help: "Report period in days (default: 30)")
        var period: Int = 30

        @Option(name: .shortAndLong, help: "Output format (text, json, html)")
        var format: String = "text"

        @Option(name: .shortAndLong, help: "Output file path")
        var output: String?

        func run() async throws {
            ConsoleUI.header("Compliance Report Generation")

            guard let complianceStandard = ComplianceStandard(rawValue: standard.uppercased()) else {
                ConsoleUI.error("Unknown compliance standard: \(standard)")
                ConsoleUI.info("Supported standards: soc2, gdpr, hipaa, pci-dss, iso27001")
                return
            }

            let auditLogger = try FileAuditLogStorage(
                logDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("cybs3")
                    .appendingPathComponent("audit")
            )

            let complianceManager = ComplianceManager(auditLogger: auditLogger)

            let reportTitle = title ?? "\(complianceStandard.displayName) Compliance Report"
            let endDate = Date()
            let startDate = endDate.addingTimeInterval(-Double(period) * 24 * 3600)
            let period = DateInterval(start: startDate, end: endDate)

            ConsoleUI.info("Generating \(complianceStandard.displayName) report for last \(period) days...")

            do {
                let report = try await complianceManager.generateComplianceReport(
                    for: complianceStandard,
                    title: reportTitle,
                    period: period
                )

                if format == "json" {
                    let jsonData = try JSONEncoder().encode(report)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        if let outputPath = output {
                            try jsonString.write(toFile: outputPath, atomically: true, encoding: .utf8)
                            ConsoleUI.success("Report saved to: \(outputPath)")
                        } else {
                            print(jsonString)
                        }
                    }
                } else if format == "html" {
                    let html = generateHTMLReport(report)
                    if let outputPath = output {
                        try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
                        ConsoleUI.success("HTML report saved to: \(outputPath)")
                    } else {
                        print(html)
                    }
                } else {
                    displayTextReport(report)
                }
            } catch {
                ConsoleUI.error("Failed to generate compliance report: \(error.localizedDescription)")
            }
        }

        private func displayTextReport(_ report: ComplianceReport) {
            ConsoleUI.success("📋 \(report.title)")
            ConsoleUI.info("Standard: \(report.standard.displayName)")
            ConsoleUI.info("Period: \(report.period.start.formatted()) - \(report.period.end.formatted())")
            ConsoleUI.info("Generated: \(report.generatedAt.formatted())")

            print("\n📊 Summary:")
            ConsoleUI.info("Total Checks: \(report.summary.totalChecks)")
            ConsoleUI.info("Passed: \(report.summary.passedChecks)")
            ConsoleUI.info("Failed: \(report.summary.failedChecks)")
            ConsoleUI.info("Warnings: \(report.summary.warningChecks)")
            ConsoleUI.info("Compliance: \(String(format: "%.1f", report.summary.compliancePercentage))%")

            let status = report.overallStatus
            switch status {
            case .pass:
                ConsoleUI.success("Overall Status: ✅ COMPLIANT")
            case .fail:
                ConsoleUI.error("Overall Status: ❌ NON-COMPLIANT")
            case .warning:
                ConsoleUI.warning("Overall Status: ⚠️ REQUIRES ATTENTION")
            case .notApplicable:
                ConsoleUI.info("Overall Status: ℹ️ NOT APPLICABLE")
            }

            if !report.checks.filter({ $0.result == .fail }).isEmpty {
                print("\n❌ Failed Checks:")
                for check in report.checks.filter({ $0.result == .fail }) {
                    ConsoleUI.error("• \(check.name): \(check.details)")
                    if let remediation = check.remediation {
                        ConsoleUI.info("  💡 \(remediation)")
                    }
                }
            }
        }

        private func generateHTMLReport(_ report: ComplianceReport) -> String {
            return """
            <!DOCTYPE html>
            <html>
            <head>
                <title>\(report.title)</title>
                <style>
                    body { font-family: Arial, sans-serif; margin: 40px; }
                    .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
                    .summary { background: #e8f4f8; padding: 15px; margin: 20px 0; border-radius: 5px; }
                    .checks { margin: 20px 0; }
                    .check { margin: 10px 0; padding: 10px; border-left: 4px solid; }
                    .pass { border-color: #28a745; background: #d4edda; }
                    .fail { border-color: #dc3545; background: #f8d7da; }
                    .warning { border-color: #ffc107; background: #fff3cd; }
                </style>
            </head>
            <body>
                <div class="header">
                    <h1>\(report.title)</h1>
                    <p><strong>Standard:</strong> \(report.standard.displayName)</p>
                    <p><strong>Period:</strong> \(report.period.start.formatted()) - \(report.period.end.formatted())</p>
                    <p><strong>Generated:</strong> \(report.generatedAt.formatted())</p>
                </div>

                <div class="summary">
                    <h2>Summary</h2>
                    <p>Total Checks: \(report.summary.totalChecks)</p>
                    <p>Passed: \(report.summary.passedChecks)</p>
                    <p>Failed: \(report.summary.failedChecks)</p>
                    <p>Warnings: \(report.summary.warningChecks)</p>
                    <p>Compliance: \(String(format: "%.1f", report.summary.compliancePercentage))%</p>
                    <p><strong>Overall Status: \(report.overallStatus.rawValue.uppercased())</strong></p>
                </div>

                <div class="checks">
                    <h2>Detailed Results</h2>
                    \(report.checks.map { check in
                        let cssClass = check.result.rawValue.lowercased()
                        return """
                        <div class="check \(cssClass)">
                            <h3>\(check.name)</h3>
                            <p><strong>Severity:</strong> \(check.severity.rawValue.uppercased())</p>
                            <p><strong>Result:</strong> \(check.result.rawValue.uppercased())</p>
                            <p>\(check.description)</p>
                            <p><em>\(check.details)</em></p>
                            \(check.remediation.map { "<p><strong>Remediation:</strong> \($0)</p>" } ?? "")
                        </div>
                        """
                    }.joined())
                </div>
            </body>
            </html>
            """
        }
    }

    /// Query and manage audit logs.
    struct Audit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "audit",
            abstract: "Query and manage audit logs for compliance and security"
        )

        @Option(name: .long, help: "Filter by actor")
        var actor: String?

        @Option(name: .long, help: "Filter by resource")
        var resource: String?

        @Option(name: .long, help: "Filter by event type")
        var eventType: String?

        @Option(name: .long, help: "Start date (YYYY-MM-DD)")
        var startDate: String?

        @Option(name: .long, help: "End date (YYYY-MM-DD)")
        var endDate: String?

        @Option(name: .long, help: "Maximum number of results")
        var limit: Int = 100

        @Option(name: .shortAndLong, help: "Output format (text, json)")
        var format: String = "text"

        func run() async throws {
            ConsoleUI.header("Audit Log Query")

            let auditLogger = try FileAuditLogStorage(
                logDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("cybs3")
                    .appendingPathComponent("audit")
            )

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            let start = startDate.flatMap { dateFormatter.date(from: $0) }
            let end = endDate.flatMap { dateFormatter.date(from: $0) }

            let eventTypeEnum = eventType.flatMap { AuditEventType(rawValue: $0) }

            ConsoleUI.info("Querying audit logs...")

            do {
                let entries = try await auditLogger.retrieve(
                    startDate: start,
                    endDate: end,
                    actor: actor,
                    resource: resource,
                    eventType: eventTypeEnum,
                    limit: limit
                )

                if format == "json" {
                    let jsonData = try JSONEncoder().encode(entries)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    displayTextResults(entries)
                }
            } catch {
                ConsoleUI.error("Failed to query audit logs: \(error.localizedDescription)")
            }
        }

        private func displayTextResults(_ entries: [AuditLogEntry]) {
            if entries.isEmpty {
                ConsoleUI.info("No audit entries found matching the criteria.")
                return
            }

            ConsoleUI.success("Found \(entries.count) audit entries:")

            for entry in entries {
                let timestamp = entry.timestamp.formatted(date: .abbreviated, time: .shortened)
                let status = entry.eventType == .operationFailed ? "❌" :
                           entry.eventType == .securityEvent ? "🔒" : "📝"

                print("\(status) [\(timestamp)] \(entry.eventType.rawValue.uppercased())")
                print("   Actor: \(entry.actor)")
                print("   Resource: \(entry.resource)")
                print("   Action: \(entry.action)")
                print("   Result: \(entry.result)")
                if !entry.metadata.isEmpty {
                    print("   Metadata: \(entry.metadata)")
                }
                if !entry.complianceTags.isEmpty {
                    print("   Compliance: \(entry.complianceTags.joined(separator: ", "))")
                }
                print()
            }
        }
    }

    /// Manage data retention policies.
    struct Retention: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "retention",
            abstract: "Manage data retention policies and lifecycle rules"
        )

        @Option(name: .long, help: "Retention policy name")
        var name: String?

        @Flag(name: .long, help: "List all retention policies")
        var list: Bool = false

        @Flag(name: .long, help: "Apply retention policies to clean up expired data")
        var apply: Bool = false

        func run() async throws {
            ConsoleUI.header("Data Retention Management")

            let auditLogger = try FileAuditLogStorage(
                logDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("cybs3")
                    .appendingPathComponent("audit")
            )

            // Use standard retention policies
            let policies = [
                StandardRetentionPolicies.soc2,
                StandardRetentionPolicies.gdpr,
                StandardRetentionPolicies.hipaa,
                StandardRetentionPolicies.auditLogs
            ]

            let lifecycleManager = DefaultLifecycleManager(policies: policies, auditLogger: auditLogger)

            if list {
                ConsoleUI.info("Available Retention Policies:")
                for policy in policies {
                    print("📋 \(policy.name)")
                    print("   Description: \(policy.description)")
                    print("   Standards: \(policy.complianceStandards.map { $0.displayName }.joined(separator: ", "))")
                    print("   Active: \(policy.isActive ? "✅" : "❌")")
                    print("   Rules:")
                    for rule in policy.rules {
                        let retentionDays = Int(rule.retentionPeriod / (24 * 3600))
                        print("     • \(rule.applicableTags.isEmpty ? "All data" : rule.applicableTags.joined(separator: ", ")): \(retentionDays) days (\(rule.action.rawValue))")
                    }
                    print()
                }
            } else if apply {
                ConsoleUI.info("Applying retention policies...")

                do {
                    let summary = try await lifecycleManager.applyRetentionPolicies()

                    ConsoleUI.success("Retention policy application completed:")
                    ConsoleUI.info("Items checked: \(summary.itemsChecked)")
                    ConsoleUI.info("Items expired: \(summary.itemsExpired)")
                    ConsoleUI.info("Items archived: \(summary.itemsArchived)")
                    ConsoleUI.info("Items deleted: \(summary.itemsDeleted)")
                    ConsoleUI.info("Total size processed: \(ByteCountFormatter.string(fromByteCount: summary.totalSizeProcessed, countStyle: .file))")

                    if !summary.errors.isEmpty {
                        ConsoleUI.warning("Errors encountered:")
                        for error in summary.errors {
                            ConsoleUI.error("  • \(error)")
                        }
                    }
                } catch {
                    ConsoleUI.error("Failed to apply retention policies: \(error.localizedDescription)")
                }
            } else {
                ConsoleUI.info("Use --list to view policies or --apply to execute retention cleanup")
            }
        }
    }
}