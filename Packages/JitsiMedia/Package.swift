// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JitsiMedia",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "JitsiMedia",
            targets: ["JitsiMedia"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", from: "115.5750.0"),
    ],
    targets: [
        .target(
            name: "JitsiMedia",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
            ]),
        .testTarget(
            name: "JitsiMediaTests",
            dependencies: ["JitsiMedia"]),
    ]
)
