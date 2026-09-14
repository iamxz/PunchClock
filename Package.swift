// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Daka",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DakaCore"),
        .testTarget(name: "DakaCoreTests", dependencies: ["DakaCore"])
    ]
)
