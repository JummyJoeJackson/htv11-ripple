// swift-tools-version:5.9
import PackageDescription

// Shared models and API client used by the server, the wearer iPhone app,
// the Apple Watch app, and the admin iPhone app.
let package = Package(
    name: "KazeKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [
        .library(name: "KazeKit", targets: ["KazeKit"]),
    ],
    targets: [
        .target(name: "KazeKit"),
    ]
)
