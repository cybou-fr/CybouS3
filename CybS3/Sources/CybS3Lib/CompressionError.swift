import Foundation
import Compression

/// Errors that can occur during backup compression
enum CompressionError: Error {
    case compressionFailed(String)
}
