// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Render",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Render",
            targets: ["Render"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
)
