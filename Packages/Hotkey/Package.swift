// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Hotkey",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Hotkey",
            targets: ["Hotkey"]
        )
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "Hotkey",
            dependencies: ["Core"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "HotkeyTests",
            dependencies: ["Hotkey"]
        )
    ]
)
