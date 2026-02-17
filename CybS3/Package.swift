// swift-tools-version: 6.2.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CybS3",
    // Supports macOS 12.0+, Linux, and iOS 15.0+
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .executable(name: "cybs3", targets: ["CybS3"]),
        .library(name: "CybS3Lib", targets: ["CybS3Lib"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.5.0"),
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
        .package(url: "https://github.com/cybou-fr/SwiftBIP39.git", branch: "main"),
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0"),
        .package(path: "../CybKMS"),
    ],
    targets: [
        .target(
            name: "CybS3Lib",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
                "SwiftBIP39",
                .product(name: "CybKMSClient", package: "CybKMS"),
            ]
        ),
        .executableTarget(
            name: "CybS3",
            dependencies: [
                "CybS3Lib",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "SwiftBIP39",
            ]
        ),
        .testTarget(
            name: "CybS3Tests",
            dependencies: [
                "CybS3Lib"
            ]
        ),
    ]
)
