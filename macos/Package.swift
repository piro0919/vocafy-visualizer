// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VocafyVisualizer",
    // Process taps (AudioHardwareCreateProcessTap) arrived in macOS 14.2.
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "VocafyVisualizer",
            path: "Sources/VocafyVisualizer",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
