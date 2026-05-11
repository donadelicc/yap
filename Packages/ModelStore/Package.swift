// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ModelStore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ModelStore", targets: ["ModelStore"])
    ],
    dependencies: [
        .package(name: "Core", path: "../Core")
    ],
    targets: [
        .target(
            name: "ModelStore",
            dependencies: ["Core"],
            resources: [
                .process("Resources/catalog.json")
            ]
        ),
        .testTarget(
            name: "ModelStoreTests",
            dependencies: ["ModelStore"]
        )
    ]
)
