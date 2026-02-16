import Foundation

/// Compliance standards supported by the system.
public enum ComplianceStandard: String, Codable, Sendable, CaseIterable {
    case soc2 = "SOC2"
    case gdpr = "GDPR"
    case hipaa = "HIPAA"
    case pciDss = "PCI-DSS"
    case iso27001 = "ISO27001"
    case custom = "CUSTOM"

    /// Display name for the compliance standard.
    public var displayName: String {
        switch self {
        case .soc2: return "SOC 2"
        case .gdpr: return "GDPR"
        case .hipaa: return "HIPAA"
        case .pciDss: return "PCI DSS"
        case .iso27001: return "ISO 27001"
        case .custom: return "Custom"
        }
    }

    /// Required compliance tags for this standard.
    public var requiredTags: [String] {
        switch self {
        case .soc2:
            return ["audit", "access_control", "data_integrity", "security"]
        case .gdpr:
            return ["data_protection", "consent", "data_minimization", "retention"]
        case .hipaa:
            return ["phi", "access_control", "audit", "encryption"]
        case .pciDss:
            return ["pci", "encryption", "access_control", "audit"]
        case .iso27001:
            return ["information_security", "risk_management", "access_control"]
        case .custom:
            return ["custom_compliance"]
        }
    }
}

/// Compliance check result.
public struct ComplianceCheck: Codable, Sendable {
    /// Unique identifier for the check.
    public let id: String
    /// Compliance standard being checked.
    public let standard: ComplianceStandard
    /// Name of the check.
    public let name: String
    /// Description of what the check validates.
    public let description: String
    /// Timestamp when the check was performed.
    public let timestamp: Date
    /// Result of the check.
    public let result: ComplianceResult
    /// Details about the check result.
    public let details: String
    /// Severity level.
    public let severity: ComplianceSeverity
    /// Remediation steps if the check failed.
    public let remediation: String?

    public init(
        id: String = UUID().uuidString,
        standard: ComplianceStandard,
        name: String,
        description: String,
        timestamp: Date = Date(),
        result: ComplianceResult,
        details: String,
        severity: ComplianceSeverity,
        remediation: String? = nil
    ) {
        self.id = id
        self.standard = standard
        self.name = name
        self.description = description
        self.timestamp = timestamp
        self.result = result
        self.details = details
        self.severity = severity
        self.remediation = remediation
    }
}

/// Result of a compliance check.
public enum ComplianceResult: String, Codable, Sendable {
    case pass = "PASS"
    case fail = "FAIL"
    case warning = "WARNING"
    case notApplicable = "NOT_APPLICABLE"
}

/// Severity levels for compliance issues.
public enum ComplianceSeverity: String, Codable, Sendable {
    case critical = "CRITICAL"
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case informational = "INFORMATIONAL"
}

/// Compliance report containing multiple checks.
public struct ComplianceReport: Codable, Sendable {
    /// Unique identifier for the report.
    public let id: String
    /// Title of the report.
    public let title: String
    /// Compliance standard covered by this report.
    public let standard: ComplianceStandard
    /// Timestamp when the report was generated.
    public let generatedAt: Date
    /// Period covered by the report.
    public let period: DateInterval
    /// All compliance checks in this report.
    public let checks: [ComplianceCheck]
    /// Overall compliance status.
    public let overallStatus: ComplianceResult
    /// Summary statistics.
    public let summary: ComplianceSummary

    public init(
        id: String = UUID().uuidString,
        title: String,
        standard: ComplianceStandard,
        generatedAt: Date = Date(),
        period: DateInterval,
        checks: [ComplianceCheck]
    ) {
        self.id = id
        self.title = title
        self.standard = standard
        self.generatedAt = generatedAt
        self.period = period
        self.checks = checks

        // Calculate overall status
        let criticalFails = checks.filter { $0.result == .fail && $0.severity == .critical }
        let highFails = checks.filter { $0.result == .fail && $0.severity == .high }

        if !criticalFails.isEmpty {
            self.overallStatus = .fail
        } else if !highFails.isEmpty {
            self.overallStatus = .warning
        } else {
            self.overallStatus = .pass
        }

        // Calculate summary
        let passCount = checks.filter { $0.result == .pass }.count
        let failCount = checks.filter { $0.result == .fail }.count
        let warningCount = checks.filter { $0.result == .warning }.count
        let naCount = checks.filter { $0.result == .notApplicable }.count

        self.summary = ComplianceSummary(
            totalChecks: checks.count,
            passedChecks: passCount,
            failedChecks: failCount,
            warningChecks: warningCount,
            notApplicableChecks: naCount,
            compliancePercentage: Double(passCount) / Double(checks.count - naCount) * 100.0
        )
    }
}

/// Summary statistics for a compliance report.
public struct ComplianceSummary: Codable, Sendable {
    /// Total number of checks performed.
    public let totalChecks: Int
    /// Number of checks that passed.
    public let passedChecks: Int
    /// Number of checks that failed.
    public let failedChecks: Int
    /// Number of checks with warnings.
    public let warningChecks: Int
    /// Number of checks not applicable.
    public let notApplicableChecks: Int
    /// Compliance percentage (0-100).
    public let compliancePercentage: Double
}

/// Protocol for compliance checkers.
public protocol ComplianceChecker: Sendable {
    /// Name of the compliance checker.
    var name: String { get }

    /// Performs compliance checks for the given standard.
    func performChecks(for standard: ComplianceStandard) async throws -> [ComplianceCheck]
}

/// SOC 2 compliance checker.
public actor SOC2ComplianceChecker: ComplianceChecker {
    public let name = "SOC2 Compliance Checker"

    private let auditLogger: any AuditLogStorage

    public init(auditLogger: any AuditLogStorage) {
        self.auditLogger = auditLogger
    }

    public func performChecks(for standard: ComplianceStandard) async throws -> [ComplianceCheck] {
        guard standard == .soc2 else {
            return []
        }

        var checks: [ComplianceCheck] = []

        // Check 1: Audit Logging
        let auditEntries = try await auditLogger.retrieve(
            startDate: Date().addingTimeInterval(-30 * 24 * 3600), // Last 30 days
            endDate: nil,
            actor: nil,
            resource: nil,
            eventType: nil,
            limit: 1000
        )

        let hasAuditLogs = !auditEntries.isEmpty
        checks.append(ComplianceCheck(
            standard: .soc2,
            name: "Audit Logging",
            description: "Verify that audit logging is enabled and capturing security events",
            result: hasAuditLogs ? .pass : .fail,
            details: hasAuditLogs ? "Audit logging is active with \(auditEntries.count) entries" : "No audit entries found",
            severity: .critical,
            remediation: hasAuditLogs ? nil : "Enable audit logging in the configuration"
        ))

        // Check 2: Access Control
        let authEntries = auditEntries.filter { $0.eventType == .authentication }
        let hasAuthAuditing = !authEntries.isEmpty
        checks.append(ComplianceCheck(
            standard: .soc2,
            name: "Access Control Auditing",
            description: "Verify that authentication and authorization events are logged",
            result: hasAuthAuditing ? .pass : .fail,
            details: hasAuthAuditing ? "Authentication auditing active with \(authEntries.count) events" : "No authentication events found",
            severity: .high,
            remediation: hasAuthAuditing ? nil : "Ensure authentication events are being logged"
        ))

        // Check 3: Data Encryption
        let dataAccessEntries = auditEntries.filter { $0.eventType == .dataAccess }
        let hasDataAccessAuditing = !dataAccessEntries.isEmpty
        checks.append(ComplianceCheck(
            standard: .soc2,
            name: "Data Access Auditing",
            description: "Verify that data access operations are logged for security monitoring",
            result: hasDataAccessAuditing ? .pass : .warning,
            details: hasDataAccessAuditing ? "Data access auditing active with \(dataAccessEntries.count) events" : "Limited data access auditing detected",
            severity: .medium,
            remediation: hasDataAccessAuditing ? nil : "Consider enabling more comprehensive data access logging"
        ))

        // Check 4: Security Events
        let securityEntries = auditEntries.filter { $0.eventType == .securityEvent || $0.complianceTags.contains("error") }
        let hasSecurityMonitoring = !securityEntries.isEmpty
        checks.append(ComplianceCheck(
            standard: .soc2,
            name: "Security Event Monitoring",
            description: "Verify that security events and errors are being monitored",
            result: hasSecurityMonitoring ? .pass : .warning,
            details: hasSecurityMonitoring ? "Security monitoring active with \(securityEntries.count) events" : "No security events detected in audit logs",
            severity: .medium,
            remediation: hasSecurityMonitoring ? nil : "Implement security event monitoring and alerting"
        ))

        return checks
    }
}

/// GDPR compliance checker.
public actor GDPRComplianceChecker: ComplianceChecker {
    public let name = "GDPR Compliance Checker"

    private let auditLogger: any AuditLogStorage

    public init(auditLogger: any AuditLogStorage) {
        self.auditLogger = auditLogger
    }

    public func performChecks(for standard: ComplianceStandard) async throws -> [ComplianceCheck] {
        guard standard == .gdpr else {
            return []
        }

        var checks: [ComplianceCheck] = []

        // Check 1: Data Protection
        let dataEntries = try await auditLogger.retrieveForCompliance(
            complianceTags: ["data_protection"],
            startDate: Date().addingTimeInterval(-365 * 24 * 3600), // Last year
            endDate: Date()
        )

        let hasDataProtection = !dataEntries.isEmpty
        checks.append(ComplianceCheck(
            standard: .gdpr,
            name: "Data Protection Measures",
            description: "Verify that data protection measures are implemented and logged",
            result: hasDataProtection ? .pass : .fail,
            details: hasDataProtection ? "Data protection measures active with \(dataEntries.count) logged events" : "No data protection events found",
            severity: .critical,
            remediation: hasDataProtection ? nil : "Implement data protection measures and enable logging"
        ))

        // Check 2: Consent Management
        let consentEntries = try await auditLogger.retrieveForCompliance(
            complianceTags: ["consent"],
            startDate: Date().addingTimeInterval(-365 * 24 * 3600),
            endDate: Date()
        )

        let hasConsentManagement = !consentEntries.isEmpty
        checks.append(ComplianceCheck(
            standard: .gdpr,
            name: "Consent Management",
            description: "Verify that user consent is being tracked and managed",
            result: hasConsentManagement ? .pass : .warning,
            details: hasConsentManagement ? "Consent management active with \(consentEntries.count) events" : "Consent management not detected",
            severity: .high,
            remediation: hasConsentManagement ? nil : "Implement consent management and tracking"
        ))

        // Check 3: Data Retention
        let retentionEntries = try await auditLogger.retrieveForCompliance(
            complianceTags: ["retention"],
            startDate: Date().addingTimeInterval(-365 * 24 * 3600),
            endDate: Date()
        )

        let hasRetentionPolicies = !retentionEntries.isEmpty
        checks.append(ComplianceCheck(
            standard: .gdpr,
            name: "Data Retention Policies",
            description: "Verify that data retention policies are implemented and enforced",
            result: hasRetentionPolicies ? .pass : .fail,
            details: hasRetentionPolicies ? "Retention policies active with \(retentionEntries.count) events" : "No retention policy events found",
            severity: .critical,
            remediation: hasRetentionPolicies ? nil : "Implement data retention policies and automated cleanup"
        ))

        // Check 4: Data Minimization
        let allEntries = try await auditLogger.retrieve(
            startDate: Date().addingTimeInterval(-30 * 24 * 3600),
            endDate: nil,
            actor: nil,
            resource: nil,
            eventType: nil,
            limit: nil
        )

        // Check for excessive data collection patterns
        let dataAccessCount = allEntries.filter { $0.eventType == .dataAccess }.count
        let hasDataMinimization = dataAccessCount < 10000 // Arbitrary threshold for demo
        checks.append(ComplianceCheck(
            standard: .gdpr,
            name: "Data Minimization",
            description: "Verify that data collection is minimized and necessary",
            result: hasDataMinimization ? .pass : .warning,
            details: "Data access operations: \(dataAccessCount) in last 30 days",
            severity: .medium,
            remediation: hasDataMinimization ? nil : "Review data collection practices and minimize unnecessary data access"
        ))

        return checks
    }
}

/// Compliance manager for running checks and generating reports.
public actor ComplianceManager {
    private let checkers: [any ComplianceChecker]
    private let auditLogger: any AuditLogStorage

    public init(auditLogger: any AuditLogStorage) {
        self.auditLogger = auditLogger
        self.checkers = [
            SOC2ComplianceChecker(auditLogger: auditLogger),
            GDPRComplianceChecker(auditLogger: auditLogger)
        ]
    }

    /// Runs compliance checks for the specified standard.
    public func runComplianceChecks(for standard: ComplianceStandard) async throws -> [ComplianceCheck] {
        var allChecks: [ComplianceCheck] = []

        for checker in checkers {
            let checks = try await checker.performChecks(for: standard)
            allChecks.append(contentsOf: checks)
        }

        return allChecks
    }

    /// Generates a compliance report for the specified standard and period.
    public func generateComplianceReport(
        for standard: ComplianceStandard,
        title: String,
        period: DateInterval
    ) async throws -> ComplianceReport {
        let checks = try await runComplianceChecks(for: standard)
        return ComplianceReport(
            title: title,
            standard: standard,
            period: period,
            checks: checks
        )
    }

    /// Runs compliance checks for all supported standards.
    public func runAllComplianceChecks() async throws -> [ComplianceStandard: [ComplianceCheck]] {
        var results: [ComplianceStandard: [ComplianceCheck]] = [:]

        for standard in ComplianceStandard.allCases {
            let checks = try await runComplianceChecks(for: standard)
            if !checks.isEmpty {
                results[standard] = checks
            }
        }

        return results
    }
}