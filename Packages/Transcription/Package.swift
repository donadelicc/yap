// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Transcription",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Transcription", targets: ["Transcription"])
    ],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "ModelStore", path: "../ModelStore"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.9.4")
    ],
    targets: [
        .target(
            name: "Transcription",
            dependencies: [
                "Core",
                "ModelStore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .testTarget(
            name: "TranscriptionTests",
            dependencies: ["Transcription"]
        )
    ]
)
