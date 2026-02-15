# Contributing to CybouS3

Thank you for your interest in contributing to CybouS3! This document provides guidelines and information for contributors.

## Code of Conduct

This project follows a code of conduct to ensure a welcoming environment for all contributors. By participating, you agree to:

- Be respectful and inclusive
- Focus on constructive feedback
- Accept responsibility for mistakes
- Show empathy towards other contributors
- Help create a positive community

## How to Contribute

### Development Setup

1. **Prerequisites**
   - Swift 6.0+
   - macOS 14.0+ or Linux
   - Git

2. **Clone and Setup**
   ```bash
   git clone https://github.com/cybou-fr/CybouS3.git
   cd CybouS3
   make setup
   make build-all
   ```

3. **Development Workflow**
   ```bash
   # Start development server
   make dev

   # Run tests
   make test-all

   # Run integration tests
   make integration

   # Format code
   make format

   # Lint code
   make lint
   ```

### Types of Contributions

#### 🐛 Bug Reports
- Use the issue tracker to report bugs
- Include detailed steps to reproduce
- Provide system information (OS, Swift version)
- Include relevant log output

#### ✨ Feature Requests
- Use the issue tracker for feature requests
- Clearly describe the proposed feature
- Explain the use case and benefits
- Consider if it fits the project scope

#### 🛠️ Code Contributions
- Fork the repository
- Create a feature branch: `git checkout -b feature/your-feature`
- Make your changes
- Add tests for new functionality
- Ensure all tests pass: `make test-all`
- Format code: `make format`
- Submit a pull request

#### 📚 Documentation
- Documentation improvements are welcome
- Update README.md for user-facing changes
- Update code comments for internal changes
- Check spelling and grammar

### Development Guidelines

#### Code Style
- Follow Swift API Design Guidelines
- Use clear, descriptive names
- Add documentation comments for public APIs
- Keep functions focused and single-purpose
- Use Swift's type system effectively

#### Testing
- Write unit tests for new functionality
- Include integration tests for cross-component features
- Test error conditions and edge cases
- Maintain test coverage above 80%

#### Security
- Be mindful of security implications
- Never log sensitive information
- Use secure coding practices
- Report security issues privately

#### Commit Messages
- Use clear, descriptive commit messages
- Start with a verb (Add, Fix, Update, etc.)
- Reference issue numbers when applicable
- Keep the first line under 50 characters

Example:
```
Add SSE-KMS support to S3Client

- Implement server-side encryption headers
- Add KMS key ID parameter
- Update documentation
- Add integration tests

Fixes #123
```

### Pull Request Process

1. **Before Submitting**
   - Ensure all tests pass
   - Format your code
   - Update documentation if needed
   - Test on multiple platforms if possible

2. **PR Description**
   - Clearly describe the changes
   - Reference related issues
   - Include screenshots for UI changes
   - List any breaking changes

3. **Review Process**
   - PRs require at least one approval
   - Address review feedback
   - Maintainers may request changes
   - Once approved, a maintainer will merge

### Areas for Contribution

#### High Priority
- Bug fixes and stability improvements
- Performance optimizations
- Security enhancements
- Documentation improvements

#### Medium Priority
- New CLI commands
- Additional S3 API support
- Testing infrastructure
- CI/CD improvements

#### Future Opportunities
- Multi-cloud support
- Advanced enterprise features
- Mobile SDKs
- Web interfaces

### Getting Help

- **Issues**: For bugs and feature requests
- **Discussions**: For questions and general discussion
- **Documentation**: Check README.md and docs/
- **Community**: Join our community channels

### Recognition

Contributors are recognized in:
- GitHub's contributor insights
- Release notes
- Project documentation

Thank you for contributing to CybouS3! 🚀