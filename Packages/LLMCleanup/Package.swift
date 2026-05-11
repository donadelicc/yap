// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LLMCleanup",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LLMCleanup", targets: ["LLMCleanup"])
    ],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "ModelStore", path: "../ModelStore"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.29.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.29.1")
    ],
    targets: [
        .target(
            name: "LLMCleanup",
            dependencies: [
                "Core",
                "ModelStore",
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples")
            ]
        ),
        .testTarget(
            name: "LLMCleanupTests",
            dependencies: ["LLMCleanup"]
        )
    ]
)
