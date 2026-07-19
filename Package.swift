// swift-tools-version:5.9
import PackageDescription

// The package is deliberately split so the pure-Swift core builds and tests on
// Linux (in CI, in the cloud sandbox), while the Apple-only media and app layers
// are only declared when the manifest is evaluated on macOS. This keeps
// `swift build --target JitsiCore` and `swift test --filter JitsiCoreTests`
// green on Linux with zero Apple dependencies — the load-bearing invariant of
// the whole project (see docs/findings.md and the build plan).

var products: [Product] = [
    .library(name: "JitsiCore", targets: ["JitsiCore"]),
    .executable(name: "LiveCapture", targets: ["LiveCapture"]),
]

var targets: [Target] = [
    // Pure Swift. No AppKit/AVFoundation/WebRTC/Combine. Builds on Linux.
    .target(
        name: "JitsiCore",
        path: "Sources/JitsiCore"
    ),
    // Headless signaling client used for [CLOUD-LIVE] fixture capture. Pure
    // Swift (URLSession) so it can run in the Linux container.
    .executableTarget(
        name: "LiveCapture",
        dependencies: ["JitsiCore"],
        path: "Tools/LiveCapture",
        exclude: ["python"]
    ),
    // Deterministic, offline unit tests. The only CI gate.
    .testTarget(
        name: "JitsiCoreTests",
        dependencies: ["JitsiCore"],
        path: "Tests/JitsiCoreTests"
    ),
    // [CLOUD-LIVE] integration tests against jitsi.luki.org. Network-gated,
    // non-blocking, on-demand. Skipped unless JITSI_LIVE_TESTS is set.
    .testTarget(
        name: "JitsiLiveTests",
        dependencies: ["JitsiCore"],
        path: "Tests/JitsiLiveTests"
    ),
]

#if os(macOS)
// Apple-only layers. These import AVFoundation/AppKit/SwiftUI and link the
// stasel/WebRTC XCFramework, which cannot build or link on Linux. They are only
// declared when the manifest runs on macOS, so Linux CI never sees them.
products.append(.library(name: "JitsiMedia", targets: ["JitsiMedia"]))

targets.append(
    .target(
        name: "JitsiMedia",
        dependencies: [
            "JitsiCore",
            .product(name: "WebRTC", package: "WebRTC"),
        ],
        path: "Sources/JitsiMedia",
        exclude: ["README.md"]
    )
)

// [MAC] Phase 2 media verification against a real RTCPeerConnection. macOS-only
// (links WebRTC), needs no live server or camera/mic — see docs/mac-runbook.md.
// Not a CI gate on Linux (the manifest never declares it there).
targets.append(
    .testTarget(
        name: "JitsiMediaTests",
        dependencies: [
            "JitsiMedia",
            "JitsiCore",
            .product(name: "WebRTC", package: "WebRTC"),
        ],
        path: "Tests/JitsiMediaTests"
    )
)
#endif

let package = Package(
    name: "JitsiMeetSwift",
    platforms: [
        .macOS(.v13),
    ],
    products: products,
    dependencies: {
        #if os(macOS)
        return [
            .package(url: "https://github.com/stasel/WebRTC.git", from: "150.0.0"),
        ]
        #else
        return []
        #endif
    }(),
    targets: targets
)
