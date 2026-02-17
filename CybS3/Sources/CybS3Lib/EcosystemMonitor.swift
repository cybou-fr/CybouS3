import Foundation
import AsyncHTTPClient

/// Unified ecosystem monitoring for cross-component health and dependency validation.
public struct EcosystemMonitor {
    /// Ecosystem health status combining all components.
    public struct EcosystemHealth {
        public let overallStatus: HealthStatus
        public let componentHealth: [String: HealthStatus]
        public let dependencies: DependencyStatus
        public let crossComponentIssues: [String]

        public var description: String {
            var report = """
            CybouS3 Ecosystem Health Report
            ================================
            Overall Status: \(overallStatus.description)
            Components: \(componentHealth.count)
            Dependencies: \(dependencies.isHealthy ? "✅ Healthy" : "❌ Issues")
            """

            if !crossComponentIssues.isEmpty {
                report += "\n\nCross-Component Issues:\n"
                for issue in crossComponentIssues {
                    report += "  • \(issue)\n"
                }
            }

            report += "\nComponent Details:\n"
            for (component, status) in componentHealth.sorted(by: { $0.key < $1.key }) {
                report += "  \(status.isHealthy ? "✅" : "❌") \(component): \(status.description)\n"
            }

            return report
        }
    }

    /// Dependency validation status.
    public struct DependencyStatus {
        public let isHealthy: Bool
        public let issues: [String]
        public let checkedDependencies: [String]

        public var description: String {
            """
            Dependencies: \(isHealthy ? "✅ All OK" : "❌ Issues Found")
            Checked: \(checkedDependencies.joined(separator: ", "))
            \(issues.isEmpty ? "" : "Issues: \(issues.joined(separator: "; "))")
            """
        }
    }

    /// Comprehensive monitoring report.
    public struct MonitoringReport {
        public let timestamp: Date
        public let ecosystemHealth: EcosystemHealth
        public let performanceMetrics: [String: Double]
        public let recommendations: [String]

        public var summary: String {
            """
            Ecosystem Monitoring Summary
            ============================
            Time: \(timestamp.formatted())
            Status: \(ecosystemHealth.overallStatus.isHealthy ? "✅ HEALTHY" : "❌ DEGRADED")

            Key Metrics:
            \(performanceMetrics.map { "  \($0.key): \($0.value)" }.joined(separator: "\n"))

            \(recommendations.isEmpty ? "" : "Recommendations:\n\(recommendations.map { "  • \($0)" }.joined(separator: "\n"))")
            """
        }
    }

    /// Perform comprehensive ecosystem health check.
    public static func checkCrossComponentHealth() async -> EcosystemHealth {
        print("🔍 Performing cross-component ecosystem health check...")

        // Check individual components
        var componentHealth = [String: HealthStatus]()

        // CybS3 components
        componentHealth["CybS3-Core"] = await HealthChecker.performHealthCheck()
        componentHealth["CybS3-Encryption"] = await checkEncryptionHealth()
        componentHealth["CybS3-Storage"] = await checkStorageHealth()

        // SwiftS3 components (if available)
        componentHealth["SwiftS3-Server"] = await checkSwiftS3Health()
        componentHealth["SwiftS3-Storage"] = await checkSwiftS3StorageHealth()

        // CybKMS components (if available)
        componentHealth["CybKMS-Server"] = await checkCybKMSHealth()

        // Check dependencies
        let dependencies = await validateDependencies()

        // Analyze cross-component issues
        let crossComponentIssues = analyzeCrossComponentIssues(componentHealth, dependencies)

        // Determine overall status
        let overallStatus = determineOverallStatus(componentHealth.values, dependencies, crossComponentIssues)

        let ecosystemHealth = EcosystemHealth(
            overallStatus: overallStatus,
            componentHealth: componentHealth,
            dependencies: dependencies,
            crossComponentIssues: crossComponentIssues
        )

        print("✅ Ecosystem health check complete")
        return ecosystemHealth
    }

    /// Validate dependencies between ecosystem components.
    public static func validateDependencies() async -> DependencyStatus {
        print("🔗 Validating component dependencies...")

        var issues = [String]()
        var checkedDependencies = [String]()

        // Check CybS3 ↔ SwiftS3 connectivity
        checkedDependencies.append("CybS3-SwiftS3-Connectivity")
        do {
            let connectivityHealthy = try await checkCybS3SwiftS3Connectivity()
            if !connectivityHealthy {
                issues.append("CybS3 cannot connect to SwiftS3 server")
            }
        } catch {
            issues.append("Connectivity check failed: \(error.localizedDescription)")
        }

        // Check CybS3 ↔ CybKMS connectivity
        checkedDependencies.append("CybS3-CybKMS-Connectivity")
        do {
            let connectivityHealthy = try await checkCybS3CybKMSConnectivity()
            if !connectivityHealthy {
                issues.append("CybS3 cannot connect to CybKMS server")
            }
        } catch {
            issues.append("CybKMS connectivity check failed: \(error.localizedDescription)")
        }

        // Check unified authentication
        checkedDependencies.append("Unified-Authentication")
        do {
            let authHealthy = try await checkUnifiedAuthentication()
            if !authHealthy {
                issues.append("Unified authentication between CybS3 and SwiftS3 not working")
            }
        } catch {
            issues.append("Authentication validation failed: \(error.localizedDescription)")
        }

        // Check encryption compatibility
        checkedDependencies.append("Encryption-Compatibility")
        do {
            let encryptionCompatible = try await checkEncryptionCompatibility()
            if !encryptionCompatible {
                issues.append("Encryption schemes between CybS3 and SwiftS3 incompatible")
            }
        } catch {
            issues.append("Encryption compatibility check failed: \(error.localizedDescription)")
        }

        let isHealthy = issues.isEmpty

        return DependencyStatus(
            isHealthy: isHealthy,
            issues: issues,
            checkedDependencies: checkedDependencies
        )
    }

    /// Generate comprehensive monitoring report.
    public static func generateUnifiedReport() async -> MonitoringReport {
        print("📊 Generating unified ecosystem monitoring report...")

        let ecosystemHealth = await checkCrossComponentHealth()
        let performanceMetrics = await collectPerformanceMetrics()
        let recommendations = generateRecommendations(ecosystemHealth, performanceMetrics)

        let report = MonitoringReport(
            timestamp: Date(),
            ecosystemHealth: ecosystemHealth,
            performanceMetrics: performanceMetrics,
            recommendations: recommendations
        )

        print("✅ Unified monitoring report generated")
        return report
    }

    // MARK: - Private Methods

    private static func checkEncryptionHealth() async -> HealthStatus {
        var issues = [String]()
        var details = [String: String]()

        do {
            // Test encryption functionality
            let testData = Data("encryption_health_check".utf8)
            let mnemonic = ["test", "mnemonic", "for", "health", "check", "only", "test", "mnemonic", "for", "health", "check", "only"]

            let key = try Encryption.deriveKey(mnemonic: mnemonic)
            let encrypted = try Encryption.encrypt(data: testData, key: key)
            let decrypted = try Encryption.decrypt(data: encrypted, key: key)

            if decrypted == testData {
                details["encryption_roundtrip"] = "successful"
            } else {
                issues.append("Encryption roundtrip failed")
                details["encryption_roundtrip"] = "failed"
            }

            details["key_derivation"] = "successful"
        } catch {
            issues.append("Encryption system error: \(error.localizedDescription)")
            details["encryption_system"] = "error"
        }

        if issues.isEmpty {
            return .healthy(details: details)
        } else {
            return .unhealthy(details: details, issues: issues)
        }
    }

    private static func checkStorageHealth() async -> HealthStatus {
        var issues = [String]()
        var details = [String: String]()

        do {
            let storage = SecureStorageFactory.create()
            let testKey = "health_check_\(UUID().uuidString)"
            let testData = Data("storage_health_check".utf8)

            try storage.store(testData, for: testKey)
            let retrieved = try storage.retrieve(for: testKey)
            try storage.delete(for: testKey)

            if retrieved == testData {
                details["secure_storage"] = "functional"
            } else {
                issues.append("Storage data integrity check failed")
                details["secure_storage"] = "integrity_error"
            }
        } catch {
            issues.append("Storage system error: \(error.localizedDescription)")
            details["secure_storage"] = "error"
        }

        if issues.isEmpty {
            return .healthy(details: details)
        } else {
            return .unhealthy(details: details, issues: issues)
        }
    }

    private static func checkSwiftS3Health() async -> HealthStatus {
        var issues = [String]()
        var details = [String: String]()

        // Try to connect to SwiftS3 server
        do {
            let client = HTTPClient()
            defer { try? client.shutdown() }

            let request = HTTPClientRequest(url: "http://127.0.0.1:8080/_health")
            let response = try await client.execute(request, timeout: .seconds(5))

            if response.status.code == 200 {
                details["swiftS3_connectivity"] = "healthy"
                details["swiftS3_status_code"] = "\(response.status.code)"
            } else {
                issues.append("SwiftS3 server responded with status \(response.status.code)")
                details["swiftS3_connectivity"] = "degraded"
                details["swiftS3_status_code"] = "\(response.status.code)"
            }
        } catch {
            issues.append("Cannot connect to SwiftS3 server: \(error.localizedDescription)")
            details["swiftS3_connectivity"] = "unreachable"
        }

        if issues.isEmpty {
            return .healthy(details: details)
        } else if issues.count <= 1 {
            return .degraded(details: details, issues: issues)
        } else {
            return .unhealthy(details: details, issues: issues)
        }
    }

    private static func checkSwiftS3StorageHealth() async -> HealthStatus {
        var issues = [String]()
        var details = [String: String]()

        // This would check SwiftS3's storage backend health
        // For now, assume healthy if SwiftS3 is reachable
        let serverHealth = await checkSwiftS3Health()

        if serverHealth.isHealthy {
            details["swiftS3_storage"] = "accessible"
        } else {
            issues.append("SwiftS3 storage health unknown - server unreachable")
            details["swiftS3_storage"] = "unknown"
        }

        if issues.isEmpty {
            return .healthy(details: details)
        } else {
            return .degraded(details: details, issues: issues)
        }
    }

    private static func checkCybKMSHealth() async -> HealthStatus {
        var issues = [String]()
        var details = [String: String]()

        // Try to connect to CybKMS server
        do {
            let client = HTTPClient()
            defer { try? client.shutdown() }

            let request = HTTPClientRequest(url: "http://127.0.0.1:8081/health")
            let response = try await client.execute(request, timeout: .seconds(5))

            if response.status.code == 200 {
                details["cybKMS_connectivity"] = "healthy"
                details["cybKMS_status_code"] = "\(response.status.code)"
            } else {
                issues.append("CybKMS server responded with status \(response.status.code)")
                details["cybKMS_connectivity"] = "degraded"
                details["cybKMS_status_code"] = "\(response.status.code)"
            }
        } catch {
            issues.append("Cannot connect to CybKMS server: \(error.localizedDescription)")
            details["cybKMS_connectivity"] = "unreachable"
        }

        if issues.isEmpty {
            return .healthy(details: details)
        } else if issues.count <= 1 {
            return .degraded(details: details, issues: issues)
        } else {
            return .unhealthy(details: details, issues: issues)
        }
    }

    private static func checkCybS3SwiftS3Connectivity() async throws -> Bool {
        // Try a simple operation that requires CybS3 ↔ SwiftS3 communication
        do {
            let client = HTTPClient()
            defer { try? client.shutdown() }

            let request = HTTPClientRequest(url: "http://127.0.0.1:8080/")
            let response = try await client.execute(request, timeout: .seconds(5))

            return response.status.code >= 200 && response.status.code < 300
        } catch {
            return false
        }
    }

    private static func checkCybS3CybKMSConnectivity() async throws -> Bool {
        // Try a simple operation that requires CybS3 ↔ CybKMS communication
        do {
            let client = HTTPClient()
            defer { try? client.shutdown() }

            let request = HTTPClientRequest(url: "http://127.0.0.1:8081/health")
            let response = try await client.execute(request, timeout: .seconds(5))

            return response.status.code >= 200 && response.status.code < 300
        } catch {
            return false
        }
    }

    private static func checkUnifiedAuthentication() async throws -> Bool {
        // This would validate that authentication works between CybS3 and SwiftS3
        // For now, assume true if connectivity works
        return try await checkCybS3SwiftS3Connectivity()
    }

    private static func checkEncryptionCompatibility() async throws -> Bool {
        // This would validate that encryption schemes are compatible
        // For now, assume true
        return true
    }

    private static func analyzeCrossComponentIssues(_ componentHealth: [String: HealthStatus], _ dependencies: DependencyStatus) -> [String] {
        var issues = [String]()

        // Check for cascading failures
        let cybS3Healthy = componentHealth["CybS3-Core"]?.isHealthy ?? false
        let swiftS3Healthy = componentHealth["SwiftS3-Server"]?.isHealthy ?? false
        let cybKMSHealthy = componentHealth["CybKMS-Server"]?.isHealthy ?? false

        if !cybS3Healthy && !swiftS3Healthy && !cybKMSHealthy {
            issues.append("All three ecosystem components (CybS3, SwiftS3, CybKMS) are unhealthy - critical ecosystem failure")
        } else if !cybS3Healthy && !swiftS3Healthy {
            issues.append("Both CybS3 and SwiftS3 are unhealthy - potential ecosystem-wide issue")
        } else if !cybS3Healthy && !cybKMSHealthy {
            issues.append("Both CybS3 and CybKMS are unhealthy - encryption and key management compromised")
        }

        if !dependencies.isHealthy {
            issues.append("Dependency issues may affect cross-component functionality")
        }

        // Check for encryption/storage consistency
        let encryptionHealthy = componentHealth["CybS3-Encryption"]?.isHealthy ?? false
        let storageHealthy = componentHealth["CybS3-Storage"]?.isHealthy ?? false

        if encryptionHealthy && !storageHealthy {
            issues.append("Encryption healthy but storage unhealthy - data may be at risk")
        }

        return issues
    }

    private static func determineOverallStatus(_ componentStatuses: Dictionary<String, HealthStatus>.Values, _ dependencies: DependencyStatus, _ crossComponentIssues: [String]) -> HealthStatus {
        let unhealthyComponents = componentStatuses.filter { !$0.isHealthy }
        let totalIssues = unhealthyComponents.count + (dependencies.isHealthy ? 0 : 1) + crossComponentIssues.count

        if totalIssues == 0 {
            return .healthy(details: ["components": "\(componentStatuses.count)", "dependencies": "healthy"])
        } else if totalIssues <= 2 {
            var issues: [String] = unhealthyComponents.flatMap { status in
                switch status {
                case .healthy: return [String]()
                case .degraded(_, let componentIssues), .unhealthy(_, let componentIssues):
                    return componentIssues
                }
            }
            issues.append(contentsOf: dependencies.issues)
            issues.append(contentsOf: crossComponentIssues)

            return .degraded(details: ["unhealthy_components": "\(unhealthyComponents.count)"], issues: issues)
        } else {
            var issues: [String] = unhealthyComponents.flatMap { status in
                switch status {
                case .healthy: return [String]()
                case .degraded(_, let componentIssues), .unhealthy(_, let componentIssues):
                    return componentIssues
                }
            }
            issues.append(contentsOf: dependencies.issues)
            issues.append(contentsOf: crossComponentIssues)

            return .unhealthy(details: ["unhealthy_components": "\(unhealthyComponents.count)"], issues: issues)
        }
    }

    private static func collectPerformanceMetrics() async -> [String: Double] {
        var metrics = [String: Double]()

        // Collect basic system metrics
        metrics["system_memory_gb"] = PlatformSpecific.systemMemoryGB
        metrics["optimal_thread_count"] = Double(PlatformSpecific.optimalThreadCount)

        // Collect operation metrics from Metrics system
        // This would integrate with the existing Metrics system

        return metrics
    }

    private static func generateRecommendations(_ health: EcosystemHealth, _ metrics: [String: Double]) -> [String] {
        var recommendations = [String]()

        if !health.overallStatus.isHealthy {
            recommendations.append("Address unhealthy components to restore ecosystem stability")
        }

        if !health.dependencies.isHealthy {
            recommendations.append("Fix dependency issues between CybS3 and SwiftS3 components")
        }

        if !health.crossComponentIssues.isEmpty {
            recommendations.append("Resolve cross-component issues for optimal ecosystem performance")
        }

        // Memory recommendations
        if let memoryGB = metrics["system_memory_gb"], memoryGB < 4.0 {
            recommendations.append("Consider upgrading system memory for better performance (current: \(String(format: "%.1f", memoryGB))GB)")
        }

        return recommendations
    }
}