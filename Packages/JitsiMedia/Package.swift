// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JitsiMedia",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JitsiMedia", targets: ["JitsiMedia"]),
    ],
    dependencies: [
        // Community-maintained pre-built WebRTC XCFrameworks (VP8/VP9/H264/H265).
        // Pinned to a specific release — do NOT track `main`.
        .package(url: "https://github.com/stasel/WebRTC", exact: "150.0.0"),
    ],
    targets: [
        // Phase 0 placeholder — will grow to cover: RTCPeerConnection lifecycle,
        // Jingle↔WebRTC mapping, and media quality control.
        .target(
            name: "JitsiMedia",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
            ]
        ),
        .testTarget(
            name: "JitsiMediaTests",
            dependencies: ["JitsiMedia"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
