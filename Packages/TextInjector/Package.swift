// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TextInjector",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TextInjector",
            targets: ["TextInjector"]
        )
    ],
    dependencies: [
        .package(name: "Core", path: "../Core")
    ],
    targets: [
        .target(
            name: "TextInjector",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "TextInjectorTests",
            dependencies: ["TextInjector"]
        )
    ]
)
