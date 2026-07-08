// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JitsiNativeMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "JitsiNativeMac", targets: ["JitsiNativeMac"]),
    ],
    dependencies: [
        .package(path: "Packages/JitsiSignaling"),
        .package(path: "Packages/JitsiMedia"),
    ],
    targets: [
        .executableTarget(
            name: "JitsiNativeMac",
            dependencies: [
                "JitsiSignaling",
                "JitsiMedia",
            ]),
        .testTarget(
            name: "JitsiNativeMacTests",
            dependencies: ["JitsiNativeMac"]),
    ]
)
