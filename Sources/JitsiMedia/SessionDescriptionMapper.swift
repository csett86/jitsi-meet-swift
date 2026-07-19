#if os(macOS)
import Foundation
import WebRTC
import JitsiCore

/// Bridges `JitsiCore`'s pure SDP/Jingle helpers to WebRTC's `RTCSessionDescription`
/// and `RTCIceCandidate`. [MAC] — the heavy lifting (Jingle↔SDP) lives in
/// `JitsiCore` and is unit-tested on Linux; this is the thin Apple-side adapter.
///
/// **Riskiest integration point** (docs/mac-runbook.md): only a real
/// `RTCPeerConnection` confirms WebRTC accepts the generated SDP. Validate
/// incrementally against one live call.
public enum SessionDescriptionMapper {

    /// The JVB's `session-initiate`, as an SDP offer to set as the remote
    /// description.
    public static func remoteOffer(from description: ParsedSessionDescription) -> RTCSessionDescription {
        RTCSessionDescription(type: .offer, sdp: SDPBuilder.offer(from: description))
    }

    /// A locally-gathered candidate, as a Jingle ICE candidate for trickle.
    public static func iceCandidate(from candidate: RTCIceCandidate) -> ICECandidate? {
        SDPCandidate.parse(candidate.sdp)
    }

    /// A Jingle ICE candidate, as an `RTCIceCandidate` to add to the connection.
    public static func rtcIceCandidate(from candidate: ICECandidate,
                                       sdpMid: String?, sdpMLineIndex: Int32) -> RTCIceCandidate {
        RTCIceCandidate(sdp: SDPCandidate.line(from: candidate),
                        sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}
#endif
