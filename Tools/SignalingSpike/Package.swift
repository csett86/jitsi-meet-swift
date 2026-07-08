// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SignalingSpike",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SignalingSpike", targets: ["SignalingSpike"]),
    ],
    dependencies: [
        .package(path: "../../Packages/JitsiSignaling"),
    ],
    targets: [
        .executableTarget(
            name: "SignalingSpike",
            dependencies: ["JitsiSignaling"]),
    ]
)
