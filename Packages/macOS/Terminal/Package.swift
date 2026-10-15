// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Terminal",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Terminal",
            targets: ["Terminal"]
        )
    ]
)
