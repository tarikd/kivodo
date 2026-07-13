// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Mac App Store builds must not ship Sparkle (the App Store handles updates).
// Set KIVODO_MAS=1 to drop the Sparkle dependency and compile out the updater
// via the MAS_BUILD flag. Default (unset) is the Developer ID / direct-download
// build, which keeps Sparkle.
let masBuild = ProcessInfo.processInfo.environment["KIVODO_MAS"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMinor(from: "2.4.0")),
]
var appDependencies: [Target.Dependency] = [
    "KivodoCore",
    .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
]
var appSwiftSettings: [SwiftSetting] = []

if masBuild {
    appSwiftSettings.append(.define("MAS_BUILD"))
} else {
    packageDependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"))
    appDependencies.append(.product(name: "Sparkle", package: "Sparkle"))
}

let package = Package(
    name: "Kivodo",
    platforms: [.macOS(.v14)],
    dependencies: packageDependencies,
    targets: [
        .target(name: "KivodoCore"),
        .executableTarget(
            name: "Kivodo",
            dependencies: appDependencies,
            swiftSettings: appSwiftSettings
        ),
        .testTarget(name: "KivodoCoreTests", dependencies: ["KivodoCore"]),
    ]
)
