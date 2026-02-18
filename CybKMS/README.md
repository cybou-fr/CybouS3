# CybKMS

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
[![Linux](https://img.shields.io/badge/Linux-Compatible-green.svg)](https://www.linux.org/)

**CybKMS** is a standalone AWS KMS API-compatible key management service written in pure Swift. It provides enterprise-grade server-side encryption capabilities without requiring AWS SDK dependencies.

## Overview

CybKMS implements the full AWS KMS API surface, allowing it to serve as a drop-in replacement for AWS KMS in development, testing, and enterprise environments. It runs as an independent HTTP service that can be deployed alongside SwiftS3 or other S3-compatible storage systems.

## Features

- **100% AWS KMS API Compatible**: Full implementation of KMS operations (CreateKey, DescribeKey, ListKeys, Encrypt, Decrypt, etc.)
- **Standalone HTTP Server**: Runs independently on configurable host/port
- **Pure Swift Implementation**: No external dependencies on AWS SDK
- **SQLite Persistence**: Keys stored securely with metadata persistence
- **Symmetric Encryption**: AES-256-GCM with envelope encryption
- **Key Management**: Complete key lifecycle management (create, enable, disable, describe)
- **Encryption Context**: Support for encryption context strings and maps
- **HTTP Client Library**: Included client for easy integration with SwiftS3
- **Actor-Based Concurrency**: Thread-safe operations using Swift actors
- **Comprehensive Logging**: Structured logging with configurable levels

## Architecture

```
┌─────────────────┐    HTTP API    ┌──────────────────┐    ┌─────────────────┐
│   SwiftS3       │◄──────────────►│     CybKMS       │◄──►│   SQLite DB     │
│   Server        │                │   HTTP Server    │    │   (Keys &       │
│                 │                │   (Hummingbird)  │    │   Metadata)     │
└─────────────────┘                └──────────────────┘    └─────────────────┘
```

## Quick Start

### Prerequisites
- Swift 6.0+ (tested with Swift 6.2.3)
- macOS 14.0+ or Linux (Ubuntu 20.04+, CentOS 8+, etc.)

### Installation

```bash
# Clone CybouS3 repository
git clone https://github.com/cybou-fr/CybouS3.git
cd CybouS3/CybKMS

# Build CybKMS
swift build -c release

# Run CybKMS server
swift run CybKMS
```

### Basic Usage

```bash
# Start CybKMS on default port 8080
swift run CybKMS

# Start on custom port and host
swift run CybKMS --port 8081 --host 127.0.0.1

# Enable debug logging
swift run CybKMS --log-level debug

# Show help
swift run CybKMS --help
```

### Integration with SwiftS3

```bash
# Start CybKMS server
cd CybKMS && swift run CybKMS --port 8081 &

# Start SwiftS3 with CybKMS integration
cd ../SwiftS3 && swift run SwiftS3 server --cyb-kms-endpoint http://127.0.0.1:8081
```

## API Reference

CybKMS implements the following AWS KMS API operations:

### Key Management
- `CreateKey` - Create a new KMS key
- `DescribeKey` - Get detailed information about a key
- `ListKeys` - List all keys in the account
- `EnableKey` - Enable a disabled key
- `DisableKey` - Disable a key (prevents encryption)

### Cryptographic Operations
- `Encrypt` - Encrypt plaintext data
- `Decrypt` - Decrypt ciphertext data
- `ReEncrypt` - Re-encrypt data under a different key

### Key Rotation
- `RotateKey` - Rotate the key material (future implementation)

## HTTP API Examples

### Create a Key
```bash
curl -X POST http://localhost:8080/CreateKey \
  -H "Content-Type: application/json" \
  -d '{"description": "My test key"}'
```

### Encrypt Data
```bash
curl -X POST http://localhost:8080/Encrypt \
  -H "Content-Type: application/json" \
  -d '{
    "keyId": "alias/my-key",
    "plaintext": "SGVsbG8gV29ybGQ=",
    "encryptionContext": {"purpose": "test"}
  }'
```

### Decrypt Data
```bash
curl -X POST http://localhost:8080/Decrypt \
  -H "Content-Type: application/json" \
  -d '{
    "ciphertextBlob": "AQ...",
    "encryptionContext": {"purpose": "test"}
  }'
```

## Swift Client Usage

```swift
import CybKMSClient

// Initialize client
let client = try CybKMSClient(endpoint: "http://localhost:8080")

// Create a key
let key = try await client.createKey(description: "My SSE key")

// Encrypt data
let plaintext = "Sensitive data".data(using: .utf8)!
let encrypted = try await client.encrypt(
    plaintext: plaintext,
    keyId: key.keyId,
    encryptionContext: ["purpose": "sse"]
)

// Decrypt data
let decrypted = try await client.decrypt(
    ciphertextBlob: encrypted.ciphertextBlob,
    encryptionContext: ["purpose": "sse"]
)
```

## Configuration

### Command Line Options

- `--port, -p`: Port to listen on (default: 8080)
- `--host, -H`: Host to bind to (default: 127.0.0.1)
- `--log-level, -l`: Logging level (trace, debug, info, notice, warning, error, critical)
- `--help, -h`: Show help information

### Environment Variables

- `CYB_KMS_PORT`: Override default port
- `CYB_KMS_HOST`: Override default host
- `CYB_KMS_LOG_LEVEL`: Override default log level

## Security Considerations

### Key Storage
- Keys are stored encrypted in SQLite database
- Master encryption key derived from system entropy
- Keys never exposed in memory or logs

### Network Security
- HTTP-only (consider TLS termination proxy for production)
- Input validation on all API endpoints
- Rate limiting and abuse prevention (future)

### Access Control
- No built-in authentication (rely on network isolation)
- Consider API gateway or reverse proxy for access control
- Audit logging for all operations

## Development

### Testing

CybKMS includes comprehensive unit tests covering core functionality:

```bash
# Run all tests
swift test

# Run specific test class
swift test --filter KMSCoreTests

# Run with verbose output
swift test -v
```

Test coverage includes:
- Key creation, encryption, and decryption operations
- Key state management (enable/disable/delete)
- Error handling for invalid operations
- Data structure validation
- API compatibility verification

### Project Structure

```
CybKMS/
├── Package.swift                 # Swift Package Manager configuration
├── Sources/
│   ├── CybKMS/                   # Main server application
│   │   ├── CybKMSServer.swift    # Main executable
│   │   ├── KMSCore.swift         # Core KMS types and operations
│   │   └── Controllers/          # HTTP API controllers
│   │       └── KMSController.swift
│   └── CybKMSClient/             # HTTP client library
│       └── CybKMSClient.swift
├── Tests/
│   └── CybKMSTests/              # Unit and integration tests
│       └── KMSCoreTests.swift    # Core functionality tests
└── README.md                     # This file
```

## Future Enhancements

### Planned Features
- **Key Rotation**: Automatic key rotation with configurable schedules
- **Multi-Region Replication**: Cross-region key synchronization
- **Hardware Security Modules**: HSM integration for enhanced security
- **Key Aliases**: Named aliases for easier key management
- **Grants and Policies**: Advanced access control mechanisms
- **Cloud Integration**: Bridge mode to AWS KMS for hybrid deployments

### Blockchain-Inspired Features
- **Distributed Consensus**: Multi-node key agreement
- **Byzantine Fault Tolerance**: Resilient key operations
- **State Replication**: Eventual consistency across nodes
- **Cryptographic Proofs**: Zero-knowledge key operations

## Contributing

Contributions are welcome! Please see the main CybouS3 repository for contribution guidelines.

## License

This project is licensed under the terms specified in the main CybouS3 repository.

## Related Projects

- **CybS3**: Zero-knowledge encrypted S3 client
- **SwiftS3**: S3-compatible object storage server
- **CybouS3**: Unified ecosystem combining all components</content>
<parameter name="filePath">/Users/cybou/Documents/CybouS3/CybKMS/README.md