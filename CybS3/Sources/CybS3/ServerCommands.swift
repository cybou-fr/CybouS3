import ArgumentParser
import AsyncHTTPClient
import Foundation
import NIOCore

/// Server management commands for SwiftS3 instances
struct ServerCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "server",
        abstract: "Manage SwiftS3 server instances",
        subcommands: [
            Start.self,
            Stop.self,
            Status.self,
            Logs.self,
        ]
    )

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start a SwiftS3 server instance"
        )

        @Option(name: .long, help: "SwiftS3 executable path")
        var swifts3Path: String = "../SwiftS3/.build/release/SwiftS3"

        @Option(name: .shortAndLong, help: "Port to bind to")
        var port: Int = 8080

        @Option(name: .shortAndLong, help: "Hostname to bind to")
        var hostname: String = "127.0.0.1"

        @Option(name: .long, help: "Storage directory path")
        var storage: String = "./data"

        @Option(name: .customLong("access-key"), help: "AWS Access Key ID")
        var accessKey: String = "admin"

        @Option(name: .customLong("secret-key"), help: "AWS Secret Access Key")
        var secretKey: String = "password"

        @Flag(name: .long, help: "Run in background")
        var background: Bool = false

        func run() async throws {
            print("🚀 Starting SwiftS3 server...")
            print("   Host: \(hostname):\(port)")
            print("   Storage: \(storage)")
            print("   Access Key: \(accessKey)")

            let httpClient = HTTPClient()
            let service = DefaultServerProcessService(httpClient: httpClient)
            let handler = StartServerHandler(service: service)

            let config = ServerStartConfig(
                swifts3Path: swifts3Path,
                port: port,
                hostname: hostname,
                storage: storage,
                accessKey: accessKey,
                secretKey: secretKey,
                background: background
            )

            let input = StartServerInput(config: config)
            let output = try await handler.handle(input: input)

            if output.result.background {
                print("✅ Server started in background (PID: \(output.result.pid ?? 0))")
                print("💡 Use 'cybs3 server stop --port \(output.result.port)' to stop")
            } else {
                print("✅ Server stopped gracefully")
            }
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop a running SwiftS3 server instance"
        )

        @Option(name: .shortAndLong, help: "Port of the server to stop")
        var port: Int = 8080

        func run() async throws {
            let httpClient = HTTPClient()
            let service = DefaultServerProcessService(httpClient: httpClient)
            let handler = StopServerHandler(service: service)

            let input = StopServerInput(port: port)
            let output = try await handler.handle(input: input)

            print("🛑 Stopping SwiftS3 server on port \(output.result.port) (PID: \(output.result.pid ?? 0))")
            print("✅ Server stopped")
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Check status of SwiftS3 server instances"
        )

        @Option(name: .shortAndLong, help: "Port to check")
        var port: Int = 8080

        func run() async throws {
            let httpClient = HTTPClient()
            let service = DefaultServerProcessService(httpClient: httpClient)
            let handler = GetServerStatusHandler(service: service)

            let input = GetServerStatusInput(port: port)
            let output = try await handler.handle(input: input)

            if output.result.running {
                print("✅ SwiftS3 server running on port \(output.result.port) (PID: \(output.result.pid ?? 0))")
                if let httpStatus = output.result.httpStatus {
                    print("   Status: \(httpStatus)")
                } else {
                    print("   Status: Unable to connect")
                }
            } else {
                print("❌ No SwiftS3 server running on port \(output.result.port)")
            }
        }
    }

    struct Logs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logs",
            abstract: "View SwiftS3 server logs"
        )

        @Option(name: .shortAndLong, help: "Server port")
        var port: Int = 8080

        @Flag(name: .long, help: "Follow logs (tail -f)")
        var follow: Bool = false

        @Option(name: .long, help: "Number of lines to show")
        var lines: Int = 50

        func run() async throws {
            print("📋 Fetching SwiftS3 server logs...")

            let httpClient = HTTPClient()
            let service = DefaultServerProcessService(httpClient: httpClient)
            let handler = GetServerLogsHandler(service: service)

            let input = GetServerLogsInput(port: port, lines: lines, follow: follow)
            let output = try await handler.handle(input: input)

            if output.result.follow {
                print("👀 Following logs for server on port \(output.result.port) (PID: \(output.result.pid ?? 0))")
                print("   Press Ctrl+C to stop following")

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
                process.arguments = ["-f", "/tmp/swifts3-\(port).log"]

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    print("⚠️  Log file not found. Server may not be configured to write logs.")
                    print("   Check server startup logs for log file location.")
                }
            } else {
                print("📄 Last \(lines) lines of logs for server on port \(output.result.port):")
                print(String(repeating: "─", count: 60))

                if let logs = output.result.logs, !logs.isEmpty {
                    print(logs)
                } else {
                    print("⚠️  No logs found or log file is empty")
                    print("   Server may not be configured to write logs.")
                    print("   Check server startup logs for log file location.")
                }
            }
        }
    }
}