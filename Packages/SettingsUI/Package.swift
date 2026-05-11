// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SettingsUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SettingsUI",
            targets: ["SettingsUI"]
        )
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Settings"),
        .package(path: "../Permissions"),
        .package(path: "../ModelStore")
    ],
    targets: [
        .target(
            name: "SettingsUI",
            dependencies: [
                "Core",
                "Settings",
                "Permissions",
                "ModelStore"
            ]
        ),
        .testTarget(
            name: "SettingsUITests",
            dependencies: ["SettingsUI"]
        )
    ]
)
