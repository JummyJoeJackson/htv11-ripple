// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KazeServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0"),
        .package(path: "../KazeKit"),
    ],
    targets: [
        // All state, timers, escalation and permission rules. No HTTP here, so it
        // can be tested with a fake clock.
        .target(
            name: "KazeEngine",
            dependencies: [
                .product(name: "KazeKit", package: "KazeKit"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        // HTTP API, web pages, messaging adapters and the job worker loop.
        .executableTarget(
            name: "KazeServer",
            dependencies: [
                "KazeEngine",
                .product(name: "KazeKit", package: "KazeKit"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "KazeEngineTests",
            dependencies: [
                "KazeEngine",
                .product(name: "KazeKit", package: "KazeKit"),
            ]
        ),
    ]
)
