#if os(macOS)
import Foundation
import WebRTC
import JitsiCore

/// Thin wrapper over `RTCPeerConnectionFactory` and the bridge between
/// `JitsiCore`'s pure signaling types and WebRTC. [MAC] — links the
/// stasel/WebRTC XCFramework, so it only builds on Apple platforms.
///
/// This is the entry point for Phase 2 (media). It deliberately starts small:
/// initialize SSL once, build a factory with the default hardware-accelerated
/// video codec factories, and translate `JitsiCore.ICEServer` values (from the
/// signaling layer's TURN discovery) into `RTCIceServer`s.
public final class PeerConnectionFactory {
    public let factory: RTCPeerConnectionFactory

    private static let sslInit: Bool = {
        RTCInitializeSSL()
    }()

    public init() {
        _ = Self.sslInit
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: encoder,
            decoderFactory: decoder
        )
    }

    /// The video codecs the default encoder factory advertises — used later to
    /// reconcile against what the JVB offers in the `ParsedSessionDescription`
    /// (AV1/VP8/H264/VP9 on jitsi.luki.org).
    public var supportedVideoCodecs: [String] {
        RTCDefaultVideoEncoderFactory().supportedCodecs().map(\.name)
    }

    /// Translate signaling-layer ICE servers into WebRTC ICE servers.
    public func rtcIceServers(from servers: [ICEServer]) -> [RTCIceServer] {
        servers.map { server in
            RTCIceServer(
                urlStrings: server.urls,
                username: server.username,
                credential: server.credential
            )
        }
    }
}
#endif
