// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "OpenNotch", path: "Sources/OpenNotch")
    ]
)
