import Foundation
import Hummingbird
import HTTPTypes
import Logging
import NIO

extension S3Controller {
    /// Registers admin and batch operation routes.
    func addAdminRoutes(to router: some Router<S3RequestContext>) {
        // Audit Events (Global and Bucket-specific)
        router.get("/audit", use: { request, context in
            try await self.getBucketAuditEvents(bucket: nil, request: request, context: context)
        })
        router.get(":bucket/audit", use: { request, context in
            let bucket = try context.parameters.require("bucket")
            return try await self.getBucketAuditEvents(bucket: bucket, request: request, context: context)
        })
        router.delete("/audit", use: { request, context in
            try await self.deleteAuditEvents(request: request, context: context)
        })

        // Analytics & Insights
        router.get("/analytics/storage", use: { request, context in
            try await self.getStorageAnalytics(request: request, context: context)
        })
        router.get(":bucket/analytics/access-analyzer", use: { request, context in
            let bucket = try context.parameters.require("bucket")
            return try await self.getAccessAnalyzer(bucket: bucket, request: request, context: context)
        })
        router.get(":bucket/inventory", use: { request, context in
            let bucket = try context.parameters.require("bucket")
            return try await self.getBucketInventory(bucket: bucket, request: request, context: context)
        })
        router.get("/analytics/performance", use: { request, context in
            try await self.getPerformanceMetrics(request: request, context: context)
        })

        // Batch Operations
        router.post("/batch/job", use: { request, context in
            try await self.createBatchJob(request: request, context: context)
        })
        router.get("/batch/job/:jobId", use: { request, context in
            let jobId = try context.parameters.require("jobId")
            return try await self.getBatchJob(jobId: jobId, request: request, context: context)
        })
        router.get("/batch/jobs", use: { request, context in
            try await self.listBatchJobs(request: request, context: context)
        })
        router.put("/batch/job/:jobId/status", use: { request, context in
            let jobId = try context.parameters.require("jobId")
            return try await self.updateBatchJobStatus(jobId: jobId, request: request, context: context)
        })
        router.delete("/batch/job/:jobId", use: { request, context in
            let jobId = try context.parameters.require("jobId")
            return try await self.deleteBatchJob(jobId: jobId, request: request, context: context)
        })
    }

    /// Retrieves audit events.
    func getBucketAuditEvents(bucket: String?, request: Request, context: S3RequestContext) async throws -> Response {
        if let bucket = bucket {
            try await checkAccess(bucket: bucket, action: "s3:GetBucketAuditEvents", request: request, context: context)
        }

        let query = request.uri.queryParameters
        let principal = query.get("principal")
        let eventTypeRaw = query.get("eventType")
        let eventType = eventTypeRaw.flatMap { AuditEventType(rawValue: $0) }

        let startDate = query.get("startDate").flatMap { ISO8601DateFormatter().date(from: $0) }
        let endDate = query.get("endDate").flatMap { ISO8601DateFormatter().date(from: $0) }

        let limit = query.get("maxItems").flatMap { Int($0) } ?? 100
        let clampedLimit = min(max(limit, 1), 1000)

        let continuationToken = query.get("continuationToken")

        let (events, nextToken) = try await storage.getAuditEvents(
            bucket: bucket, principal: principal, eventType: eventType,
            startDate: startDate, endDate: endDate, limit: clampedLimit, continuationToken: continuationToken
        )

        struct AuditEventsResponse: Codable {
            let events: [AuditEvent]
            let nextContinuationToken: String?
            let isTruncated: Bool
        }

        let response = AuditEventsResponse(events: events, nextContinuationToken: nextToken, isTruncated: nextToken != nil)
        let jsonData = try JSONEncoder().encode(response)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }

    /// Deletes audit events.
    func deleteAuditEvents(request: Request, context: S3RequestContext) async throws -> Response {
        let query = request.uri.queryParameters
        guard let olderThanRaw = query.get("olderThan"),
              let olderThan = ISO8601DateFormatter().date(from: olderThanRaw) else {
            throw S3Error.invalidArgument
        }

        try await storage.deleteAuditEvents(olderThan: olderThan)
        logger.info("Audit events deleted", metadata: ["olderThan": "\(olderThan)"])
        return Response(status: .noContent)
    }

    /// Retrieves storage analytics.
    func getStorageAnalytics(request: Request, context: S3RequestContext) async throws -> Response {
        let query = request.uri.queryParameters
        let periodDays = Int(query.get("period") ?? "30") ?? 30
        let filterBucket = query.get("bucket")
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-TimeInterval(periodDays * 24 * 60 * 60))

        let (events, _) = try await storage.getAuditEvents(
            bucket: filterBucket, principal: nil, eventType: nil,
            startDate: startDate, endDate: endDate, limit: nil, continuationToken: nil
        )

        let buckets = try await storage.listBuckets()
        var totalStorage: Int64 = 0
        var bucketStats: [String: [String: Any]] = [:]

        for (bucketName, _) in buckets {
            if let filterBucket = filterBucket, filterBucket != bucketName { continue }
            
            let objects = try await storage.listObjects(
                bucket: bucketName, prefix: nil, delimiter: nil, marker: nil,
                continuationToken: nil, maxKeys: nil
            )
            
            var bucketSize: Int64 = 0
            var objectCount = 0
            var storageClasses: [String: Int] = [:]
            
            for object in objects.objects {
                bucketSize += object.size
                objectCount += 1
                let storageClass = object.storageClass.rawValue
                storageClasses[storageClass, default: 0] += 1
            }
            
            totalStorage += bucketSize
            
            let bucketEvents = events.filter { $0.bucket == bucketName }
            let accessCount = bucketEvents.count
            let downloadCount = bucketEvents.filter { $0.eventType == .objectDownloaded }.count
            let uploadCount = bucketEvents.filter { $0.eventType == .objectUploaded }.count
            
            bucketStats[bucketName] = [
                "size": bucketSize,
                "objectCount": objectCount,
                "storageClasses": storageClasses,
                "accessCount": accessCount,
                "downloadCount": downloadCount,
                "uploadCount": uploadCount
            ]
        }

        let totalAccesses = events.count
        let downloads = events.filter { $0.eventType == .objectDownloaded }.count
        let uploads = events.filter { $0.eventType == .objectUploaded }.count
        let deletes = events.filter { $0.eventType == .objectDeleted }.count
        
        var objectAccessCount: [String: Int] = [:]
        for event in events where event.key != nil {
            let key = "\(event.bucket ?? "")/\(event.key ?? "")"
            objectAccessCount[key, default: 0] += 1
        }
        let topAccessedObjects = objectAccessCount.sorted { $0.value > $1.value }.prefix(10).map { ["key": $0.key, "accesses": $0.value] }

        var costInsights: [String: Any] = [:]
        var unusedObjects = 0
        var oldObjects = 0
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        for (bucketName, _) in bucketStats {
            let objects = try await storage.listObjects(
                bucket: bucketName, prefix: nil, delimiter: nil, marker: nil,
                continuationToken: nil, maxKeys: nil
            )
            
            for object in objects.objects {
                let recentAccesses = events.filter { 
                    $0.key == object.key && $0.bucket == bucketName && $0.timestamp > thirtyDaysAgo 
                }.count
                
                if recentAccesses == 0 && object.lastModified < thirtyDaysAgo {
                    unusedObjects += 1
                }
                
                if object.lastModified < thirtyDaysAgo.addingTimeInterval(-365 * 24 * 60 * 60) {
                    oldObjects += 1
                }
            }
        }
        
        costInsights["unusedObjects"] = unusedObjects
        costInsights["oldObjects"] = oldObjects
        costInsights["recommendations"] = [
            "Consider moving \(unusedObjects) unused objects to cheaper storage classes",
            "Consider lifecycle policies for \(oldObjects) old objects"
        ]

        let analytics: [String: Any] = [
            "period": [
                "start": ISO8601DateFormatter().string(from: startDate),
                "end": ISO8601DateFormatter().string(from: endDate),
                "days": periodDays
            ],
            "summary": [
                "totalStorage": totalStorage,
                "totalBuckets": bucketStats.count,
                "totalAccesses": totalAccesses,
                "downloads": downloads,
                "uploads": uploads,
                "deletes": deletes
            ],
            "bucketStats": bucketStats,
            "topAccessedObjects": topAccessedObjects,
            "costInsights": costInsights
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: analytics, options: .prettyPrinted)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }

    /// Performs access analysis.
    func getAccessAnalyzer(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        _ = try await storage.headBucket(name: bucket)

        let query = request.uri.queryParameters
        let periodDays = Int(query.get("period") ?? "7") ?? 7
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-TimeInterval(periodDays * 24 * 60 * 60))

        let (events, _) = try await storage.getAuditEvents(
            bucket: bucket, principal: nil, eventType: nil,
            startDate: startDate, endDate: endDate, limit: nil, continuationToken: nil
        )

        var findings: [[String: Any]] = []
        var principalAccess: [String: [AuditEvent]] = [:]
        var ipAccess: [String: [AuditEvent]] = [:]
        var errorEvents: [AuditEvent] = []
        
        for event in events {
            let principal = event.principal
            principalAccess[principal, default: []].append(event)
            
            if let ip = event.sourceIp {
                ipAccess[ip, default: []].append(event)
            }
            
            if event.status != "200" && event.status != "201" && event.status != "204" {
                errorEvents.append(event)
            }
        }

        let totalEvents = events.count
        let errorRate = Double(errorEvents.count) / Double(totalEvents)
        if errorRate > 0.1 {
            findings.append([
                "severity": "high",
                "type": "high_error_rate",
                "description": "High error rate detected (\(String(format: "%.1f", errorRate * 100))%)",
                "recommendation": "Review error logs"
            ])
        }

        for (ip, ipEvents) in ipAccess {
            let accessCount = ipEvents.count
            if accessCount > totalEvents / 2 {
                findings.append([
                    "severity": "medium",
                    "type": "concentrated_access",
                    "description": "High concentration of access from single IP: \(ip) (\(accessCount) requests)",
                    "recommendation": "Verify if this is expected behavior"
                ])
            }
        }

        let authFailures = events.filter { $0.eventType == .authenticationFailed }.count
        if authFailures > 10 {
            findings.append([
                "severity": "high",
                "type": "authentication_failures",
                "description": "\(authFailures) authentication failures detected",
                "recommendation": "Check for brute force attempts"
            ])
        }

        let accessDenied = events.filter { $0.eventType == .accessDenied }.count
        if accessDenied > Int(Double(totalEvents) * 0.05) {
            findings.append([
                "severity": "medium",
                "type": "access_denied",
                "description": "\(accessDenied) access denied events",
                "recommendation": "Review permissions"
            ])
        }

        let anonymousAccess = events.filter { $0.principal == "anonymous" }.count
        if anonymousAccess > 0 {
            findings.append([
                "severity": "high",
                "type": "anonymous_access",
                "description": "\(anonymousAccess) requests from anonymous users detected",
                "recommendation": "Review bucket policies"
            ])
        }

        var hourlyAccess: [Int: Int] = [:]
        for event in events {
            let hour = Calendar.current.component(.hour, from: event.timestamp)
            hourlyAccess[hour, default: 0] += 1
        }
        
        let avgHourly = Double(totalEvents) / 24.0
        for (hour, count) in hourlyAccess {
            if Double(count) > avgHourly * 3 {
                findings.append([
                    "severity": "low",
                    "type": "unusual_timing",
                    "description": "Unusual access concentration at hour \(hour) (\(count) requests)",
                    "recommendation": "Monitor for automated access"
                ])
            }
        }

        let analysis: [String: Any] = [
            "bucket": bucket,
            "period": [
                "start": ISO8601DateFormatter().string(from: startDate),
                "end": ISO8601DateFormatter().string(from: endDate),
                "days": periodDays
            ],
            "summary": [
                "totalEvents": totalEvents,
                "uniquePrincipals": principalAccess.count,
                "uniqueIPs": ipAccess.count,
                "errorRate": errorRate,
                "findingsCount": findings.count
            ],
            "findings": findings
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: analysis, options: .prettyPrinted)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }

    /// Generates inventory report.
    func getBucketInventory(bucket: String, request: Request, context: S3RequestContext) async throws -> Response {
        _ = try await storage.headBucket(name: bucket)

        let query = request.uri.queryParameters
        let format = query.get("format") ?? "json"
        let prefix = query.get("prefix")

        let result = try await storage.listObjects(
            bucket: bucket, prefix: prefix, delimiter: nil, marker: nil,
            continuationToken: nil, maxKeys: nil
        )

        if format == "csv" {
            var csv = "Key,Size,LastModified,ETag,StorageClass,Owner\n"
            for object in result.objects {
                let key = object.key.replacingOccurrences(of: "\"", with: "\"\"")
                let size = "\(object.size)"
                let lastModified = ISO8601DateFormatter().string(from: object.lastModified)
                let etag = object.eTag ?? ""
                let storageClass = object.storageClass.rawValue
                let owner = object.owner ?? ""
                csv += "\"\(key)\",\(size),\(lastModified),\"\(etag)\",\(storageClass),\"\(owner)\"\n"
            }
            return Response(
                status: .ok,
                headers: [
                    .contentType: "text/csv",
                    HTTPField.Name("Content-Disposition")!: "attachment; filename=\"\(bucket)-inventory.csv\""
                ],
                body: .init(byteBuffer: ByteBuffer(string: csv))
            )
        } else {
            let inventory: [String: Any] = [
                "bucket": bucket,
                "generated": ISO8601DateFormatter().string(from: Date()),
                "totalObjects": result.objects.count,
                "prefix": prefix as Any,
                "objects": result.objects.map { object in
                    [
                        "key": object.key,
                        "size": object.size,
                        "lastModified": ISO8601DateFormatter().string(from: object.lastModified),
                        "etag": object.eTag as Any,
                        "contentType": object.contentType as Any,
                        "storageClass": object.storageClass.rawValue,
                        "owner": object.owner as Any,
                        "versionId": object.versionId,
                        "isLatest": object.isLatest,
                        "checksumAlgorithm": object.checksumAlgorithm?.rawValue as Any,
                        "checksumValue": object.checksumValue as Any
                    ]
                }
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: inventory, options: .prettyPrinted)
            return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
        }
    }

    /// Retrieves performance metrics.
    func getPerformanceMetrics(request: Request, context: S3RequestContext) async throws -> Response {
        let query = request.uri.queryParameters
        let periodHours = Int(query.get("period") ?? "24") ?? 24
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-TimeInterval(periodHours * 60 * 60))

        let (events, _) = try await storage.getAuditEvents(
            bucket: nil, principal: nil, eventType: nil,
            startDate: startDate, endDate: endDate, limit: nil, continuationToken: nil
        )

        var operationCounts: [String: Int] = [:]
        var errorCounts: [String: Int] = [:]
        var hourlyThroughput: [Int: Int] = [:]
        
        for event in events {
            operationCounts[event.operation, default: 0] += 1
            if event.status.starts(with: "4") || event.status.starts(with: "5") {
                errorCounts[event.operation, default: 0] += 1
            }
            let hour = Calendar.current.component(.hour, from: event.timestamp)
            hourlyThroughput[hour, default: 0] += 1
        }

        var errorRates: [String: Double] = [:]
        for (operation, count) in operationCounts {
            let errors = errorCounts[operation] ?? 0
            errorRates[operation] = Double(errors) / Double(count)
        }

        let basicMetrics = await metrics.getMetrics()
        
        let totalRequests = events.count
        let avgRequestsPerHour = Double(totalRequests) / Double(periodHours)
        let peakHour = hourlyThroughput.max { $0.value < $1.value }?.key ?? 0
        let peakRequests = hourlyThroughput[peakHour] ?? 0

        var recommendations: [String] = []
        if avgRequestsPerHour > 1000 {
            recommendations.append("High request volume detected. Consider scaling infrastructure.")
        }
        let highErrorOps = errorRates.filter { $0.value > 0.05 }.keys
        if !highErrorOps.isEmpty {
            recommendations.append("High error rates for operations: \(highErrorOps.joined(separator: ", "))")
        }
        if Double(peakRequests) > avgRequestsPerHour * 2 {
            recommendations.append("Significant traffic spikes detected. Consider load balancing.")
        }

        let performance: [String: Any] = [
            "period": [
                "start": ISO8601DateFormatter().string(from: startDate),
                "end": ISO8601DateFormatter().string(from: endDate),
                "hours": periodHours
            ],
            "throughput": [
                "totalRequests": totalRequests,
                "avgRequestsPerHour": avgRequestsPerHour,
                "peakHour": peakHour,
                "peakRequests": peakRequests,
                "hourlyBreakdown": hourlyThroughput
            ],
            "operations": [
                "counts": operationCounts,
                "errorRates": errorRates
            ],
            "basicMetrics": basicMetrics,
            "recommendations": recommendations
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: performance, options: .prettyPrinted)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }

    /// Creates a batch job.
    func createBatchJob(request: Request, context: S3RequestContext) async throws -> Response {
        let body = try await request.body.collect(upTo: 1024 * 1024)
        let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any] ?? [:]

        guard let operationDict = json["operation"] as? [String: Any],
              let operationTypeStr = operationDict["type"] as? String,
              let operationType = BatchOperationType(rawValue: operationTypeStr),
              let operationParams = operationDict["parameters"] as? [String: String] else {
            throw S3Error(code: "InvalidRequest", message: "Invalid operation specification", statusCode: .badRequest)
        }
        let operation = BatchOperation(type: operationType, parameters: operationParams)

        guard let manifestDict = json["manifest"] as? [String: Any],
              let locationDict = manifestDict["location"] as? [String: Any],
              let manifestBucket = locationDict["bucket"] as? String,
              let manifestKey = locationDict["key"] as? String,
              let specDict = manifestDict["spec"] as? [String: Any],
              let formatStr = specDict["format"] as? String,
              let format = BatchManifestFormat(rawValue: formatStr),
              let fields = specDict["fields"] as? [String] else {
            throw S3Error(code: "InvalidRequest", message: "Invalid manifest specification", statusCode: .badRequest)
        }
        let manifestEtag = locationDict["etag"] as? String
        let manifestLocation = BatchManifestLocation(bucket: manifestBucket, key: manifestKey, etag: manifestEtag)
        let manifestSpec = BatchManifestSpec(format: format, fields: fields)
        let manifest = BatchManifest(location: manifestLocation, spec: manifestSpec)

        let priority = json["priority"] as? Int ?? 0
        let roleArn = json["roleArn"] as? String

        let job = BatchJob(operation: operation, manifest: manifest, priority: priority, roleArn: roleArn)
        let jobId = try await storage.createBatchJob(job: job)

        let response: [String: Any] = ["jobId": jobId, "status": "created"]
        let jsonData = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
        return Response(status: .created, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }

    /// Retrieves a batch job.
    func getBatchJob(jobId: String, request: Request, context: S3RequestContext) async throws -> Response {
        guard let job = try await storage.getBatchJob(jobId: jobId) else {
            throw S3Error.noSuchKey
        }

        let jobDict: [String: Any] = [
            "id": job.id,
            "operation": ["type": job.operation.type.rawValue, "parameters": job.operation.parameters],
            "manifest": [
                "location": ["bucket": job.manifest.location.bucket, "key": job.manifest.location.key, "etag": job.manifest.location.etag as Any],
                "spec": ["format": job.manifest.spec.format.rawValue, "fields": job.manifest.spec.fields]
            ],
            "priority": job.priority,
            "roleArn": job.roleArn as Any,
            "status": job.status.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: job.createdAt),
            "completedAt": job.completedAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
            "failureReasons": job.failureReasons,
            "progress": ["totalObjects": job.progress.totalObjects, "processedObjects": job.progress.processedObjects, "failedObjects": job.progress.failedObjects]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: jobDict, options: .prettyPrinted)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }

    /// Lists batch jobs.
    func listBatchJobs(request: Request, context: S3RequestContext) async throws -> Response {
        let query = request.uri.queryParameters
        let bucket = query.get("bucket")
        let statusStr = query.get("status")
        let status = statusStr.flatMap { BatchJobStatus(rawValue: $0) }
        let limit = Int(query.get("maxJobs") ?? "100") ?? 100
        let continuationToken = query.get("continuationToken")

        let (jobs, nextContinuationToken) = try await storage.listBatchJobs(bucket: bucket, status: status, limit: limit, continuationToken: continuationToken)

        let jobsArray = jobs.map { job -> [String: Any] in
            [
                "id": job.id,
                "operation": ["type": job.operation.type.rawValue, "parameters": job.operation.parameters],
                "manifest": ["location": ["bucket": job.manifest.location.bucket, "key": job.manifest.location.key]],
                "status": job.status.rawValue,
                "createdAt": ISO8601DateFormatter().string(from: job.createdAt),
                "progress": ["totalObjects": job.progress.totalObjects, "processedObjects": job.progress.processedObjects, "failedObjects": job.progress.failedObjects]
            ]
        }
        var response: [String: Any] = ["jobs": jobsArray, "totalCount": jobsArray.count]
        if let nextToken = nextContinuationToken {
            response["nextContinuationToken"] = nextToken
        }
        let jsonData = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }

    /// Updates batch job status.
    func updateBatchJobStatus(jobId: String, request: Request, context: S3RequestContext) async throws -> Response {
        let body = try await request.body.collect(upTo: 1024 * 1024)
        let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any] ?? [:]

        guard let statusStr = json["status"] as? String,
              let status = BatchJobStatus(rawValue: statusStr) else {
            throw S3Error(code: "InvalidRequest", message: "Invalid status", statusCode: .badRequest)
        }
        let failureReasons = json["failureReasons"] as? [String]
        let message = failureReasons?.joined(separator: "; ") ?? json["message"] as? String

        try await storage.updateBatchJobStatus(jobId: jobId, status: status, message: message)
        let response: [String: Any] = ["jobId": jobId, "status": status.rawValue, "updated": true]
        let jsonData = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }

    /// Deletes a batch job.
    func deleteBatchJob(jobId: String, request: Request, context: S3RequestContext) async throws -> Response {
        guard let job = try await storage.getBatchJob(jobId: jobId) else {
            throw S3Error.noSuchKey
        }
        guard job.status == .complete || job.status == .failed || job.status == .cancelled else {
            throw S3Error(code: "InvalidRequest", message: "Cannot delete active batch job", statusCode: .badRequest)
        }
        try await storage.deleteBatchJob(jobId: jobId)
        let response: [String: Any] = ["jobId": jobId, "deleted": true]
        let jsonData = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: jsonData)))
    }
}
