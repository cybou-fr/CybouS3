import Foundation
import Hummingbird
import Logging

/// Actor responsible for collecting and exposing S3 server metrics.
/// Provides Prometheus-compatible metrics for monitoring server performance and usage.
/// Thread-safe due to actor isolation, allowing concurrent metric updates.
actor S3Metrics {
    private var requestCount: Int = 0
    private var requestDuration: [String: [TimeInterval]] = [:] // method -> durations
    private var storageBytes: Int64 = 0

    /// Increments the total request count by one.
    func incrementRequestCount() {
        requestCount += 1
    }

    /// Records the duration of a request for the specified HTTP method.
    /// Maintains a rolling window of the last 100 measurements per method.
    /// - Parameters:
    ///   - method: The HTTP method (e.g., "GET", "PUT") for which to record the duration
    ///   - duration: The request duration in seconds
    func recordRequestDuration(method: String, duration: TimeInterval) {
        if requestDuration[method] == nil {
            requestDuration[method] = []
        }
        requestDuration[method]!.append(duration)
        // Keep only last 100 measurements
        if requestDuration[method]!.count > 100 {
            requestDuration[method]!.removeFirst()
        }
    }

    /// Sets the current storage usage in bytes.
    /// - Parameter bytes: The total number of bytes currently stored
    func setStorageBytes(_ bytes: Int64) {
        storageBytes = bytes
    }

    /// Returns metrics data in Prometheus format for monitoring.
    /// Includes request counts and average request durations by HTTP method.
    /// - Returns: A string containing Prometheus-formatted metrics
    func getMetrics() -> String {
        var output = "# HELP s3_requests_total Total number of S3 requests\n"
        output += "# TYPE s3_requests_total counter\n"
        output += "s3_requests_total \(requestCount)\n\n"

        output += "# HELP s3_request_duration_seconds Request duration in seconds\n"
        output += "# TYPE s3_request_duration_seconds histogram\n"
        for (method, durations) in requestDuration {
            if let avg = durations.average() {
                output += "s3_request_duration_seconds{operation=\"\(method)\"} \(avg)\n"
            }
        }
        output += "\n"

        output += "# HELP s3_storage_bytes_total Total storage bytes used\n"
        output += "# TYPE s3_storage_bytes_total gauge\n"
        output += "s3_storage_bytes_total \(storageBytes)\n"

        return output
    }
}

extension Array where Element == TimeInterval {
    /// Calculates the average of all time intervals in the array.
    /// - Returns: The average duration, or nil if the array is empty
    func average() -> TimeInterval? {
        guard !isEmpty else { return nil }
        let sum = reduce(0, +)
        return sum / TimeInterval(count)
    }
}

/// Middleware that records request metrics for monitoring and observability.
/// Captures request count, duration, and other performance metrics for each HTTP request.
/// Integrates with the S3Metrics actor to provide thread-safe metric collection.
struct S3MetricsMiddleware: RouterMiddleware {
    let metrics: S3Metrics

    func handle(_ input: Request, context: S3RequestContext, next: (Request, S3RequestContext) async throws -> Response) async throws -> Response {
        let start = Date()
        let response = try await next(input, context)
        let duration = Date().timeIntervalSince(start)
        
        await metrics.incrementRequestCount()
        await metrics.recordRequestDuration(method: input.method.rawValue, duration: duration)
        
        return response
    }
}
