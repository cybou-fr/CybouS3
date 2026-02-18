import AsyncHTTPClient
import CybS3Lib
import Foundation
import NIOCore

/// Protocol for server process management service
public protocol ServerProcessServiceProtocol {
    func startServer(config: ServerStartConfig) async throws -> ServerStartResult
    func stopServer(port: Int) async throws -> ServerStopResult
    func getServerStatus(port: Int) async throws -> ServerStatusResult
    func getServerLogs(port: Int, lines: Int, follow: Bool) async throws -> ServerLogsResult
}

/// Server configuration for starting
public struct ServerStartConfig {
    public let swifts3Path: String
    public let port: Int
    public let hostname: String
    public let storage: String
    public let accessKey: String
    public let secretKey: String
    public let background: Bool

    public init(swifts3Path: String, port: Int, hostname: String, storage: String, accessKey: String, secretKey: String, background: Bool) {
        self.swifts3Path = swifts3Path
        self.port = port
        self.hostname = hostname
        self.storage = storage
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.background = background
    }
}

/// Results for server operations
public struct ServerStartResult {
    public let port: Int
    public let hostname: String
    public let pid: Int?
    public let background: Bool
}

public struct ServerStopResult {
    public let port: Int
    public let pid: Int?
}

public struct ServerStatusResult {
    public let port: Int
    public let running: Bool
    public let pid: Int?
    public let httpStatus: Int?
}

public struct ServerLogsResult {
    public let port: Int
    public let pid: Int?
    public let logs: String?
    public let follow: Bool
}

/// Default implementation of server process service
public class DefaultServerProcessService: ServerProcessServiceProtocol {
    private let httpClient: HTTPClient

    public init(httpClient: HTTPClient = HTTPClient()) {
        self.httpClient = httpClient
    }

    public func startServer(config: ServerStartConfig) async throws -> ServerStartResult {
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
                pid: Int(process.processIdentifier),
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

    public func stopServer(port: Int) async throws -> ServerStopResult {
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

    public func getServerStatus(port: Int) async throws -> ServerStatusResult {
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

    public func getServerLogs(port: Int, lines: Int, follow: Bool) async throws -> ServerLogsResult {
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

public struct StartServerInput {
    public let config: ServerStartConfig

    public init(config: ServerStartConfig) {
        self.config = config
    }
}

public struct StartServerOutput {
    public let result: ServerStartResult
}

public struct StopServerInput {
    public let port: Int

    public init(port: Int) {
        self.port = port
    }
}

public struct StopServerOutput {
    public let result: ServerStopResult
}

public struct GetServerStatusInput {
    public let port: Int

    public init(port: Int) {
        self.port = port
    }
}

public struct GetServerStatusOutput {
    public let result: ServerStatusResult
}

public struct GetServerLogsInput {
    public let port: Int
    public let lines: Int
    public let follow: Bool

    public init(port: Int, lines: Int, follow: Bool) {
        self.port = port
        self.lines = lines
        self.follow = follow
    }
}

public struct GetServerLogsOutput {
    public let result: ServerLogsResult
}

/// Server operation handlers

public class StartServerHandler {
    public typealias Input = StartServerInput
    public typealias Output = StartServerOutput

    private let service: ServerProcessServiceProtocol

    public init(service: ServerProcessServiceProtocol) {
        self.service = service
    }

    public func handle(input: Input) async throws -> Output {
        let result = try await service.startServer(config: input.config)
        return Output(result: result)
    }
}

public class StopServerHandler {
    public typealias Input = StopServerInput
    public typealias Output = StopServerOutput

    private let service: ServerProcessServiceProtocol

    public init(service: ServerProcessServiceProtocol) {
        self.service = service
    }

    public func handle(input: Input) async throws -> Output {
        let result = try await service.stopServer(port: input.port)
        return Output(result: result)
    }
}

public class GetServerStatusHandler {
    public typealias Input = GetServerStatusInput
    public typealias Output = GetServerStatusOutput

    private let service: ServerProcessServiceProtocol

    public init(service: ServerProcessServiceProtocol) {
        self.service = service
    }

    public func handle(input: Input) async throws -> Output {
        let result = try await service.getServerStatus(port: input.port)
        return Output(result: result)
    }
}

public class GetServerLogsHandler {
    public typealias Input = GetServerLogsInput
    public typealias Output = GetServerLogsOutput

    private let service: ServerProcessServiceProtocol

    public init(service: ServerProcessServiceProtocol) {
        self.service = service
    }

    public func handle(input: Input) async throws -> Output {
        let result = try await service.getServerLogs(port: input.port, lines: input.lines, follow: input.follow)
        return Output(result: result)
    }
}