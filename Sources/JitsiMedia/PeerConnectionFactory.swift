#if os(macOS)
import Foundation
import WebRTC

/// Thin wrapper over `RTCPeerConnectionFactory`. [MAC] — links the
/// stasel/WebRTC XCFramework, so it only builds on Apple platforms.
///
/// It does exactly two things: initialize SSL once per process, and build a
/// factory with the default hardware-accelerated video codec factories.
/// `MediaSession` owns everything else about a peer connection.
public final class PeerConnectionFactory {
    public let factory: RTCPeerConnectionFactory

    private static let sslInit: Bool = {
        RTCInitializeSSL()
    }()

    public init() {
        _ = Self.sslInit
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }
}
#endif
