// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EdgePin",
    platforms: [.macOS(.v13)],
    targets: [
        // The geometry, kept apart from AppKit so it can be tested without a screen.
        .target(name: "EdgePinCore"),
        .executableTarget(name: "EdgePin", dependencies: ["EdgePinCore"]),
        .testTarget(name: "EdgePinCoreTests", dependencies: ["EdgePinCore"]),
    ]
)
