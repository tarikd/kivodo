// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kivodo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMinor(from: "2.4.0")),
    ],
    targets: [
        .target(name: "KivodoCore"),
        .executableTarget(
            name: "Kivodo",
            dependencies: [
                "KivodoCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "KivodoCoreTests", dependencies: ["KivodoCore"]),
    ]
)
