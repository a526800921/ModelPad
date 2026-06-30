// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ModelPadCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ModelPadCore",
            targets: ["ModelPadCore"]
        )
    ],
    targets: [
        .target(
            name: "ModelPadCore"
        ),
        .testTarget(
            name: "ModelPadCoreTests",
            dependencies: ["ModelPadCore"]
        )
    ]
)
