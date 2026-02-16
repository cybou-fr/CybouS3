import XCTest
@testable import CybS3Lib

final class ComplianceTests: XCTestCase {
    var auditLogger: MemoryAuditLogStorage!

    override func setUp() {
        super.setUp()
        auditLogger = MemoryAuditLogStorage()
    }

    override func tearDown() {
        auditLogger = nil
        super.tearDown()
    }

    func testComplianceStandards() {
        XCTAssertEqual(ComplianceStandard.soc2.displayName, "SOC 2")
        XCTAssertEqual(ComplianceStandard.gdpr.displayName, "GDPR")
        XCTAssertEqual(ComplianceStandard.hipaa.displayName, "HIPAA")
    }

    func testComplianceCheckCreation() {
        let check = ComplianceCheck(
            standard: .soc2,
            name: "Test Check",
            description: "A test compliance check",
            result: .pass,
            details: "Check passed successfully",
            severity: .high
        )

        XCTAssertEqual(check.standard, .soc2)
        XCTAssertEqual(check.name, "Test Check")
        XCTAssertEqual(check.result, .pass)
        XCTAssertEqual(check.severity, .high)
    }

    func testComplianceReportGeneration() {
        let checks = [
            ComplianceCheck(
                standard: .soc2,
                name: "Audit Logging",
                description: "Verify audit logging is enabled",
                result: .pass,
                details: "Audit logging is active",
                severity: .critical
            ),
            ComplianceCheck(
                standard: .soc2,
                name: "Access Control",
                description: "Verify access controls are in place",
                result: .fail,
                details: "Access control check failed",
                severity: .high,
                remediation: "Enable access control policies"
            )
        ]

        let period = DateInterval(start: Date().addingTimeInterval(-86400), end: Date())
        let report = ComplianceReport(
            title: "Test SOC2 Report",
            standard: .soc2,
            period: period,
            checks: checks
        )

        XCTAssertEqual(report.title, "Test SOC2 Report")
        XCTAssertEqual(report.standard, .soc2)
        XCTAssertEqual(report.checks.count, 2)
        XCTAssertEqual(report.summary.totalChecks, 2)
        XCTAssertEqual(report.summary.passedChecks, 1)
        XCTAssertEqual(report.summary.failedChecks, 1)
        XCTAssertEqual(report.overallStatus, .fail) // Critical check failed
    }

    func testRetentionPolicy() {
        let policy = RetentionPolicy(
            name: "Test Policy",
            description: "A test retention policy",
            rules: [
                RetentionRule(
                    applicableTags: ["audit"],
                    retentionPeriod: 365 * 24 * 3600, // 1 year
                    action: .delete
                )
            ]
        )

        // Test data that's within retention period
        XCTAssertTrue(policy.shouldRetain(dataAge: 30 * 24 * 3600, dataTags: ["audit"])) // 30 days

        // Test data that's beyond retention period
        XCTAssertFalse(policy.shouldRetain(dataAge: 400 * 24 * 3600, dataTags: ["audit"])) // 400 days

        // Test data with different tags
        XCTAssertTrue(policy.shouldRetain(dataAge: 400 * 24 * 3600, dataTags: ["other"])) // Should retain (no matching rule)
    }

    func testStandardRetentionPolicies() {
        let soc2Policy = StandardRetentionPolicies.soc2
        XCTAssertEqual(soc2Policy.name, "SOC 2 Compliance")
        XCTAssertTrue(soc2Policy.complianceStandards.contains(.soc2))

        let gdprPolicy = StandardRetentionPolicies.gdpr
        XCTAssertEqual(gdprPolicy.name, "GDPR Compliance")
        XCTAssertTrue(gdprPolicy.complianceStandards.contains(.gdpr))
    }

    func testAuditLogEntryCreation() {
        let entry = AuditLogEntry.operationStart(
            actor: "test-user",
            resource: "test-bucket/file.txt",
            action: "upload",
            source: "127.0.0.1",
            metadata: ["size": "1024"]
        )

        XCTAssertEqual(entry.eventType, .operationStart)
        XCTAssertEqual(entry.actor, "test-user")
        XCTAssertEqual(entry.resource, "test-bucket/file.txt")
        XCTAssertEqual(entry.action, "upload")
        XCTAssertEqual(entry.result, "started")
        XCTAssertEqual(entry.metadata["size"], "1024")
        XCTAssertEqual(entry.source, "127.0.0.1")
    }

    func testAuditLoggerStorage() async throws {
        let entry = AuditLogEntry(
            eventType: .authentication,
            actor: "test-user",
            resource: "login",
            action: "login",
            result: "success",
            source: "127.0.0.1"
        )

        try await auditLogger.store(entry)

        let retrieved = try await auditLogger.retrieve(
            startDate: nil,
            endDate: nil,
            actor: "test-user",
            resource: nil,
            eventType: nil,
            limit: 10
        )

        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved[0].actor, "test-user")
        XCTAssertEqual(retrieved[0].eventType, .authentication)
    }

    func testComplianceManager() async throws {
        let manager = ComplianceManager(auditLogger: auditLogger)

        // Add some test audit entries
        let entries = [
            AuditLogEntry(
                eventType: .authentication,
                actor: "user1",
                resource: "login",
                action: "login",
                result: "success",
                source: "127.0.0.1"
            ),
            AuditLogEntry(
                eventType: .dataAccess,
                actor: "user1",
                resource: "bucket/file.txt",
                action: "download",
                result: "success",
                source: "127.0.0.1",
                complianceTags: ["data_access"]
            )
        ]

        for entry in entries {
            try await auditLogger.store(entry)
        }

        // Run SOC2 compliance checks
        let checks = try await manager.runComplianceChecks(for: .soc2)

        // Should have multiple checks
        XCTAssertGreaterThan(checks.count, 0)

        // Generate a report
        let period = DateInterval(start: Date().addingTimeInterval(-86400), end: Date())
        let report = try await manager.generateComplianceReport(
            for: .soc2,
            title: "Test Report",
            period: period
        )

        XCTAssertEqual(report.standard, .soc2)
        XCTAssertEqual(report.title, "Test Report")
        XCTAssertGreaterThanOrEqual(report.checks.count, checks.count)
    }
}