import Foundation
import Crypto
import Compression

/// Comprehensive benchmarking for compression and encryption operations
public class CompressionEncryptionBenchmark {
    public init() {}

    /// Benchmark configuration
    public struct BenchmarkConfig {
        public let dataSizes: [Int] // In bytes
        public let iterations: Int
        public let algorithms: [CompressionAlgorithm]
        public let encryptionAlgorithms: [String]

        public init(
            dataSizes: [Int] = [1024, 10*1024, 100*1024, 1024*1024], // 1KB, 10KB, 100KB, 1MB
            iterations: Int = 10,
            algorithms: [CompressionAlgorithm] = [.gzip, .bzip2, .xz],
            encryptionAlgorithms: [String] = ["AES-256-GCM", "ChaCha20-Poly1305"]
        ) {
            self.dataSizes = dataSizes
            self.iterations = iterations
            self.algorithms = algorithms
            self.encryptionAlgorithms = encryptionAlgorithms
        }
    }

    /// Benchmark result for a single test
    public struct BenchmarkResult {
        public let algorithm: String
        public let dataSize: Int
        public let compressionRatio: Double?
        public let compressionThroughput: Double // MB/s
        public let decompressionThroughput: Double // MB/s
        public let encryptionThroughput: Double // MB/s
        public let decryptionThroughput: Double // MB/s
        public let totalTime: TimeInterval
        public let error: String?

        public init(
            algorithm: String,
            dataSize: Int,
            compressionRatio: Double? = nil,
            compressionThroughput: Double = 0,
            decompressionThroughput: Double = 0,
            encryptionThroughput: Double = 0,
            decryptionThroughput: Double = 0,
            totalTime: TimeInterval = 0,
            error: String? = nil
        ) {
            self.algorithm = algorithm
            self.dataSize = dataSize
            self.compressionRatio = compressionRatio
            self.compressionThroughput = compressionThroughput
            self.decompressionThroughput = decompressionThroughput
            self.encryptionThroughput = encryptionThroughput
            self.decryptionThroughput = decryptionThroughput
            self.totalTime = totalTime
            self.error = error
        }
    }

    /// Run comprehensive compression and encryption benchmarks
    public func runBenchmark(config: BenchmarkConfig = BenchmarkConfig()) async throws -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []

        // Generate test data patterns
        let testDataPatterns = [
            "random": generateRandomData(size: 1024 * 1024), // 1MB base pattern
            "text": generateTextData(size: 1024 * 1024),
            "binary": generateBinaryData(size: 1024 * 1024)
        ]

        for dataSize in config.dataSizes {
            for patternName in ["random", "text", "binary"] {
                let baseData = testDataPatterns[patternName]!
                let testData = baseData.prefix(dataSize)

                // Test compression algorithms
                for algorithm in config.algorithms {
                    let result = try await benchmarkCompression(
                        data: Data(testData),
                        algorithm: algorithm,
                        iterations: config.iterations
                    )
                    results.append(result)
                }

                // Test encryption algorithms
                for encAlgorithm in config.encryptionAlgorithms {
                    let result = try await benchmarkEncryption(
                        data: Data(testData),
                        algorithm: encAlgorithm,
                        iterations: config.iterations
                    )
                    results.append(result)
                }

                // Test combined compression + encryption
                for compAlgorithm in config.algorithms {
                    for encAlgorithm in config.encryptionAlgorithms {
                        let result = try await benchmarkCombined(
                            data: Data(testData),
                            compressionAlgorithm: compAlgorithm,
                            encryptionAlgorithm: encAlgorithm,
                            iterations: config.iterations
                        )
                        results.append(result)
                    }
                }
            }
        }

        return results
    }

    /// Benchmark a single compression algorithm
    private func benchmarkCompression(data: Data, algorithm: CompressionAlgorithm, iterations: Int) async throws -> BenchmarkResult {
        let algorithmName = "compression-\(algorithm.rawValue)"

        do {
            var totalCompressionTime: TimeInterval = 0
            var totalDecompressionTime: TimeInterval = 0
            var compressedSizes: [Int] = []

            for _ in 0..<iterations {
                // Compression benchmark
                let compressionStart = Date()
                let compressedData = try compressData(data, algorithm: algorithm)
                let compressionTime = Date().timeIntervalSince(compressionStart)
                totalCompressionTime += compressionTime
                compressedSizes.append(compressedData.count)

                // Decompression benchmark
                let decompressionStart = Date()
                let _ = try decompressData(compressedData, algorithm: algorithm)
                let decompressionTime = Date().timeIntervalSince(decompressionStart)
                totalDecompressionTime += decompressionTime
            }

            let avgCompressionTime = totalCompressionTime / Double(iterations)
            let avgDecompressionTime = totalDecompressionTime / Double(iterations)
            let avgCompressedSize = Double(compressedSizes.reduce(0, +)) / Double(compressedSizes.count)
            let compressionRatio = Double(data.count) / avgCompressedSize

            let compressionThroughput = Double(data.count) / avgCompressionTime / (1024 * 1024) // MB/s
            let decompressionThroughput = avgCompressedSize / avgDecompressionTime / (1024 * 1024) // MB/s

            return BenchmarkResult(
                algorithm: algorithmName,
                dataSize: data.count,
                compressionRatio: compressionRatio,
                compressionThroughput: compressionThroughput,
                decompressionThroughput: decompressionThroughput,
                totalTime: totalCompressionTime + totalDecompressionTime
            )

        } catch {
            return BenchmarkResult(
                algorithm: algorithmName,
                dataSize: data.count,
                error: error.localizedDescription
            )
        }
    }

    /// Benchmark a single encryption algorithm
    private func benchmarkEncryption(data: Data, algorithm: String, iterations: Int) async throws -> BenchmarkResult {
        let algorithmName = "encryption-\(algorithm)"

        do {
            // Generate test key
            let key = SymmetricKey(size: .bits256)

            var totalEncryptionTime: TimeInterval = 0
            var totalDecryptionTime: TimeInterval = 0

            for _ in 0..<iterations {
                // Encryption benchmark
                let encryptionStart = Date()
                let encryptedData = try encryptData(data, key: key, algorithm: algorithm)
                let encryptionTime = Date().timeIntervalSince(encryptionStart)
                totalEncryptionTime += encryptionTime

                // Decryption benchmark
                let decryptionStart = Date()
                let _ = try decryptData(encryptedData, key: key)
                let decryptionTime = Date().timeIntervalSince(decryptionStart)
                totalDecryptionTime += decryptionTime
            }

            let avgEncryptionTime = totalEncryptionTime / Double(iterations)
            let avgDecryptionTime = totalDecryptionTime / Double(iterations)

            let encryptionThroughput = Double(data.count) / avgEncryptionTime / (1024 * 1024) // MB/s
            let decryptionThroughput = Double(data.count) / avgDecryptionTime / (1024 * 1024) // MB/s

            return BenchmarkResult(
                algorithm: algorithmName,
                dataSize: data.count,
                encryptionThroughput: encryptionThroughput,
                decryptionThroughput: decryptionThroughput,
                totalTime: totalEncryptionTime + totalDecryptionTime
            )

        } catch {
            return BenchmarkResult(
                algorithm: algorithmName,
                dataSize: data.count,
                error: error.localizedDescription
            )
        }
    }

    /// Benchmark combined compression + encryption
    private func benchmarkCombined(data: Data, compressionAlgorithm: CompressionAlgorithm, encryptionAlgorithm: String, iterations: Int) async throws -> BenchmarkResult {
        let algorithmName = "combined-\(compressionAlgorithm.rawValue)-\(encryptionAlgorithm)"

        do {
            let key = SymmetricKey(size: .bits256)
            var totalTime: TimeInterval = 0

            for _ in 0..<iterations {
                let startTime = Date()

                // Compress
                let compressedData = try compressData(data, algorithm: compressionAlgorithm)

                // Encrypt
                let encryptedData = try encryptData(compressedData, key: key, algorithm: encryptionAlgorithm)

                // Decrypt
                let decryptedData = try decryptData(encryptedData, key: key)

                // Decompress
                let _ = try decompressData(decryptedData, algorithm: compressionAlgorithm)

                let endTime = Date()
                totalTime += endTime.timeIntervalSince(startTime)
            }

            let avgTime = totalTime / Double(iterations)
            let throughput = Double(data.count) / avgTime / (1024 * 1024) // MB/s

            return BenchmarkResult(
                algorithm: algorithmName,
                dataSize: data.count,
                compressionThroughput: throughput, // Combined throughput
                totalTime: totalTime
            )

        } catch {
            return BenchmarkResult(
                algorithm: algorithmName,
                dataSize: data.count,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Helper Methods

    private func compressData(_ data: Data, algorithm: CompressionAlgorithm) throws -> Data {
        switch algorithm {
        case .gzip:
            return try gzipCompress(data)
        case .bzip2:
            return try bzip2Compress(data)
        case .xz:
            return try xzCompress(data)
        }
    }

    private func decompressData(_ data: Data, algorithm: CompressionAlgorithm) throws -> Data {
        switch algorithm {
        case .gzip:
            return try gzipDecompress(data)
        case .bzip2:
            return try bzip2Decompress(data)
        case .xz:
            return try xzDecompress(data)
        }
    }

    private func encryptData(_ data: Data, key: SymmetricKey, algorithm: String) throws -> Data {
        let encAlgorithm: EncryptionAlgorithm
        switch algorithm {
        case "AES-256-GCM":
            encAlgorithm = .aes256gcm
        case "ChaCha20-Poly1305":
            encAlgorithm = .chacha20poly1305
        default:
            encAlgorithm = .aes256gcm
        }
        return try Encryption.encrypt(data: data, key: key, algorithm: encAlgorithm)
    }

    private func decryptData(_ data: Data, key: SymmetricKey) throws -> Data {
        return try Encryption.decrypt(data: data, key: key)
    }

    // MARK: - Compression Implementation (duplicated from BackupServices for testing)

    private func gzipCompress(_ data: Data) throws -> Data {
        let pageSize = 4096
        let destinationBufferSize = pageSize

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { sourceBuffer.deallocate() }
        data.copyBytes(to: sourceBuffer, count: data.count)

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 0)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 0)!,
            src_size: 0,
            state: UnsafeMutableRawPointer(bitPattern: 0)
        )
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw CompressionError.compressionFailed("Failed to initialize compression stream")
        }

        stream.src_ptr = UnsafePointer(sourceBuffer)
        stream.src_size = data.count
        stream.dst_ptr = destinationBuffer
        stream.dst_size = destinationBufferSize

        var compressedData = Data()

        repeat {
            status = compression_stream_process(&stream, stream.src_size == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)

            switch status {
            case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                compressedData.append(destinationBuffer, count: destinationBufferSize - stream.dst_size)
                stream.dst_ptr = destinationBuffer
                stream.dst_size = destinationBufferSize
            case COMPRESSION_STATUS_ERROR:
                compression_stream_destroy(&stream)
                throw CompressionError.compressionFailed("Compression failed")
            default:
                break
            }
        } while status == COMPRESSION_STATUS_OK

        compression_stream_destroy(&stream)
        return compressedData
    }

    private func gzipDecompress(_ data: Data) throws -> Data {
        let pageSize = 4096
        let destinationBufferSize = pageSize

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { sourceBuffer.deallocate() }
        data.copyBytes(to: sourceBuffer, count: data.count)

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 0)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 0)!,
            src_size: 0,
            state: UnsafeMutableRawPointer(bitPattern: 0)
        )
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw CompressionError.compressionFailed("Failed to initialize decompression stream")
        }

        stream.src_ptr = UnsafePointer(sourceBuffer)
        stream.src_size = data.count
        stream.dst_ptr = destinationBuffer
        stream.dst_size = destinationBufferSize

        var decompressedData = Data()

        repeat {
            status = compression_stream_process(&stream, stream.src_size == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)

            switch status {
            case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                decompressedData.append(destinationBuffer, count: destinationBufferSize - stream.dst_size)
                stream.dst_ptr = destinationBuffer
                stream.dst_size = destinationBufferSize
            case COMPRESSION_STATUS_ERROR:
                compression_stream_destroy(&stream)
                throw CompressionError.compressionFailed("Decompression failed")
            default:
                break
            }
        } while status == COMPRESSION_STATUS_OK

        compression_stream_destroy(&stream)
        return decompressedData
    }

    private func bzip2Compress(_ data: Data) throws -> Data {
        return try compressWithSystemTool(data: data, tool: "bzip2", args: ["-c", "-9"])
    }

    private func bzip2Decompress(_ data: Data) throws -> Data {
        return try decompressWithSystemTool(data: data, tool: "bunzip2", args: ["-c"])
    }

    private func xzCompress(_ data: Data) throws -> Data {
        return try compressWithSystemTool(data: data, tool: "xz", args: ["-c", "-9"])
    }

    private func xzDecompress(_ data: Data) throws -> Data {
        return try decompressWithSystemTool(data: data, tool: "unxz", args: ["-c"])
    }

    private func compressWithSystemTool(data: Data, tool: String, args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(tool)")
        process.arguments = args

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.closeFile()

        let compressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw CompressionError.compressionFailed("\(tool) failed: \(errorMessage)")
        }

        return compressedData
    }

    private func decompressWithSystemTool(data: Data, tool: String, args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(tool)")
        process.arguments = args

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.closeFile()

        let decompressedData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw CompressionError.compressionFailed("\(tool) failed: \(errorMessage)")
        }

        return decompressedData
    }

    // MARK: - Test Data Generation

    private func generateRandomData(size: Int) -> Data {
        var data = Data(capacity: size)
        for _ in 0..<size {
            data.append(UInt8.random(in: 0...255))
        }
        return data
    }

    private func generateTextData(size: Int) -> Data {
        let lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
        var text = ""
        while text.count < size {
            text += lorem
        }
        return text.prefix(size).data(using: .utf8)!
    }

    private func generateBinaryData(size: Int) -> Data {
        var data = Data(capacity: size)
        // Create a pattern that's somewhat compressible
        for i in 0..<size {
            let pattern = UInt8((i % 256) ^ (i / 256 % 256))
            data.append(pattern)
        }
        return data
    }
}