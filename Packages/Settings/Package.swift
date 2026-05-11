// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Settings",
            targets: ["Settings"]
        )
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "Settings",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: ["Settings"]
        )
    ]
)
