import Foundation

/// Protocol for bucket operations service
public protocol BucketOperationsServiceProtocol {
    func createBucket(name: String) async throws
    func deleteBucket(name: String) async throws
    func listBuckets() async throws -> [String]
}

/// Default implementation of bucket operations service
public class DefaultBucketOperationsService: BucketOperationsServiceProtocol {
    private let client: S3Client

    init(client: S3Client) {
        self.client = client
    }

    public func createBucket(name: String) async throws {
        try await client.createBucket(name: name)
    }

    public func deleteBucket(name: String) async throws {
        try await client.deleteBucket(name: name)
    }

    public func listBuckets() async throws -> [String] {
        try await client.listBuckets()
    }
}

/// Input/Output types for bucket handlers

public struct CreateBucketInput {
    public let bucketName: String
    public let vaultName: String?
}

public struct CreateBucketOutput {
    public let bucketName: String
    public let vaultName: String?
}

public struct DeleteBucketInput {
    public let bucketName: String
    public let vaultName: String?
    public let force: Bool
}

public struct DeleteBucketOutput {
    let bucketName: String
    let vaultName: String?
}

public struct ListBucketsInput {
    public let vaultName: String?
    public let json: Bool
}

public struct ListBucketsOutput {
    public let buckets: [String]
    public let vaultName: String?
    public let json: Bool
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

public class ListBucketsHandler {
    typealias Input = ListBucketsInput
    typealias Output = ListBucketsOutput

    private let service: BucketOperationsServiceProtocol

    public init(service: BucketOperationsServiceProtocol) {
        self.service = service
    }

    func handle(input: Input) async throws -> Output {
        let buckets = try await service.listBuckets()
        return Output(buckets: buckets, vaultName: input.vaultName, json: input.json)
    }
}