import CybS3Lib
import Foundation

/// Protocol for bucket operations service
protocol BucketOperationsServiceProtocol {
    func createBucket(name: String) async throws
    func deleteBucket(name: String) async throws
    func listBuckets() async throws -> [String]
}

/// Default implementation of bucket operations service
class DefaultBucketOperationsService: BucketOperationsServiceProtocol {
    private let client: S3Client

    init(client: S3Client) {
        self.client = client
    }

    func createBucket(name: String) async throws {
        try await client.createBucket(name: name)
    }

    func deleteBucket(name: String) async throws {
        try await client.deleteBucket(name: name)
    }

    func listBuckets() async throws -> [String] {
        try await client.listBuckets()
    }
}

/// Input/Output types for bucket handlers

struct CreateBucketInput {
    let bucketName: String
    let vaultName: String?
}

struct CreateBucketOutput {
    let bucketName: String
    let vaultName: String?
}

struct DeleteBucketInput {
    let bucketName: String
    let vaultName: String?
    let force: Bool
}

struct DeleteBucketOutput {
    let bucketName: String
    let vaultName: String?
}

struct ListBucketsInput {
    let vaultName: String?
    let json: Bool
}

struct ListBucketsOutput {
    let buckets: [String]
    let vaultName: String?
    let json: Bool
}

/// Bucket operation handlers

class CreateBucketHandler {
    typealias Input = CreateBucketInput
    typealias Output = CreateBucketOutput

    private let service: BucketOperationsServiceProtocol

    init(service: BucketOperationsServiceProtocol) {
        self.service = service
    }

    func handle(input: Input) async throws -> Output {
        try await service.createBucket(name: input.bucketName)
        return Output(bucketName: input.bucketName, vaultName: input.vaultName)
    }
}

class DeleteBucketHandler {
    typealias Input = DeleteBucketInput
    typealias Output = DeleteBucketOutput

    private let service: BucketOperationsServiceProtocol

    init(service: BucketOperationsServiceProtocol) {
        self.service = service
    }

    func handle(input: Input) async throws -> Output {
        try await service.deleteBucket(name: input.bucketName)
        return Output(bucketName: input.bucketName, vaultName: input.vaultName)
    }
}

class ListBucketsHandler {
    typealias Input = ListBucketsInput
    typealias Output = ListBucketsOutput

    private let service: BucketOperationsServiceProtocol

    init(service: BucketOperationsServiceProtocol) {
        self.service = service
    }

    func handle(input: Input) async throws -> Output {
        let buckets = try await service.listBuckets()
        return Output(buckets: buckets, vaultName: input.vaultName, json: input.json)
    }
}