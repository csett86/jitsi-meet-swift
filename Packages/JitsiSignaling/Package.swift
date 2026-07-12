// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JitsiSignaling",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JitsiSignaling", targets: ["JitsiSignaling"]),
    ],
    targets: [
        // Phase 0 placeholder — will grow to cover: XMPP transport, stanza parsing,
        // MUC, Jingle negotiation, and service discovery (disco).
        .target(name: "JitsiSignaling"),
        .testTarget(
            name: "JitsiSignalingTests",
            dependencies: ["JitsiSignaling"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
