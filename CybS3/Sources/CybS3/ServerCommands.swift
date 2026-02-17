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

            let process = Process()
            process.executableURL = URL(fileURLWithPath: swifts3Path)
            process.arguments = [
                "server",
                "--hostname", hostname,
                "--port", "\(port)",
                "--storage", storage,
                "--access-key", accessKey,
                "--secret-key", secretKey
            ]

            if background {
                // Save PID for later stop command
                let pidFile = "/tmp/swifts3-\(port).pid"
                process.terminationHandler = { _ in
                    try? FileManager.default.removeItem(atPath: pidFile)
                }

                try process.run()
                try "\(process.processIdentifier)".write(toFile: pidFile, atomically: true, encoding: .utf8)
                print("✅ Server started in background (PID: \(process.processIdentifier))")
                print("💡 Use 'cybs3 server stop --port \(port)' to stop")
            } else {
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    print("✅ Server stopped gracefully")
                } else {
                    print("❌ Server exited with code \(process.terminationStatus)")
                }
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
            let pidFile = "/tmp/swifts3-\(port).pid"
            guard let pidString = try? String(contentsOfFile: pidFile),
                  let pid = Int(pidString) else {
                print("❌ No server found running on port \(port)")
                return
            }

            print("🛑 Stopping SwiftS3 server on port \(port) (PID: \(pid))")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/kill")
            process.arguments = ["\(pid)"]

            try process.run()
            process.waitUntilExit()

            try? FileManager.default.removeItem(atPath: pidFile)
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
            let pidFile = "/tmp/swifts3-\(port).pid"
            if let pidString = try? String(contentsOfFile: pidFile),
               let pid = Int(pidString) {
                print("✅ SwiftS3 server running on port \(port) (PID: \(pid))")

                // Try to connect and get basic info
                do {
                    let client = HTTPClient()
                    defer { try? client.shutdown() }

                    let request = HTTPClientRequest(url: "http://127.0.0.1:\(port)/")
                    let response = try await client.execute(request, deadline: .now() + .seconds(5))
                    print("   Status: \(response.status.code)")
                } catch {
                    print("   Status: Unable to connect")
                }
            } else {
                print("❌ No SwiftS3 server running on port \(port)")
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

            // Check if server is running
            let pidFile = "/tmp/swifts3-\(port).pid"
            guard let pidString = try? String(contentsOfFile: pidFile),
                  let pid = Int(pidString) else {
                print("❌ No SwiftS3 server running on port \(port)")
                print("💡 Start the server first with: cybs3 server start --port \(port)")
                throw ExitCode.failure
            }

            if follow {
                print("👀 Following logs for server on port \(port) (PID: \(pid))")
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
                print("📄 Last \(lines) lines of logs for server on port \(port):")
                print(String(repeating: "─", count: 60))

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
                process.arguments = ["-n", "\(lines)", "/tmp/swifts3-\(port).log"]

                let outputPipe = Pipe()
                process.standardOutput = outputPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                        print(output)
                    } else {
                        print("⚠️  No logs found or log file is empty")
                    }
                } catch {
                    print("⚠️  Log file not found. Server may not be configured to write logs.")
                    print("   Check server startup logs for log file location.")
                }
            }
        }
    }
}