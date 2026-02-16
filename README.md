# CybouS3

**The Unified Swift Object Storage Ecosystem**

CybouS3 combines CybS3 (zero-knowledge encrypted S3 client) and SwiftS3 (S3-compatible server) into a comprehensive, secure, and enterprise-ready object storage solution built entirely in Swift.

## What We're Building

CybouS3 is pioneering a **unified ecosystem** that bridges the gap between secure client-side encryption and enterprise-grade server infrastructure. Our vision is to create the most secure, performant, and user-friendly object storage solution that maintains zero-trust principles while providing seamless integration.

### The Problem We're Solving
Traditional object storage solutions force a choice between:
- **Security**: Client-side encryption tools that are complex and disconnected
- **Usability**: Server solutions that handle everything but expose data risks

CybouS3 eliminates this tradeoff by providing **double encryption** (client + server) with unified management, making security the default while maintaining enterprise capabilities.

### Our Approach
- **Zero-Knowledge Architecture**: Your data is never exposed - not in transit, not at rest, not even to our servers
- **Unified Experience**: Single CLI for client operations, server management, and ecosystem coordination
- **Enterprise Ready**: Multi-tenant support, audit logging, compliance features, and scalability
- **Developer Friendly**: Easy local development setup, comprehensive testing, and cross-platform support

## Overview

CybouS3 is the first unified ecosystem that seamlessly integrates:

- **CybS3**: Advanced CLI client with zero-knowledge, client-side AES-256-GCM encryption
- **SwiftS3**: High-performance S3-compatible server with enterprise features

This combination delivers **double encryption** (client + server), unified management, and comprehensive testing - all while maintaining the zero-trust security model.

## Features

### 🔐 Security First
- **Client-side encryption** with BIP39 mnemonic keys
- **Server-side encryption** (SSE-KMS) support - *Implemented Q2 2026*
- **Double encryption** capabilities (client + server) - *Framework ready*
- **Zero-knowledge architecture** - your data is never exposed
- **Key rotation** without re-encryption
- **Secure key storage** (Keychain/platform-specific)

### ⚡ Performance & Scalability
- **High-performance streaming** for large files
- **Concurrent operations** with configurable parallelism
- **Load balancing** and connection pooling
- **Enterprise-grade** server features
- **Performance benchmarking suite** - *Implemented Q2 2026*

### 🏢 Enterprise Ready
- **Multi-tenant support** with isolated vaults
- **LDAP/AD integration** for authentication
- **Audit logging** and compliance reporting
- **VPC-only access** and advanced security
- **Unified authentication** between client and server - *Implemented Q2 2026*

### 🔧 Developer Experience
- **Unified CLI** for both client and server management - *Enhanced Q2 2026*
- **Easy local development** setup with `cybs3 vaults local`
- **Comprehensive testing** suite (integration, security, performance) - *Enhanced Q2 2026*
- **Cross-platform** support (macOS, Linux, Windows)
- **SwiftS3 server management** through CybS3 CLI - *Implemented Q2 2026*

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

# Check server status and metrics
cybs3 server status
cybs3 server metrics

# View server logs
cybs3 server logs --follow

# Sync vault credentials to server
cybs3 server auth sync --vault my-vault

# Create encrypted vault for local development
cybs3 vaults local --name dev

# Use CybS3 with local server
cybs3 vaults select dev
cybs3 files put myfile.txt --bucket my-bucket

# Run integration tests
cybs3 test integration

# Run security tests
cybs3 test security

# Run performance benchmarks (Coming Q3 2026)
cybs3 performance benchmark --swift-s3
```

### Development Workflow

```bash
# Quick setup
make setup

# Build everything
make build-all

# Run all tests
make test-all

# Start development server
make server

# Run integration tests
make integration
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
         Unified Ecosystem
```

### Current State (Q2 2026 ✅ COMPLETED)
- ✅ CybS3 CLI with client-side AES-256-GCM encryption
- ✅ SwiftS3 S3-compatible server with enterprise features
- ✅ SSE-KMS integration and double encryption framework
- ✅ Unified authentication between CybS3 and SwiftS3
- ✅ Enhanced server management (start/stop/status/logs/metrics/auth)
- ✅ Comprehensive security testing framework
- ✅ Cross-platform ecosystem with platform optimizations

### Coming Soon
- 🔄 **Q3 2026**: Advanced vault management and monitoring
- 🔄 **Q4 2026**: Performance benchmarking and chaos engineering
- 🔄 **2027**: Multi-cloud support, enterprise compliance, AI/ML features

## Components

### CybS3 CLI
Located in `CybS3/` directory.

**Current Commands:**
- `cybs3 vaults` - Manage encrypted S3 vaults
- `cybs3 keys` - Key management and rotation
- `cybs3 files` - File operations with client-side encryption
- `cybs3 folders` - Folder sync operations
- `cybs3 config` - Configuration management
- `cybs3 server` - SwiftS3 server management (start/stop/status/logs/metrics/auth)
- `cybs3 test` - Integration, security, and performance testing
- `cybs3 performance` - Performance benchmarking tools

**Coming Soon (Q3 2026):**
- `cybs3 server start/stop/status` - SwiftS3 server management
- Enhanced vault management spanning client and server

### SwiftS3 Server
Located in `SwiftS3/` directory.

**Features:**
- Full S3 API compatibility
- SQLite metadata storage
- Server-side encryption (SSE-KMS) support
- Object versioning and lifecycle management
- Access control and policies
- LDAP/AD authentication integration
- Audit logging and compliance features
- Event notifications

## Security Model

### Encryption Layers
1. **Client-side AES-256-GCM** (always enabled in CybS3)
2. **Server-side KMS encryption** (optional, SwiftS3) - *Bridge coming Q2 2026*
3. **Transport encryption** (TLS 1.3)

### Zero-Knowledge Architecture
- **Your data is never exposed** - encrypted before leaving your device
- **BIP39 mnemonics** for deterministic key generation
- **Key rotation** without re-encryption of existing data
- **Secure key storage** using platform-specific secure storage (Keychain, etc.)

### Double Encryption Vision
CybouS3 will be the first ecosystem to offer **true double encryption**:
- **Layer 1**: Client-side encryption you control
- **Layer 2**: Server-side encryption for additional protection
- **Result**: Ultra-sensitive data gets maximum protection while maintaining usability

### Key Management
- **Hierarchical key derivation** from BIP39 mnemonics
- **AWS KMS integration** for server-side encryption
- **Key rotation workflows** that maintain data accessibility
- **Cross-platform secure storage** for credentials and keys

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

# Performance benchmarks (including large file multipart upload tests)
cybs3 performance benchmark --swift-s3

# Unit tests
cd CybS3 && swift test
cd ../SwiftS3 && swift test
```

## Roadmap

We're building CybouS3 incrementally with a focus on security, performance, and usability. Here's what's completed and coming:

### Q2 2026: Enterprise Feature Bridge ✅ COMPLETED
- ✅ SSE-KMS integration and double encryption framework
- ✅ Unified authentication between CybS3 and SwiftS3
- ✅ Enhanced server management (logs, metrics, auth sync)
- ✅ Comprehensive security testing framework
- ✅ Cross-platform ecosystem optimizations

### Q3 2026: Unified CLI & Management
- 🔄 Advanced vault management spanning client and server
- 🔄 Unified monitoring across ecosystem
- 🔄 Advanced server configuration management

### Q4 2026: Performance & Security
- 🔄 Performance benchmarking suite with regression detection
- 🔄 Security testing framework with end-to-end validation
- 🔄 Chaos engineering and resilience testing

### 2027: Advanced Features
- 🔄 Multi-cloud support (AWS S3, GCP, Azure, etc.)
- 🔄 Enterprise compliance (SOC2, HIPAA, GDPR)
- 🔄 AI/ML-powered optimization and anomaly detection

See [CYBOUS3_ROADMAP.md](CYBOUS3_ROADMAP.md) for detailed implementation status and timelines.

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