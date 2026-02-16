import XCTest
@testable import CybS3Lib

final class MultiCloudTests: XCTestCase {
    func testCloudProviderEnum() {
        // Test all providers are defined
        let providers = CloudProvider.allCases
        XCTAssertGreaterThan(providers.count, 10, "Should have multiple cloud providers")

        // Test specific providers
        XCTAssertTrue(providers.contains(.aws))
        XCTAssertTrue(providers.contains(.gcp))
        XCTAssertTrue(providers.contains(.azure))
        XCTAssertTrue(providers.contains(.minio))
    }

    func testCloudProviderDisplayNames() {
        XCTAssertEqual(CloudProvider.aws.displayName, "Amazon Web Services S3")
        XCTAssertEqual(CloudProvider.gcp.displayName, "Google Cloud Storage")
        XCTAssertEqual(CloudProvider.azure.displayName, "Microsoft Azure Blob Storage")
    }

    func testCloudProviderCompatibility() {
        // S3 compatible providers
        XCTAssertTrue(CloudProvider.aws.isS3Compatible)
        XCTAssertTrue(CloudProvider.minio.isS3Compatible)
        XCTAssertTrue(CloudProvider.wasabi.isS3Compatible)

        // Non-S3 compatible providers
        XCTAssertFalse(CloudProvider.gcp.isS3Compatible)
        XCTAssertFalse(CloudProvider.azure.isS3Compatible)
    }

    func testCloudConfigValidation() {
        let config = CloudConfig(
            provider: .aws,
            accessKey: "test-key",
            secretKey: "test-secret",
            region: "us-east-1"
        )

        XCTAssertNoThrow(try config.validate())
    }

    func testCloudConfigValidationFailure() {
        let invalidConfig = CloudConfig(
            provider: .aws,
            accessKey: "",
            secretKey: "test-secret",
            region: "us-east-1"
        )

        XCTAssertThrowsError(try invalidConfig.validate())
    }

    func testS3EndpointGeneration() {
        let config = CloudConfig(
            provider: .aws,
            accessKey: "test",
            secretKey: "test",
            region: "us-west-2"
        )

        let endpoint = config.toS3Endpoint()
        XCTAssertEqual(endpoint.host, "s3.us-west-2.amazonaws.com")
        XCTAssertEqual(endpoint.port, 443)
        XCTAssertTrue(endpoint.useSSL)
    }

    func testCustomEndpoint() {
        let config = CloudConfig(
            provider: .minio,
            accessKey: "test",
            secretKey: "test",
            region: "us-east-1",
            customEndpoint: "https://minio.example.com:9000"
        )

        let endpoint = config.toS3Endpoint()
        XCTAssertEqual(endpoint.host, "minio.example.com")
        XCTAssertEqual(endpoint.port, 9000)
        XCTAssertTrue(endpoint.useSSL)
    }

    func testCloudClientFactoryS3Compatible() {
        let config = CloudConfig(
            provider: .aws,
            accessKey: "test",
            secretKey: "test",
            region: "us-east-1"
        )

        XCTAssertNoThrow(try CloudClientFactory.createS3Client(config: config))
    }

    // Note: GCP and Azure client tests would require actual credentials
    // These are integration tests that would be run separately
    func testCloudClientFactoryGCP() {
        let config = CloudConfig(
            provider: .gcp,
            accessKey: "test-project",
            secretKey: "test-key",
            region: "us-central1"
        )

        // This should create a GCPClient without throwing
        XCTAssertNoThrow(try CloudClientFactory.createCloudClient(config: config))
    }

    func testCloudClientFactoryAzure() {
        let config = CloudConfig(
            provider: .azure,
            accessKey: "testaccount",
            secretKey: "testkey",
            region: "eastus"
        )

        // This should create an AzureClient without throwing
        XCTAssertNoThrow(try CloudClientFactory.createCloudClient(config: config))
    }
}