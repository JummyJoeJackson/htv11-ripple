// swift-tools-version:5.9
import PackageDescription

// Shared models, the alarm coordinator that runs on the wearer's iPhone, and
// the API client. Used by the server, the wearer iPhone app, the Apple Watch
// app, and the demo admin app.
let package = Package(
    name: "RippleKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [
        .library(name: "RippleKit", targets: ["RippleKit"]),
    ],
    targets: [
        .target(name: "RippleKit"),
        .testTarget(name: "RippleKitTests", dependencies: ["RippleKit"]),
    ]
)
