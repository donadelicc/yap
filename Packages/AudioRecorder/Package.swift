// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AudioRecorder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AudioRecorder",
            targets: ["AudioRecorder"]
        )
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "AudioRecorder",
            dependencies: ["Core"],
            linkerSettings: [
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "AudioRecorderTests",
            dependencies: ["AudioRecorder"]
        )
    ]
)
