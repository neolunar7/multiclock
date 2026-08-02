// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MultiClock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MultiClock",
            path: "Sources/MultiClock",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
