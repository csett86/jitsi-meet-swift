// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JitsiSignaling",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JitsiSignaling", targets: ["JitsiSignaling"]),
    ],
    targets: [
        .target(name: "JitsiSignaling"),
        .testTarget(
            name: "JitsiSignalingTests",
            dependencies: ["JitsiSignaling"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
