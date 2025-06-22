// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DTN7",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v9),
        .visionOS(.v2)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DTN7",
            targets: ["DTN7"]),
        .executable(name: "dtnd", targets: ["dtnd"]),
        .executable(name: "dtnquery", targets: ["dtnquery"]),
        .executable(name: "dtnrecv", targets: ["dtnrecv"]),
        .executable(name: "dtnsend", targets: ["dtnsend"]),
        .executable(name: "dtntrigger", targets: ["dtntrigger"]),
        .executable(name: "dtnecho", targets: ["dtnecho"]),
        .executable(name: "dtnping", targets: ["dtnping"]),
    ],
    dependencies: [
        .package(url: "https://github.com/edgeengineer/bp7.git", from: "0.0.5"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.14.1"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CSQLite",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]),
        .target(
            name: "DTN7",
            dependencies: [
                "CSQLite",
                .product(name: "BP7", package: "bp7"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]),
        .executableTarget(
            name: "dtnd",
            dependencies: ["DTN7", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(
            name: "dtnquery",
            dependencies: ["DTN7", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(
            name: "dtnrecv",
            dependencies: ["DTN7", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(
            name: "dtnsend",
            dependencies: ["DTN7", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(
            name: "dtntrigger",
            dependencies: ["DTN7", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(
            name: "dtnecho",
            dependencies: ["DTN7", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(
            name: "dtnping",
            dependencies: ["DTN7", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(
            name: "UnitTests",
            dependencies: ["DTN7"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["DTN7"],
            path: "Tests",
            sources: ["IntegrationTests/BasicTests.swift", "IntegrationTests/HTTPTests.swift", "Utilities/TestFramework.swift"]
        ),
    ]
)
