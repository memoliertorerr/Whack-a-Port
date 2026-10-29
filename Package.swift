// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhackAPort",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhackAPort", targets: ["WhackAPort"]),
    ],
    targets: [
        // Port discovery, process inspection and signalling. No UI, fully testable.
        .target(name: "WhackKit"),
        // The menu bar app.
        .executableTarget(name: "WhackAPort", dependencies: ["WhackKit"]),
        .testTarget(name: "WhackKitTests", dependencies: ["WhackKit"]),
    ]
)
