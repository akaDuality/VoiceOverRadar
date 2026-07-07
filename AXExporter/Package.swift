// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AXExporter",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "AXExporter", targets: ["AXExporter"]),
    ],
    targets: [
        .target(
            name: "AXExporter",
            // UIKit accessibility traversal is Objective-C-flavoured and runs on
            // the main thread; Swift 5 mode keeps that interop friction-free.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AXExporterTests",
            dependencies: ["AXExporter"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
