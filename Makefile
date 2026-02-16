# CybouS3 - Unified Swift Object Storage Ecosystem
# Makefile for development tasks

.PHONY: help build build-release build-all test test-all clean install docs format lint

# Default target
help:
	@echo "CybouS3 Development Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  build         - Build CybS3 in debug mode"
	@echo "  build-release - Build CybS3 in release mode"
	@echo "  build-swiftS3 - Build SwiftS3 in debug mode"
	@echo "  build-all     - Build both CybS3 and SwiftS3"
	@echo "  test          - Run CybS3 tests"
	@echo "  test-swiftS3  - Run SwiftS3 tests"
	@echo "  test-all      - Run all tests"
	@echo "  clean         - Clean all build artifacts"
	@echo "  install       - Install CybS3 CLI to /usr/local/bin"
	@echo "  docs          - Generate documentation"
	@echo "  format        - Format Swift code"
	@echo "  lint          - Run SwiftLint (if installed)"
	@echo "  setup         - Initial project setup"
	@echo "  server        - Start SwiftS3 server for development"
	@echo "  integration   - Run integration tests"
	@echo "  perf          - Run performance benchmarks"
	@echo "  security      - Run security tests"
	@echo "  chaos         - Run chaos engineering tests"
	@echo "  regression    - Run performance regression detection"
	@echo "  ecosystem-health - Check unified ecosystem health"
	@echo "  multicloud-test - Test multi-cloud provider support"
	@echo "  multicloud-integration - Run multi-cloud integration tests"
	@echo "  compliance-check - Run compliance checks for all standards"
	@echo "  compliance-report - Generate compliance reports"
	@echo "  retention-apply - Apply data retention policies"
	@echo ""

# Build targets
build:
	@echo "Building CybS3..."
	cd CybS3 && swift build

build-release:
	@echo "Building CybS3 (release)..."
	cd CybS3 && swift build -c release

build-swiftS3:
	@echo "Building SwiftS3..."
	cd SwiftS3 && swift build

build-all: build-swiftS3 build-release
	@echo "All components built successfully!"

# Test targets
test:
	@echo "Running CybS3 tests..."
	cd CybS3 && swift test

test-swiftS3:
	@echo "Running SwiftS3 tests..."
	cd SwiftS3 && swift test

test-all: test test-swiftS3
	@echo "All tests completed!"

# Integration tests
integration:
	@echo "Running CybouS3 integration tests..."
	cd CybS3 && swift build -c release
	./CybS3/.build/release/cybs3 test integration

# Clean
clean:
	@echo "Cleaning build artifacts..."
	cd CybS3 && swift package clean
	cd SwiftS3 && swift package clean
	rm -rf CybS3/.build SwiftS3/.build
	rm -rf docs/build

# Install
install: build-release
	@echo "Installing CybS3 CLI..."
	sudo cp CybS3/.build/release/cybs3 /usr/local/bin/
	@echo "CybS3 installed to /usr/local/bin/cybs3"

# Development server
server: build-swiftS3
	@echo "Starting SwiftS3 development server..."
	./SwiftS3/.build/debug/SwiftS3 server --hostname 127.0.0.1 --port 8080 --storage ./data --access-key admin --secret-key password

# Documentation
docs:
	@echo "Generating documentation..."
	@echo "Note: Install jazzy for Swift documentation generation"
	@if command -v jazzy >/dev/null 2>&1; then \
		jazzy --config docs/.jazzy.yml; \
	else \
		echo "Jazzy not installed. Install with: gem install jazzy"; \
	fi

# Code formatting
format:
	@echo "Formatting Swift code..."
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat CybS3/Sources CybS3/Tests SwiftS3/Sources SwiftS3/Tests; \
	else \
		echo "SwiftFormat not installed. Install with: brew install swiftformat"; \
	fi

# Linting
lint:
	@echo "Running SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint CybS3/Sources CybS3/Tests SwiftS3/Sources SwiftS3/Tests; \
	else \
		echo "SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

# Setup
setup:
	@echo "Setting up CybouS3 development environment..."
	@echo "Installing development dependencies..."
	@if command -v brew >/dev/null 2>&1; then \
		brew install swiftlint swiftformat || true; \
	else \
		echo "Homebrew not found. Please install swiftlint and swiftformat manually."; \
	fi
	@echo "Setup complete! Run 'make build-all' to build the project."

# Performance testing
perf: build-release
	@echo "Running performance benchmarks..."
	./CybS3/.build/release/cybs3 performance benchmark --swift-s3 --duration 30

# Security testing
security: build-release
	@echo "Running security tests..."
	./CybS3/.build/release/cybs3 test security

# Chaos engineering testing
chaos: build-release
	@echo "Running chaos engineering tests..."
	./CybS3/.build/release/cybs3 test chaos resilience --duration 60

# Regression detection
regression: build-release
	@echo "Running performance regression detection..."
	./CybS3/.build/release/cybs3 performance regression check --fail-on-regression

# Ecosystem health check
ecosystem-health: build-release
	@echo "Checking ecosystem health..."
	./CybS3/.build/release/cybs3 health ecosystem --detailed

# Multi-cloud testing
multicloud-test: build-release
	@echo "Testing multi-cloud providers..."
	./CybS3/.build/release/cybs3 multicloud providers
	@echo "Multi-cloud provider listing completed"

# Multi-cloud integration tests (placeholder)
multicloud-integration: build-release
	@echo "Running multi-cloud integration tests..."
	@echo "Note: Multi-cloud integration tests require provider credentials"
	@echo "Configure providers with: cybs3 multicloud configure <provider>"
	@echo "Integration tests will be fully implemented with enterprise compliance features"

# Compliance testing
compliance-check: build-release
	@echo "Running compliance checks..."
	./CybS3/.build/release/cybs3 compliance check --all

compliance-report: build-release
	@echo "Generating compliance reports..."
	./CybS3/.build/release/cybs3 compliance report soc2 --title "SOC2 Compliance Report"
	./CybS3/.build/release/cybs3 compliance report gdpr --title "GDPR Compliance Report"

retention-apply: build-release
	@echo "Applying data retention policies..."
	./CybS3/.build/release/cybs3 compliance retention --apply

# Full CI pipeline
ci: clean build-all test-all integration security chaos regression ecosystem-health multicloud-test compliance-check
	@echo "CI pipeline completed successfully!"

# Development workflow
dev: build server
	@echo "Development environment ready!"
	@echo "SwiftS3 server running on http://127.0.0.1:8080"
	@echo "Use './CybS3/.build/debug/cybs3' for CLI testing"