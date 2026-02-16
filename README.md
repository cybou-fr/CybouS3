# CybouS3

**The Unified Swift Object Storage Ecosystem**

CybouS3 combines CybS3 (zero-knowledge encrypted S3 client) and SwiftS3 (S3-compatible server) into a comprehensive, secure, and enterprise-ready object storage solution built entirely in Swift.

## Overview

CybouS3 is the first unified ecosystem that seamlessly integrates:

- **CybS3**: Advanced CLI client with zero-knowledge, client-side AES-256-GCM encryption
- **SwiftS3**: High-performance S3-compatible server with enterprise features

This combination delivers **double encryption** (client + server), unified management, and comprehensive testing - all while maintaining the zero-trust security model.

## Features

### 🔐 Security First
- **Client-side encryption** with BIP39 mnemonic keys
- **Server-side encryption** (SSE-KMS) support
- **Double encryption** capabilities (client + server)
- **Zero-knowledge architecture** - your data is never exposed

### ⚡ Performance & Scalability
- **High-performance streaming** for large files
- **Concurrent operations** with configurable parallelism
- **Load balancing** and connection pooling
- **Enterprise-grade** server features

### 🏢 Enterprise Ready
- **Multi-tenant support** with isolated vaults
- **LDAP/AD integration** for authentication
- **Audit logging** and compliance reporting
- **VPC-only access** and advanced security

### 🔧 Developer Experience
- **Unified CLI** for both client and server management
- **Easy local development** setup
- **Comprehensive testing** suite
- **Cross-platform** support (macOS, Linux, Windows)

## Quick Start

### Prerequisites
- Swift 6.0+ (tested with Swift 6.2.3)
- macOS 14.0+ or Linux (Ubuntu 20.04+, CentOS 8+, etc.)

### Installation

```bash
# Clone CybouS3
git clone https://github.com/cybou-fr/CybouS3.git
cd CybouS3

# Build both components
cd CybS3 && swift build -c release
cd ../SwiftS3 && swift build -c release

# Install CybS3 CLI (adjust path as needed)
cd ../CybS3 && cp .build/x86_64-unknown-linux-gnu/release/cybs3 /usr/local/bin/
```

### Basic Usage

```bash
# Start SwiftS3 server
cybs3 server start

# Create encrypted vault for local development
cybs3 vaults local --name dev

# Use CybS3 with local server
cybs3 vaults select dev
cybs3 files put myfile.txt --bucket my-bucket

# Run integration tests
cybs3 test integration

# Run security tests
cybs3 test security

# Run performance benchmarks
cybs3 performance benchmark --swift-s3
```

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│     CybS3 CLI   │    │   SwiftS3 Server │
│                 │    │                 │
│ • Client-side   │◄──►│ • S3 Compatible │
│   encryption    │    │ • Enterprise     │
│ • Multi-vault   │    │   features       │
│ • Performance   │    │ • SSE-KMS        │
│ • Cross-platform│    │ • Versioning     │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┘
              CybouS3
```

## Components

### CybS3 CLI
Located in `CybS3/` directory.

**Commands:**
- `cybs3 vaults` - Manage encrypted S3 vaults
- `cybs3 keys` - Key management and rotation
- `cybs3 files` - File operations
- `cybs3 folders` - Folder sync operations
- `cybs3 server` - SwiftS3 server management
- `cybs3 test` - Integration and security testing
- `cybs3 performance` - Benchmarking tools

### SwiftS3 Server
Located in `SwiftS3/` directory.

**Features:**
- Full S3 API compatibility
- SQLite metadata storage
- Server-side encryption (SSE-KMS)
- Object versioning and lifecycle
- Access control and policies
- Event notifications

## Security Model

### Encryption Layers
1. **Client-side AES-256-GCM** (always enabled in CybS3)
2. **Server-side KMS encryption** (optional, SwiftS3)
3. **Transport encryption** (TLS 1.3)

### Key Management
- **BIP39 mnemonics** for client encryption
- **AWS KMS integration** for server encryption
- **Key rotation** without re-encryption
- **Secure key storage** (Keychain/platform-specific)

## Development

### Project Structure
```
CybouS3/
├── CybS3/              # CLI client
├── SwiftS3/            # S3 server
├── docs/               # Documentation
├── CYBOUS3_ROADMAP.md  # Roadmap
└── README.md          # This file
```

### Building
```bash
# Quick setup and build
make setup
make build-all

# Or build manually
cd CybS3 && swift build -c release
cd ../SwiftS3 && swift build -c release
```

**Note:** CybouS3 is fully cross-platform and has been tested on Linux with Swift 6.2.3. All platform-specific code has been updated to work on macOS, Linux, and Windows.

### Development Workflow
```bash
# Start development environment
make dev

# Run all tests
make test-all

# Run integration tests
make integration

# Format code
make format

# Clean everything
make clean
```

### Testing
```bash
# Integration tests
cybs3 test integration

# Security tests
cybs3 test security

# Performance benchmarks
cybs3 performance benchmark --swift-s3

# Unit tests
cd CybS3 && swift test
cd ../SwiftS3 && swift test
```

## Roadmap

See [CYBOUS3_ROADMAP.md](CYBOUS3_ROADMAP.md) for detailed roadmap and implementation status.

## Contributing

We welcome contributions! See our [contributing guide](CONTRIBUTING.md) for details.

### Getting Started
```bash
# Quick development setup
make setup
make build-all
make test-all
```

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE).

## Support

- **Issues**: [GitHub Issues](https://github.com/cybou-fr/CybouS3/issues)
- **Discussions**: [GitHub Discussions](https://github.com/cybou-fr/CybouS3/discussions)
- **Documentation**: See [docs/](docs/) directory
- **Contributing**: See [CONTRIBUTING.md](CONTRIBUTING.md)

---

**Built with ❤️ in Swift - The CybouS3 Ecosystem (Updated: February 2026)**</content>
<parameter name="filePath">/Users/cybou/Documents/CybouS3/README.md