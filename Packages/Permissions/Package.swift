// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Permissions",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Permissions",
            targets: ["Permissions"]
        )
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "Permissions",
            dependencies: ["Core"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "PermissionsTests",
            dependencies: ["Permissions"]
        )
    ]
)
