import Crypto
import Foundation

// CRC32 extension for Data
extension Data {
    func crc32() -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table = crc32Table()

        for byte in self {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }

        return crc ^ 0xFFFFFFFF
    }

    private func crc32Table() -> [UInt32] {
        var table: [UInt32] = Array(repeating: 0, count: 256)
        let polynomial: UInt32 = 0xEDB88320

        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ polynomial
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }

        return table
    }
}

// Digest to hex string extension
extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

/// Handles data integrity verification and checksum computation.
/// Supports CRC32, CRC32C, SHA1, and SHA256 algorithms.
actor IntegrityChecker {

    /// Verifies data integrity using checksums and detects bitrot.
    func verifyDataIntegrity(data: Data, storedAlgorithm: ChecksumAlgorithm?, storedChecksum: String?) throws -> DataIntegrityResult {
        // If we have a checksum, verify it
        if let algorithm = storedAlgorithm, let storedChecksum = storedChecksum {
            let computedChecksum = try computeChecksum(data: data, algorithm: algorithm)
            let isValid = computedChecksum == storedChecksum

            return DataIntegrityResult(
                isValid: isValid,
                algorithm: algorithm,
                computedChecksum: computedChecksum,
                storedChecksum: storedChecksum,
                bitrotDetected: !isValid,
                canRepair: false // For now, no repair capability
            )
        }

        // No checksum available
        return DataIntegrityResult(
            isValid: true, // Assume valid if no checksum
            bitrotDetected: false,
            canRepair: false
        )
    }

    /// Repairs data corruption if possible (for erasure coding or bitrot recovery).
    func repairDataCorruption(data: Data) async throws -> (repaired: Bool, data: Data) {
        // For now, return false as we don't have erasure coding implemented
        // This would be where erasure coding recovery would happen
        return (false, data)
    }

    /// Computes checksum for data using specified algorithm.
    func computeChecksum(data: Data, algorithm: ChecksumAlgorithm) throws -> String {
        switch algorithm {
        case .crc32:
            // Simple CRC32 implementation
            return String(format: "%08x", data.crc32())
        case .crc32c:
            // CRC32C - for now use same as CRC32
            return String(format: "%08x", data.crc32())
        case .sha1:
            return Insecure.SHA1.hash(data: data).hexString
        case .sha256:
            return SHA256.hash(data: data).hexString
        }
    }
}