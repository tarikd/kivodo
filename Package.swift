// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kivodo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KivodoCore"),
        .executableTarget(name: "Kivodo", dependencies: ["KivodoCore"]),
        .testTarget(name: "KivodoCoreTests", dependencies: ["KivodoCore"]),
    ]
)
