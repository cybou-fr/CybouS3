import XCTest
@testable import CybS3Lib

final class ServerHandlersTests: XCTestCase {

    // MARK: - Start SwiftS3 Handler Tests

    func testStartSwiftS3HandlerSuccess() async throws {
        // Given
        let mockServerService = MockServerProcessService()
        mockServerService.startSwiftS3Result = .success(ServerStartOutput(
            success: true,
            message: "SwiftS3 server started successfully",
            pid: 12345,
            port: 8080
        ))

        let handler = StartSwiftS3Handler(service: mockServerService)
        let input = StartSwiftS3Input(options: ServerStartOptions())

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "SwiftS3 server started successfully")
        XCTAssertEqual(output.pid, 12345)
        XCTAssertEqual(output.port, 8080)
    }

    func testStartSwiftS3HandlerFailure() async throws {
        // Given
        let mockServerService = MockServerProcessService()
        mockServerService.startSwiftS3Result = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Port already in use"]))

        let handler = StartSwiftS3Handler(service: mockServerService)
        let input = StartSwiftS3Input(options: ServerStartOptions())

        // When/Then
        do {
            _ = try await handler.handle(input: input)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TestError")
        }
    }

    // MARK: - Start CybKMS Handler Tests

    func testStartCybKMSHandlerSuccess() async throws {
        // Given
        let mockServerService = MockServerProcessService()
        mockServerService.startCybKMSResult = .success(ServerStartOutput(
            success: true,
            message: "CybKMS server started successfully",
            pid: 12346,
            port: 8081
        ))

        let handler = StartCybKMSHandler(service: mockServerService)
        let input = StartCybKMSInput(options: ServerStartOptions())

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "CybKMS server started successfully")
        XCTAssertEqual(output.pid, 12346)
        XCTAssertEqual(output.port, 8081)
    }

    // MARK: - Stop SwiftS3 Handler Tests

    func testStopSwiftS3HandlerSuccess() async throws {
        // Given
        let mockServerService = MockServerProcessService()
        mockServerService.stopResult = .success(ServerStopOutput(
            success: true,
            message: "SwiftS3 server stopped successfully"
        ))

        let handler = StopSwiftS3Handler(service: mockServerService)
        let input = StopSwiftS3Input()

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "SwiftS3 server stopped successfully")
    }

    // MARK: - Stop CybKMS Handler Tests

    func testStopCybKMSHandlerSuccess() async throws {
        // Given
        let mockServerService = MockServerProcessService()
        mockServerService.stopResult = .success(ServerStopOutput(
            success: true,
            message: "CybKMS server stopped successfully"
        ))

        let handler = StopCybKMSHandler(service: mockServerService)
        let input = StopCybKMSInput()

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "CybKMS server stopped successfully")
    }

    // MARK: - Status SwiftS3 Handler Tests

    func testStatusSwiftS3HandlerRunning() async throws {
        // Given
        let mockServerService = MockServerProcessService()
        mockServerService.statusResult = .success(ServerStatusOutput(
            success: true,
            message: "SwiftS3 server is running",
            running: true,
            pid: 12345,
            port: 8080,
            uptime: 3600
        ))

        let handler = StatusSwiftS3Handler(service: mockServerService)
        let input = StatusSwiftS3Input()

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "SwiftS3 server is running")
        XCTAssertTrue(output.running)
        XCTAssertEqual(output.pid, 12345)
        XCTAssertEqual(output.port, 8080)
        XCTAssertEqual(output.uptime, 3600)
    }

    func testStatusSwiftS3HandlerNotRunning() async throws {
        // Given
        let mockServerService = MockServerProcessService()
        mockServerService.statusResult = .success(ServerStatusOutput(
            success: true,
            message: "SwiftS3 server is not running",
            running: false,
            pid: nil,
            port: nil,
            uptime: nil
        ))

        let handler = StatusSwiftS3Handler(service: mockServerService)
        let input = StatusSwiftS3Input()

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "SwiftS3 server is not running")
        XCTAssertFalse(output.running)
        XCTAssertNil(output.pid)
        XCTAssertNil(output.port)
        XCTAssertNil(output.uptime)
    }

    // MARK: - Status CybKMS Handler Tests

    func testStatusCybKMSHandlerRunning() async throws {
        // Given
        let mockServerService = MockServerProcessService()
        mockServerService.statusResult = .success(ServerStatusOutput(
            success: true,
            message: "CybKMS server is running",
            running: true,
            pid: 12346,
            port: 8081,
            uptime: 1800
        ))

        let handler = StatusCybKMSHandler(service: mockServerService)
        let input = StatusCybKMSInput()

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "CybKMS server is running")
        XCTAssertTrue(output.running)
        XCTAssertEqual(output.pid, 12346)
        XCTAssertEqual(output.port, 8081)
        XCTAssertEqual(output.uptime, 1800)
    }
}