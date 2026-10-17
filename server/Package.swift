// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RippleServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0"),
        .package(path: "../RippleKit"),
    ],
    targets: [
        // Alarm mirror, backup sender rules, acknowledgments, temporary
        // contacts and admin commands. No HTTP here, so it is tested with a fake clock.
        .target(
            name: "RippleEngine",
            dependencies: [
                .product(name: "RippleKit", package: "RippleKit"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        // HTTP API, web pages, the Twilio backup sender and the worker loop.
        .executableTarget(
            name: "RippleServer",
            dependencies: [
                "RippleEngine",
                .product(name: "RippleKit", package: "RippleKit"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "RippleEngineTests",
            dependencies: [
                "RippleEngine",
                .product(name: "RippleKit", package: "RippleKit"),
            ]
        ),
    ]
)
