// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CybKMS",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "CybKMS", targets: ["CybKMS"]),
        .library(name: "CybKMSClient", targets: ["CybKMSClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/vapor/sqlite-nio.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "CybKMS",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SQLiteNIO", package: "sqlite-nio"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]
        ),
        .target(
            name: "CybKMSClient",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            path: "CybKMSClient"
        ),
        .testTarget(
            name: "CybKMSTests",
            dependencies: [
                "CybKMS",
                "CybKMSClient",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
    ]
)