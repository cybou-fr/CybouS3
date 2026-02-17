import AsyncHTTPClient
import CybS3Lib
import Foundation
import NIOCore

/// Protocol for server process management service
protocol ServerProcessServiceProtocol {
    func startServer(config: ServerStartConfig) async throws -> ServerStartResult
    func stopServer(port: Int) async throws -> ServerStopResult
    func getServerStatus(port: Int) async throws -> ServerStatusResult
    func getServerLogs(port: Int, lines: Int, follow: Bool) async throws -> ServerLogsResult
}

/// Server configuration for starting
struct ServerStartConfig {
    let swifts3Path: String
    let port: Int
    let hostname: String
    let storage: String
    let accessKey: String
    let secretKey: String
    let background: Bool
}

/// Results for server operations
struct ServerStartResult {
    let port: Int
    let hostname: String
    let pid: Int?
    let background: Bool
}

struct ServerStopResult {
    let port: Int
    let pid: Int?
}

struct ServerStatusResult {
    let port: Int
    let running: Bool
    let pid: Int?
    let httpStatus: Int?
}

struct ServerLogsResult {
    let port: Int
    let pid: Int?
    let logs: String?
    let follow: Bool
}

/// Default implementation of server process service
class DefaultServerProcessService: ServerProcessServiceProtocol {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient = HTTPClient()) {
        self.httpClient = httpClient
    }

    func startServer(config: ServerStartConfig) async throws -> ServerStartResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.swifts3Path)
        process.arguments = [
            "server",
            "--hostname", config.hostname,
            "--port", "\(config.port)",
            "--storage", config.storage,
            "--access-key", config.accessKey,
            "--secret-key", config.secretKey
        ]

        if config.background {
            let pidFile = "/tmp/swifts3-\(config.port).pid"
            process.terminationHandler = { _ in
                try? FileManager.default.removeItem(atPath: pidFile)
            }

            try process.run()
            try "\(process.processIdentifier)".write(toFile: pidFile, atomically: true, encoding: .utf8)

            return ServerStartResult(
                port: config.port,
                hostname: config.hostname,
                pid: process.processIdentifier,
                background: true
            )
        } else {
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            try process.run()
            process.waitUntilExit()

            return ServerStartResult(
                port: config.port,
                hostname: config.hostname,
                pid: nil,
                background: false
            )
        }
    }

    func stopServer(port: Int) async throws -> ServerStopResult {
        let pidFile = "/tmp/swifts3-\(port).pid"
        guard let pidString = try? String(contentsOfFile: pidFile),
              let pid = Int(pidString) else {
            throw ServerError.serverNotRunning(port: port)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["\(pid)"]

        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(atPath: pidFile)

        return ServerStopResult(port: port, pid: pid)
    }

    func getServerStatus(port: Int) async throws -> ServerStatusResult {
        let pidFile = "/tmp/swifts3-\(port).pid"
        let pid: Int?
        if let pidString = try? String(contentsOfFile: pidFile),
           let parsedPid = Int(pidString) {
            pid = parsedPid
        } else {
            pid = nil
        }

        var httpStatus: Int? = nil
        if pid != nil {
            do {
                let request = HTTPClientRequest(url: "http://127.0.0.1:\(port)/")
                let response = try await httpClient.execute(request, deadline: .now() + .seconds(5))
                httpStatus = Int(response.status.code)
            } catch {
                // Connection failed, server might not be responding
            }
        }

        return ServerStatusResult(
            port: port,
            running: pid != nil,
            pid: pid,
            httpStatus: httpStatus
        )
    }

    func getServerLogs(port: Int, lines: Int, follow: Bool) async throws -> ServerLogsResult {
        let pidFile = "/tmp/swifts3-\(port).pid"
        guard let pidString = try? String(contentsOfFile: pidFile),
              let pid = Int(pidString) else {
            throw ServerError.serverNotRunning(port: port)
        }

        let logFile = "/tmp/swifts3-\(port).log"

        if follow {
            // For following logs, we can't easily capture output in async context
            // The command will handle this directly
            return ServerLogsResult(port: port, pid: pid, logs: nil, follow: true)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
            process.arguments = ["-n", "\(lines)", logFile]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let logs = String(data: outputData, encoding: .utf8)

                return ServerLogsResult(port: port, pid: pid, logs: logs, follow: false)
            } catch {
                return ServerLogsResult(port: port, pid: pid, logs: nil, follow: false)
            }
        }
    }
}

/// Server-related errors
enum ServerError: LocalizedError {
    case serverNotRunning(port: Int)

    var errorDescription: String? {
        switch self {
        case .serverNotRunning(let port):
            return "No server found running on port \(port)"
        }
    }
}

/// Input/Output types for server handlers

struct StartServerInput {
    let config: ServerStartConfig
}

struct StartServerOutput {
    let result: ServerStartResult
}

struct StopServerInput {
    let port: Int
}

struct StopServerOutput {
    let result: ServerStopResult
}

struct GetServerStatusInput {
    let port: Int
}

struct GetServerStatusOutput {
    let result: ServerStatusResult
}

struct GetServerLogsInput {
    let port: Int
    let lines: Int
    let follow: Bool
}

struct GetServerLogsOutput {
    let result: ServerLogsResult
}

/// Server operation handlers

class StartServerHandler {
    typealias Input = StartServerInput
    typealias Output = StartServerOutput

    private let service: ServerProcessServiceProtocol

    init(service: ServerProcessServiceProtocol) {
        self.service = service
    }

    func handle(input: Input) async throws -> Output {
        let result = try await service.startServer(config: input.config)
        return Output(result: result)
    }
}

class StopServerHandler {
    typealias Input = StopServerInput
    typealias Output = StopServerOutput

    private let service: ServerProcessServiceProtocol

    init(service: ServerProcessServiceProtocol) {
        self.service = service
    }

    func handle(input: Input) async throws -> Output {
        let result = try await service.stopServer(port: input.port)
        return Output(result: result)
    }
}

class GetServerStatusHandler {
    typealias Input = GetServerStatusInput
    typealias Output = GetServerStatusOutput

    private let service: ServerProcessServiceProtocol

    init(service: ServerProcessServiceProtocol) {
        self.service = service
    }

    func handle(input: Input) async throws -> Output {
        let result = try await service.getServerStatus(port: input.port)
        return Output(result: result)
    }
}

class GetServerLogsHandler {
    typealias Input = GetServerLogsInput
    typealias Output = GetServerLogsOutput

    private let service: ServerProcessServiceProtocol

    init(service: ServerProcessServiceProtocol) {
        self.service = service
    }

    func handle(input: Input) async throws -> Output {
        let result = try await service.getServerLogs(port: input.port, lines: input.lines, follow: input.follow)
        return Output(result: result)
    }
}</content>
<parameter name="filePath">/home/user/dev/CybouS3/CybS3/Sources/CybS3/ServerHandlers.swift