import XCTest
@testable import CybS3Lib

final class CoreHandlersTests: XCTestCase {

    // MARK: - Basic Setup Tests

    func testMockServiceInstantiation() {
        // Test that mock services can be instantiated
        let mockAuthService = MockAuthenticationService()
        XCTAssertNotNil(mockAuthService)
    }

    // MARK: - Login Handler Tests

    func testLoginHandlerSuccess() async throws {
        // Given
        let mockAuthService = MockAuthenticationService()
        mockAuthService.loginResult = .success(LoginOutput(success: true, message: "Login successful"))

        let handler = LoginHandler(authService: mockAuthService)
        let input = LoginInput(mnemonic: "test mnemonic")

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Login successful")
    }

    func testLoginHandlerFailure() async throws {
        // Given
        let mockAuthService = MockAuthenticationService()
        mockAuthService.loginResult = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid mnemonic"]))

        let handler = LoginHandler(authService: mockAuthService)
        let input = LoginInput(mnemonic: "invalid mnemonic")

        // When/Then
        do {
            _ = try await handler.handle(input: input)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TestError")
        }
    }

    // MARK: - Logout Handler Tests

    func testLogoutHandlerSuccess() async throws {
        // Given
        let mockAuthService = MockAuthenticationService()
        mockAuthService.logoutResult = .success(LogoutOutput(success: true, message: "Logout successful"))

        let handler = LogoutHandler(authService: mockAuthService)
        let input = LogoutInput()

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Logout successful")
    }

    func testLogoutHandlerFailure() async throws {
        // Given
        let mockAuthService = MockAuthenticationService()
        mockAuthService.logoutResult = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Logout failed"]))

        let handler = LogoutHandler(authService: mockAuthService)
        let input = LogoutInput()

        // When/Then
        do {
            _ = try await handler.handle(input: input)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TestError")
        }
    }

    // MARK: - Config Handler Tests

    func testConfigHandlerGetSuccess() async throws {
        // Given
        let mockConfigService = MockConfigurationService()
        mockConfigService.configResult = .success(ConfigOutput(
            success: true,
            message: "Configuration retrieved",
            vaults: ["vault1", "vault2"],
            currentVault: "vault1",
            accessKey: "test-key",
            secretKey: "test-secret"
        ))

        let handler = ConfigHandler(configService: mockConfigService)
        let input = ConfigInput(
            mnemonic: "test mnemonic",
            list: true,
            reset: false,
            accessKey: nil,
            secretKey: nil
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Configuration retrieved")
        XCTAssertEqual(output.vaults, ["vault1", "vault2"])
        XCTAssertEqual(output.currentVault, "vault1")
    }

    func testConfigHandlerSetSuccess() async throws {
        // Given
        let mockConfigService = MockConfigurationService()
        mockConfigService.configResult = .success(ConfigOutput(
            success: true,
            message: "Configuration updated",
            vaults: ["vault1"],
            currentVault: "vault1",
            accessKey: "new-key",
            secretKey: "new-secret"
        ))

        let handler = ConfigHandler(configService: mockConfigService)
        let input = ConfigInput(
            mnemonic: "test mnemonic",
            list: false,
            reset: false,
            accessKey: "new-key",
            secretKey: "new-secret"
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Configuration updated")
        XCTAssertEqual(output.accessKey, "new-key")
        XCTAssertEqual(output.secretKey, "new-secret")
    }

    func testConfigHandlerFailure() async throws {
        // Given
        let mockConfigService = MockConfigurationService()
        mockConfigService.configResult = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Configuration error"]))

        let handler = ConfigHandler(configService: mockConfigService)
        let input = ConfigInput(
            mnemonic: "test mnemonic",
            list: true,
            reset: false,
            accessKey: nil,
            secretKey: nil
        )

        // When/Then
        do {
            _ = try await handler.handle(input: input)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TestError")
        }
    }
}