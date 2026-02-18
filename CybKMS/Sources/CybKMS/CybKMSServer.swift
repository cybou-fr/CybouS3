import ArgumentParser
import Foundation
import Hummingbird
import Logging

/// CybKMS Server - Standalone AWS KMS API-compatible server
@main
struct CybKMSServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cybkms",
        abstract: "CybKMS - Standalone AWS KMS API-compatible server",
        version: "1.0.0"
    )

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 8080

    @Option(name: .shortAndLong, help: "Host to bind to")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Path to persist keys (optional)")
    var keyStorePath: String?

    @Option(name: .long, help: "Log level (trace, debug, info, notice, warning, error, critical)")
    var logLevel: String = "info"

    func run() async throws {
        // Setup logging
        let logLevel = Logger.Level(rawValue: logLevel) ?? .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = logLevel
            return handler
        }

        let logger = Logger(label: "CybKMS.Server")

        logger.info("Starting CybKMS server", metadata: [
            "host": "\(host)",
            "port": "\(port)",
            "keyStorePath": "\(keyStorePath ?? "in-memory")"
        ])

        // Initialize key store
        let keyStore = try await KMSKeyStore(persistencePath: keyStorePath)
        let operations = KMSOperations(keyStore: keyStore)

        // Create KMS controller
        let kmsController = KMSController(operations: operations)

        // Create Router
        let router = Router()

        // Add middleware
        router.middlewares.add(LogRequestsMiddleware(.info))
        router.middlewares.add(CORSMiddleware<BasicRequestContext>())

        // Register routes
        router.registerKMSRoutes(controller: kmsController)

        // Health check endpoint
        router.get("/health") { _, _ in
            return ["status": "healthy", "service": "CybKMS", "version": "1.0.0"]
        }

        // Root endpoint
        router.get("/") { _, _ in
            return RootResponse(
                service: "CybKMS",
                version: "1.0.0",
                description: "AWS KMS API-compatible key management service",
                endpoints: [
                    "POST /CreateKey",
                    "POST /DescribeKey",
                    "POST /ListKeys",
                    "POST /Encrypt",
                    "POST /Decrypt",
                    "POST /EnableKey",
                    "POST /DisableKey",
                    "POST /ScheduleKeyDeletion",
                    "GET /health"
                ]
            )
        }

        // Setup Hummingbird application
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(host, port: port),
                serverName: "CybKMS"
            )
        )

        logger.info("CybKMS server started successfully", metadata: [
            "url": "http://\(host):\(port)"
        ])

        // Start the server
        try await app.runService()
    }
}

struct RootResponse: ResponseGenerator, Encodable {
    let service: String
    let version: String
    let description: String
    let endpoints: [String]
    
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let jsonData = try JSONEncoder().encode(self)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: jsonData)))
    }
}

// MARK: - Middleware

/// CORS middleware for API access
struct CORSMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(_ input: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        var response = try await next(input, context)

        // Add CORS headers
        response.headers[.accessControlAllowOrigin] = "*"
        response.headers[.accessControlAllowMethods] = "GET, POST, PUT, DELETE, OPTIONS"
        response.headers[.accessControlAllowHeaders] = "Content-Type, Authorization"

        return response
    }
}