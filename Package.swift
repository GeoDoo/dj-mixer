// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dj-mixer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "dj-mixer", path: "Sources/dj-mixer")
    ]
)
