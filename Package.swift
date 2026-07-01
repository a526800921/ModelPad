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
    dependencies: [
        // 阶段 3：轻量 HTTP 服务器。SwiftNIO 是 Apple 维护的非阻塞网络库，
        // 比 Vapor 轻一个数量级，只引入 HTTP 解析和事件循环，不引入路由框架、
        // 模板引擎或 ORM。对一个 8 端点的本地 JSON API 而言是最小可行选择。
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
        )
    ]
)
