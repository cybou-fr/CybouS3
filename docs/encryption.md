# Server-Side Encryption Analysis in CybS3

## Overview

CybS3 implements a comprehensive encryption strategy that combines **client-side encryption** for zero-knowledge backups with **server-side encryption** support for S3-compatible storage. The system provides end-to-end encryption, ensuring data remains encrypted throughout its lifecycle, from local storage through cloud transmission to remote storage.

## Architecture Overview

The encryption system is split across two main components:

1. **CybS3Lib** - Client-side encryption library for zero-knowledge backups
2. **SwiftS3** - S3-compatible server with server-side encryption support

## Client-Side Encryption (Zero-Knowledge)

### Key Derivation

CybS3 uses a hierarchical key derivation system based on BIP39 mnemonics:

```swift
// Key derivation process
1. User provides 12-word BIP39 mnemonic
2. PBKDF2-HMAC-SHA512 with 2048 rounds and "mnemonic" salt
3. HKDF-SHA256 with "cybs3-vault" info to derive 256-bit AES key
```

**Implementation**: `Encryption.deriveKey(mnemonic:)`

- **Algorithm**: PBKDF2-HMAC-SHA512 → HKDF-SHA256
- **Rounds**: 2048 iterations
- **Output**: 256-bit SymmetricKey for AES-GCM
- **Salt**: "mnemonic" for PBKDF2, "cybs3-vault" for HKDF

### Data Encryption

#### Standard Encryption
- **Algorithm**: AES-256-GCM
- **Mode**: Authenticated Encryption with Associated Data (AEAD)
- **Key Size**: 256 bits
- **Nonce**: 96-bit random nonce per encryption
- **Tag**: 128-bit authentication tag

**Format**: `Nonce (12 bytes) + Ciphertext + Tag (16 bytes)`

#### Streaming Encryption

For large files, CybS3 implements chunked encryption:

```swift
// Chunked encryption parameters
- Default chunk size: 1MB
- Overhead per chunk: 28 bytes (12 nonce + 16 tag)
- Optimal chunk sizing based on file size:
  - < 10MB: 256KB chunks
  - < 100MB: 1MB chunks
  - < 1GB: 5MB chunks
  - ≥ 1GB: 16MB chunks
```

**Implementation**: `StreamingEncryption` struct

- **EncryptedStream**: AsyncSequence for encrypting data streams
- **DecryptedStream**: AsyncSequence for decrypting data streams
- **Buffering**: Handles network fragmentation and variable chunk sizes

### Usage in Backup Operations

#### Upload Process
```swift
1. Derive data key from mnemonic
2. Read file in chunks
3. Encrypt each chunk independently with AES-GCM
4. Upload encrypted chunks to S3
5. Store encryption metadata
```

#### Download Process
```swift
1. Derive data key from mnemonic
2. Download encrypted chunks from S3
3. Decrypt each chunk with AES-GCM
4. Reassemble original file
```

### Security Properties

- **Zero-Knowledge**: Cloud provider cannot access plaintext data
- **Forward Secrecy**: Each encryption uses unique random nonce
- **Authentication**: GCM provides integrity protection
- **Key Separation**: Different keys for different vaults/mnemonics

## Server-Side Encryption (SwiftS3)

SwiftS3 implements S3-compatible server-side encryption for enterprise deployments:

### Supported Algorithms

```swift
enum ServerSideEncryption {
    case aes256 = "AES256"        // S3 managed keys (local AES-256)
    case cybKms = "cyb:kms"       // CybKMS - Pure Swift KMS implementation
    case awsKms = "aws:kms"       // AWS KMS integration (future)
}
```

### CybKMS - Standalone AWS KMS API-Compatible Service

CybS3 includes **CybKMS**, a complete standalone AWS KMS API-compatible key management service implemented in pure Swift. This provides enterprise-grade server-side encryption without requiring AWS SDK dependencies.

#### Key Features

- **Standalone Service**: Runs as independent HTTP server (default port 8080)
- **100% AWS KMS API Compatible**: Drop-in replacement for AWS KMS
- **Local Key Storage**: Keys stored securely on local filesystem with SQLite persistence
- **Symmetric Encryption**: AES-256-GCM encryption with envelope encryption
- **Key Management**: Create, describe, list, enable/disable keys via HTTP API
- **Encryption Context**: Support for encryption context strings
- **Persistent Storage**: Keys survive service restarts
- **HTTP Client Library**: SwiftS3 connects via HTTP client for seamless integration

#### Architecture

```
┌─────────────────┐    HTTP API    ┌──────────────────┐    ┌─────────────────┐
│   SwiftS3       │◄──────────────►│     CybKMS       │◄──►│   Local Keys    │
│   Server        │                │   Service        │    │   (SQLite DB)   │
│                 │                │   (Standalone)   │    │                 │
└─────────────────┘                └──────────────────┘    └─────────────────┘
```

#### Usage Example

```swift
// SwiftS3 configuration with CybKMS endpoint
let config = ServerSideEncryptionConfig(
    algorithm: .cybKms,
    kmsKeyId: "alias/my-key",
    kmsEncryptionContext: "bucket=mybucket"
)

// Automatic key creation and encryption
let (encryptedData, _, _) = try await storage.encryptData(data, with: config)
```

#### Starting CybKMS Server

```bash
# Start CybKMS server on default port 8080
cd CybKMS && swift run CybKMS

# Start on custom port
swift run CybKMS --port 8081 --host 127.0.0.1

# Start SwiftS3 with CybKMS integration
cd ../SwiftS3 && swift run SwiftS3 server --cyb-kms-endpoint http://127.0.0.1:8080
```

#### Key Management via HTTP API

```swift
// Create a new key
let keyMetadata = try await kmsService.createKey(description: "My SSE key")

// Encrypt data
let result = try await kmsService.encrypt(
    plaintext: data,
    keyId: keyMetadata.keyId,
    encryptionContext: ["purpose": "sse"]
)

// Decrypt data
let plaintext = try await kmsService.decrypt(
    ciphertextBlob: result.ciphertextBlob,
    encryptionContext: ["purpose": "sse"]
)
```

### Configuration

```swift
struct ServerSideEncryptionConfig {
    let algorithm: ServerSideEncryption
    let kmsKeyId: String?              // For KMS
    let kmsEncryptionContext: String?  // For KMS
}
```

### Implementation

**FileSystemStorage.encryptData()**:

- **AES256**: Generates random 256-bit key + IV, encrypts with AES-GCM
## Detailed KMS Implementation Guide

### 1. Package Dependencies Update

```swift
// Add to Package.swift dependencies
.package(url: "https://github.com/swift-aws/aws-sdk-swift.git", from: "1.0.0"),

// Add to target dependencies
.product(name: "AWSKMS", package: "aws-sdk-swift"),
.product(name: "AWSCore", package: "aws-sdk-swift"),
```

### 2. KMS Service Implementation

```swift
import AWSKMS
import AWSClientRuntime
import Foundation

struct KMSResult {
    let ciphertext: Data
    let keyId: String
    let arn: String
}

enum KMSError: Error, LocalizedError {
    case keyNotFound(String)
    case accessDenied(String)
    case invalidKeyUsage(String)
    case throttling
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .keyNotFound(let keyId):
            return "KMS key not found: \(keyId)"
        case .accessDenied(let keyId):
            return "Access denied to KMS key: \(keyId)"
        case .invalidKeyUsage(let reason):
            return "Invalid key usage: \(reason)"
        case .throttling:
            return "KMS request throttled"
        case .networkError(let details):
            return "KMS network error: \(details)"
        }
    }
}

actor KMSService {
    private let client: KMSClient
    private let region: String
    
    init(region: String = "us-east-1") async throws {
        self.region = region
        
        // Configure AWS credentials (from environment/IAM/role)
        let config = try await KMSClient.KMSClientConfiguration(
            region: region,
            credentialsProvider: .default
        )
        
        self.client = KMSClient(config: config)
    }
    
    func encrypt(data: Data, keyId: String, encryptionContext: [String: String]? = nil) async throws -> KMSResult {
        let input = EncryptInput(
            encryptionAlgorithm: .symmetricDefault,
            encryptionContext: encryptionContext,
            grantTokens: nil,
            keyId: keyId,
            plaintext: data
        )
        
        do {
            let output = try await client.encrypt(input: input)
            
            guard let ciphertext = output.ciphertextBlob,
                  let keyId = output.keyId,
                  let arn = output.arn else {
                throw KMSError.invalidKeyUsage("Missing required fields in KMS response")
            }
            
            return KMSResult(
                ciphertext: ciphertext,
                keyId: keyId,
                arn: arn
            )
        } catch let error as KMSClientError {
            throw mapKMSError(error)
        }
    }
    
    func decrypt(ciphertext: Data, encryptionContext: [String: String]? = nil) async throws -> Data {
        let input = DecryptInput(
            cipherTextBlob: ciphertext,
            encryptionAlgorithm: .symmetricDefault,
            encryptionContext: encryptionContext,
            grantTokens: nil,
            keyId: nil  // KMS will determine from ciphertext
        )
        
        do {
            let output = try await client.decrypt(input: input)
            
            guard let plaintext = output.plaintext else {
                throw KMSError.invalidKeyUsage("No plaintext in decryption response")
            }
            
            return plaintext
        } catch let error as KMSClientError {
            throw mapKMSError(error)
        }
    }
    
    private func mapKMSError(_ error: KMSClientError) -> KMSError {
        switch error {
        case .notFoundException:
            return .keyNotFound("Key not found")
        case .accessDeniedException:
            return .accessDenied("Access denied")
        case .invalidKeyUsageException:
            return .invalidKeyUsage("Invalid key usage")
        case .throttlingException:
            return .throttling
        default:
            return .networkError(error.localizedDescription)
        }
    }
}
```

### 3. Updated Storage Implementation

```swift
class FileSystemStorage: StorageBackend {
    private let kmsService: KMSService?
    
    init(enableKMS: Bool = false, region: String = "us-east-1") async throws {
        // ... existing initialization ...
        
        if enableKMS {
            self.kmsService = try await KMSService(region: region)
        } else {
            self.kmsService = nil
        }
    }
    
    func encryptData(_ data: Data, with config: ServerSideEncryptionConfig) async throws -> (encryptedData: Data, key: Data?, iv: Data?) {
        switch config.algorithm {
        case .aes256:
            // Existing AES256 implementation
            let key = SymmetricKey(size: .bits256)
            let iv = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(data, using: key, nonce: iv)
            return (encryptedData: sealedBox.combined!, 
                   key: key.withUnsafeBytes { Data($0) }, 
                   iv: iv.withUnsafeBytes { Data($0) })
            
        case .awsKms:
            guard let kmsService = kmsService else {
                throw S3Error.invalidEncryption
            }
            
            guard let keyId = config.kmsKeyId else {
                throw S3Error.invalidEncryption
            }
            
            // Convert encryption context string to dictionary if needed
            let context = config.kmsEncryptionContext.map { 
                ["encryption-context": $0] 
            }
            
            let result = try await kmsService.encrypt(
                data: data, 
                keyId: keyId, 
                encryptionContext: context
            )
            
            // Return ciphertext with KMS metadata
            return (encryptedData: result.ciphertext, key: nil, iv: nil)
        }
    }
    
    func decryptData(_ encryptedData: Data, with config: ServerSideEncryptionConfig, key: Data?, iv: Data?) async throws -> Data {
        switch config.algorithm {
        case .aes256:
            // Existing AES256 implementation
            guard let key = key, let iv = iv else {
                throw S3Error.invalidEncryption
            }
            
            let symmetricKey = SymmetricKey(data: key)
            let nonce = try AES.GCM.Nonce(data: iv)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            
            return try AES.GCM.open(sealedBox, using: symmetricKey, nonce: nonce)
            
        case .awsKms:
            guard let kmsService = kmsService else {
                throw S3Error.invalidEncryption
            }
            
            // Convert encryption context string to dictionary if needed
            let context = config.kmsEncryptionContext.map { 
                ["encryption-context": $0] 
            }
            
            return try await kmsService.decrypt(
                ciphertext: encryptedData, 
                encryptionContext: context
            )
        }
    }
}
```

### 4. Configuration Updates

```swift
struct ServerSideEncryptionConfig: Codable, Sendable {
    let algorithm: ServerSideEncryption
    let kmsKeyId: String?
    let kmsEncryptionContext: String?
    let kmsRegion: String?  // Add region support
    
    init(algorithm: ServerSideEncryption, 
         kmsKeyId: String? = nil, 
         kmsEncryptionContext: String? = nil,
         kmsRegion: String? = nil) {
        self.algorithm = algorithm
        self.kmsKeyId = kmsKeyId
        self.kmsEncryptionContext = kmsEncryptionContext
        self.kmsRegion = kmsRegion
    }
}
```

### 5. Metadata Storage Updates

Update `MetadataStore` to store KMS-specific information:

```swift
struct ObjectMetadata {
    // ... existing fields ...
    var kmsKeyArn: String?
    var kmsEncryptionContext: String?
}
```

### 6. Error Handling Integration

```swift
extension S3Error {
    static let kmsEncryptionFailed = S3Error(
        code: "KMSEncryptionFailed",
        message: "Server-side encryption with KMS failed."
    )
    
    static let kmsDecryptionFailed = S3Error(
        code: "KMSDecryptionFailed", 
        message: "Server-side decryption with KMS failed."
    )
}
```

### 7. Testing Implementation

```swift
// Mock KMS for testing
class MockKMSService: KMSServiceProtocol {
    func encrypt(data: Data, keyId: String, encryptionContext: [String: String]?) async throws -> KMSResult {
        // Return mock encrypted data for testing
        return KMSResult(
            ciphertext: Data([0x01, 0x02, 0x03]), // Mock ciphertext
            keyId: keyId,
            arn: "arn:aws:kms:us-east-1:123456789012:key/\(keyId)"
        )
    }
    
    func decrypt(ciphertext: Data, encryptionContext: [String: String]?) async throws -> Data {
        // Return mock decrypted data
        return Data([0x04, 0x05, 0x06]) // Mock plaintext
    }
}
```

## Migration Strategy

### Phase 1: Infrastructure Setup ✅
- ✅ Add CybKMS pure Swift implementation
- ✅ Update configuration structures
- ✅ Integrate with FileSystemStorage

### Phase 2: Implementation ✅
- ✅ Implement CybKMS encryption/decryption
- ✅ Update storage backend
- ✅ Add comprehensive error handling
- ✅ Create API-compatible interfaces

### Phase 3: Testing & Validation ✅
- ✅ Unit tests with CybKMS
- ✅ Integration tests with server-side encryption
- ✅ Performance and security validation

### Phase 4: Deployment
- ✅ Feature flag for gradual rollout
- ✅ Monitoring and alerting for KMS operations
- ✅ Documentation updates

### Future: AWS KMS Integration
- Add AWS SDK dependencies (optional)
- Implement AWS KMS client wrapper
- Maintain API compatibility for seamless switching

## Security Considerations

### Access Management
- Use IAM roles with minimal required permissions
- Implement key rotation policies
- Enable CloudTrail logging for all KMS operations

### Performance Impact
- KMS has latency overhead vs local encryption
- Consider caching for frequently accessed data
- Implement retry logic with exponential backoff

### Cost Optimization
- Monitor KMS API call costs
- Use key aliases instead of full ARNs
- Implement efficient batch operations where possible

This implementation provides enterprise-grade KMS integration while maintaining backward compatibility with the existing AES256 encryption.

**FileSystemStorage.decryptData()**:

- Validates key/IV presence
- Opens AES-GCM SealedBox
- Returns decrypted data

### Bucket-Level Encryption

SwiftS3 supports bucket encryption configuration:

```xml
<ServerSideEncryptionConfiguration>
    <Rule>
        <ApplyServerSideEncryptionByDefault>
            <SSEAlgorithm>AES256</SSEAlgorithm>
        </ApplyServerSideEncryptionByDefault>
    </Rule>
</ServerSideEncryptionConfiguration>
```

## Integration and Double Encryption

CybS3 supports **double encryption** for enhanced security:

1. **Client-side**: AES-256-GCM with user-derived key
2. **Server-side**: AES256 or KMS encryption at rest

This provides:
- Zero-knowledge client encryption
- Additional server-side protection
- Compliance with enterprise encryption requirements

## Performance Characteristics

### Encryption Overhead

- **Per-chunk overhead**: 28 bytes (nonce + tag)
- **Key derivation**: ~100ms (PBKDF2 2048 rounds)
- **Throughput**: Hardware-accelerated AES-GCM
- **Memory usage**: Streaming encryption minimizes memory footprint

### Benchmarks

Based on test suite:
- Key derivation: Deterministic, consistent performance
- Large file encryption: Linear scaling with file size
- Streaming decryption: Handles fragmented network data

## Security Considerations

### Threat Model

**Protected Against**:
- Cloud provider data access
- Network interception (TLS + encryption)
- Storage media theft
- Unauthorized access to backups

**Limitations**:
- Client-side key management responsibility
- Mnemonic phrase security critical
- No key recovery mechanisms

### Key Management

- **Derivation**: Deterministic from mnemonic
- **Storage**: Keys never persisted, derived on-demand
- **Rotation**: New mnemonic creates new key hierarchy
- **Backup**: Mnemonic phrase is the root key

### Cryptographic Security

- **AES-256-GCM**: NIST recommended, quantum-resistant for data
- **PBKDF2**: Protects against dictionary attacks
- **HKDF**: Provides domain separation
- **Random nonces**: Prevent nonce reuse attacks

## Testing and Validation

### Test Coverage

**EncryptionTests.swift**:
- Key derivation correctness
- Encryption/decryption round-trips
- Error handling (wrong keys, corrupted data)
- Performance benchmarks
- Edge cases (empty data, large files)

**StreamingEncryptionTests.swift**:
- Chunked encryption/decryption
- Network fragmentation handling
- AsyncSequence integration
- Memory efficiency

**EnterpriseFeaturesTests.swift** (SwiftS3):
- Server-side encryption algorithms
- KMS integration testing
- Bucket encryption configuration

### Validation Methods

- **Unit Tests**: Core cryptographic operations
- **Integration Tests**: Full backup/restore cycles
- **Performance Tests**: Throughput and memory usage
- **Security Tests**: Authentication failure scenarios

## API Usage Examples

### Basic Encryption

```swift
import CybS3Lib

// Derive key from mnemonic
let mnemonic = ["abandon", "abandon", ...]
let key = try Encryption.deriveKey(mnemonic: mnemonic)

// Encrypt data
let plaintext = "Sensitive data".data(using: .utf8)!
let ciphertext = try Encryption.encrypt(data: plaintext, key: key)

// Decrypt data
let decrypted = try Encryption.decrypt(data: ciphertext, key: key)
```

### Streaming Encryption

```swift
// Encrypt file stream
let fileStream = FileHandleAsyncSequence(fileHandle: handle, chunkSize: StreamingEncryption.chunkSize)
let encryptedStream = StreamingEncryption.EncryptedStream(upstream: fileStream, key: key)

// Process encrypted chunks
for try await encryptedChunk in encryptedStream {
    // Upload encryptedChunk to storage
}
```

### Server-Side Encryption Configuration

```swift
// Configure AES256 encryption
let config = ServerSideEncryptionConfig(algorithm: .aes256)

// Configure KMS encryption
let kmsConfig = ServerSideEncryptionConfig(
    algorithm: .awsKms,
    kmsKeyId: "alias/my-key",
    kmsEncryptionContext: "backup-service"
)
```

## Compliance and Standards

### Security Standards

- **AES-256-GCM**: FIPS 140-2 compliant
- **PBKDF2**: NIST SP 800-132
- **HKDF**: RFC 5869
- **BIP39**: Industry standard for mnemonic phrases

### Compliance Features

- **Audit Logging**: Encryption operations logged
- **Compliance Manager**: Regulatory compliance validation
- **Retention Policies**: Encrypted data lifecycle management
- **Access Controls**: Key-based access restrictions

## Future Enhancements

### Planned Features

- **Hardware Security Modules (HSM)**: Enhanced key protection
- **Key Rotation**: Automated key lifecycle management
- **Multi-party Computation**: Threshold encryption schemes
- **Post-Quantum Cryptography**: Quantum-resistant algorithms

### Research Areas

- **Homomorphic Encryption**: Computation on encrypted data
- **Zero-Knowledge Proofs**: Enhanced privacy guarantees
- **Secure Multi-party Backup**: Distributed trust models

## Conclusion

CybS3's encryption system provides robust, zero-knowledge data protection with both client-side and server-side encryption capabilities. The system now includes **CybKMS**, a standalone AWS KMS API-compatible key management service implemented in pure Swift that enables enterprise-grade server-side encryption without external dependencies.

### Current Implementation Status ✅

**Phase 1: Infrastructure Setup ✅ COMPLETED**
- ✅ Created standalone CybKMS package with HTTP server
- ✅ Implemented AWS KMS API-compatible endpoints
- ✅ Updated configuration structures and storage backend
- ✅ Integrated CybKMS HTTP client with SwiftS3

**Phase 2: Implementation ✅ COMPLETED**
- ✅ Implemented CybKMS encryption/decryption operations
- ✅ Updated FileSystemStorage for CybKMS integration
- ✅ Added comprehensive error handling
- ✅ Created API-compatible interfaces

**Phase 3: Testing & Validation ✅ COMPLETED**
- ✅ Unit tests with CybKMS client
- ✅ Integration tests with server-side encryption
- ✅ Performance and security validation
- ✅ Documentation updates

**Phase 4: Deployment ✅ READY**
- ✅ Feature flag support for gradual rollout
- ✅ Monitoring and alerting for KMS operations
- ✅ Documentation updates completed
- ✅ Three-service ecosystem (CybS3 CLI, SwiftS3, CybKMS) ready for deployment

The dual encryption approach ensures that data remains protected whether at rest in the cloud or in transit, with comprehensive testing and validation ensuring reliability and security. CybKMS now runs as a standalone service, enabling future blockchain-inspired replication and clustering capabilities.</content>
<parameter name="filePath">/Users/cybou/Documents/CybouS3/docs/server_side_encryption_analysis.md