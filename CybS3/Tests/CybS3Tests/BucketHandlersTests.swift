import XCTest
@testable import CybS3Lib

final class BucketHandlersTests: XCTestCase {

    // MARK: - Create Bucket Handler Tests

    func testCreateBucketHandlerSuccess() async throws {
        // Given
        let mockBucketService = MockBucketOperationsService()
        mockBucketService.createResult = .success(BucketCreateOutput(
            success: true,
            message: "Bucket created successfully",
            bucket: "test-bucket"
        ))

        let handler = CreateBucketHandler(service: mockBucketService)
        let input = CreateBucketInput(
            name: "test-bucket",
            options: BucketCreateOptions()
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Bucket created successfully")
        XCTAssertEqual(output.bucket, "test-bucket")
    }

    func testCreateBucketHandlerFailure() async throws {
        // Given
        let mockBucketService = MockBucketOperationsService()
        mockBucketService.createResult = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bucket creation failed"]))

        let handler = CreateBucketHandler(service: mockBucketService)
        let input = CreateBucketInput(
            name: "test-bucket",
            options: BucketCreateOptions()
        )

        // When/Then
        do {
            _ = try await handler.handle(input: input)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TestError")
        }
    }

    // MARK: - List Buckets Handler Tests

    func testListBucketsHandlerSuccess() async throws {
        // Given
        let mockBucketService = MockBucketOperationsService()
        let expectedBuckets = [
            BucketInfo(name: "bucket1", creationDate: Date()),
            BucketInfo(name: "bucket2", creationDate: Date()),
            BucketInfo(name: "bucket3", creationDate: Date())
        ]
        mockBucketService.listResult = .success(BucketListOutput(
            success: true,
            message: "Buckets listed successfully",
            buckets: expectedBuckets
        ))

        let handler = ListBucketsHandler(service: mockBucketService)
        let input = ListBucketsInput(options: BucketListOptions())

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Buckets listed successfully")
        XCTAssertEqual(output.buckets.count, 3)
        XCTAssertEqual(output.buckets[0].name, "bucket1")
        XCTAssertEqual(output.buckets[1].name, "bucket2")
        XCTAssertEqual(output.buckets[2].name, "bucket3")
    }

    func testListBucketsHandlerEmpty() async throws {
        // Given
        let mockBucketService = MockBucketOperationsService()
        mockBucketService.listResult = .success(BucketListOutput(
            success: true,
            message: "No buckets found",
            buckets: []
        ))

        let handler = ListBucketsHandler(service: mockBucketService)
        let input = ListBucketsInput(options: BucketListOptions())

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "No buckets found")
        XCTAssertTrue(output.buckets.isEmpty)
    }

    // MARK: - Delete Bucket Handler Tests

    func testDeleteBucketHandlerSuccess() async throws {
        // Given
        let mockBucketService = MockBucketOperationsService()
        mockBucketService.deleteResult = .success(BucketDeleteOutput(
            success: true,
            message: "Bucket deleted successfully",
            bucket: "test-bucket"
        ))

        let handler = DeleteBucketHandler(service: mockBucketService)
        let input = DeleteBucketInput(
            name: "test-bucket",
            options: BucketDeleteOptions()
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Bucket deleted successfully")
        XCTAssertEqual(output.bucket, "test-bucket")
    }

    func testDeleteBucketHandlerFailure() async throws {
        // Given
        let mockBucketService = MockBucketOperationsService()
        mockBucketService.deleteResult = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bucket not empty"]))

        let handler = DeleteBucketHandler(service: mockBucketService)
        let input = DeleteBucketInput(
            name: "test-bucket",
            options: BucketDeleteOptions()
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