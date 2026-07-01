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
        ),
        .executable(
            name: "ModelPad",
            targets: ["ModelPadApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "ModelPadCore",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio")
            ]
        ),
        .testTarget(
            name: "ModelPadCoreTests",
            dependencies: ["ModelPadCore"]
        ),
        .executableTarget(
            name: "ModelPadApp",
            dependencies: ["ModelPadCore"],
            path: "App/Sources",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-framework", "-Xlinker", "AppKit"]),
                .unsafeFlags(["-Xlinker", "-framework", "-Xlinker", "SwiftUI"])
            ]
        )
    ]
)
