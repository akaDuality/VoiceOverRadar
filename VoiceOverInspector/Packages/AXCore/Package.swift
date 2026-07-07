// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AXCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AXCore", targets: ["AXCore"]),
    ],
    targets: [
        .target(
            name: "AXCore",
            // The Accessibility API is C-heavy (AXObserver callbacks, Unmanaged
            // refcons). Swift 5 language mode keeps that interop ergonomic; the
            // app layer that consumes this module can stay on Swift 6.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AXCoreTests",
            dependencies: ["AXCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
