// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chat",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),        
    ],
    products: [
        .library(
            name: "Chat",
            targets: ["Chat"]
        ),
    ],
    targets: [
        .target(
            name: "Chat"
        )
    ]
)
