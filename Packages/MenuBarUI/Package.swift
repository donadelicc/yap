// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MenuBarUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MenuBarUI",
            targets: ["MenuBarUI"]
        )
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "MenuBarUI",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "MenuBarUITests",
            dependencies: ["MenuBarUI"]
        )
    ]
)
