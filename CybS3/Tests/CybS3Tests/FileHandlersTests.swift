import XCTest
@testable import CybS3Lib

final class FileHandlersTests: XCTestCase {

    // MARK: - Upload Handler Tests

    func testUploadHandlerSuccess() async throws {
        // Given
        let mockFileService = MockFileOperationsService()
        mockFileService.uploadResult = .success(FileUploadOutput(
            success: true,
            message: "File uploaded successfully",
            filePath: "/test/file.txt",
            bucket: "test-bucket",
            key: "file.txt",
            size: 1024
        ))

        let handler = UploadHandler(fileService: mockFileService)
        let input = UploadInput(
            localPath: "/test/file.txt",
            bucket: "test-bucket",
            key: nil,
            options: UploadOptions()
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "File uploaded successfully")
        XCTAssertEqual(output.filePath, "/test/file.txt")
        XCTAssertEqual(output.bucket, "test-bucket")
        XCTAssertEqual(output.size, 1024)
    }

    func testUploadHandlerFailure() async throws {
        // Given
        let mockFileService = MockFileOperationsService()
        mockFileService.uploadResult = .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"]))

        let handler = UploadHandler(fileService: mockFileService)
        let input = UploadInput(
            localPath: "/test/file.txt",
            bucket: "test-bucket",
            key: nil,
            options: UploadOptions()
        )

        // When/Then
        do {
            _ = try await handler.handle(input: input)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).domain, "TestError")
        }
    }

    // MARK: - Download Handler Tests

    func testDownloadHandlerSuccess() async throws {
        // Given
        let mockFileService = MockFileOperationsService()
        mockFileService.downloadResult = .success(FileDownloadOutput(
            success: true,
            message: "File downloaded successfully",
            localPath: "/local/file.txt",
            remotePath: "s3://test-bucket/file.txt",
            size: 2048
        ))

        let handler = DownloadHandler(fileService: mockFileService)
        let input = DownloadInput(
            remotePath: "s3://test-bucket/file.txt",
            localPath: "/local/file.txt",
            options: DownloadOptions()
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "File downloaded successfully")
        XCTAssertEqual(output.localPath, "/local/file.txt")
        XCTAssertEqual(output.remotePath, "s3://test-bucket/file.txt")
        XCTAssertEqual(output.size, 2048)
    }

    // MARK: - List Handler Tests

    func testListHandlerSuccess() async throws {
        // Given
        let mockFileService = MockFileOperationsService()
        let expectedFiles = [
            FileInfo(name: "file1.txt", size: 100, lastModified: Date(), etag: "etag1"),
            FileInfo(name: "file2.txt", size: 200, lastModified: Date(), etag: "etag2")
        ]
        mockFileService.listResult = .success(FileListOutput(
            success: true,
            message: "Files listed successfully",
            files: expectedFiles,
            totalSize: 300
        ))

        let handler = ListHandler(fileService: mockFileService)
        let input = ListInput(
            bucket: "test-bucket",
            prefix: nil,
            options: ListOptions()
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Files listed successfully")
        XCTAssertEqual(output.files.count, 2)
        XCTAssertEqual(output.files[0].name, "file1.txt")
        XCTAssertEqual(output.files[1].name, "file2.txt")
        XCTAssertEqual(output.totalSize, 300)
    }

    // MARK: - Delete Handler Tests

    func testDeleteHandlerSuccess() async throws {
        // Given
        let mockFileService = MockFileOperationsService()
        mockFileService.deleteResult = .success(FileDeleteOutput(
            success: true,
            message: "File deleted successfully",
            deletedFiles: ["file1.txt", "file2.txt"]
        ))

        let handler = DeleteHandler(fileService: mockFileService)
        let input = DeleteInput(
            paths: ["s3://bucket/file1.txt", "s3://bucket/file2.txt"],
            options: DeleteOptions()
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "File deleted successfully")
        XCTAssertEqual(output.deletedFiles, ["file1.txt", "file2.txt"])
    }

    // MARK: - Sync Handler Tests

    func testSyncHandlerSuccess() async throws {
        // Given
        let mockFileService = MockFileOperationsService()
        mockFileService.syncResult = .success(FileSyncOutput(
            success: true,
            message: "Sync completed successfully",
            uploaded: 5,
            downloaded: 3,
            deleted: 1,
            errors: []
        ))

        let handler = SyncHandler(fileService: mockFileService)
        let input = SyncInput(
            localPath: "/local/dir",
            bucket: "test-bucket",
            options: SyncOptions()
        )

        // When
        let output = try await handler.handle(input: input)

        // Then
        XCTAssertTrue(output.success)
        XCTAssertEqual(output.message, "Sync completed successfully")
        XCTAssertEqual(output.uploaded, 5)
        XCTAssertEqual(output.downloaded, 3)
        XCTAssertEqual(output.deleted, 1)
        XCTAssertTrue(output.errors.isEmpty)
    }
}