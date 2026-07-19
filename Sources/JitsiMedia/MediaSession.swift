#if os(macOS)
import Foundation
import WebRTC
import JitsiCore

/// Ties a `JitsiCore` `ParsedSessionDescription` to a live `RTCPeerConnection`:
/// sets the remote offer, adds local media, creates the answer, and surfaces the
/// Jingle `session-accept` and trickle ICE candidates for the signaling layer to
/// send. Remote candidates from `transport-info` are fed back in.
///
/// [MAC] — written by the agent, verified by a human on a real call
/// (docs/mac-signoff.md). Codec-neutral: it accepts whatever the JVB negotiates.
public final class MediaSession: NSObject {
    private let factory: RTCPeerConnectionFactory
    private let localMedia: LocalMediaSource

    private var peerConnection: RTCPeerConnection?
    private var offer: ParsedSessionDescription?
    private var bridge: BridgeChannel?

    // Outbound signaling — the ConferenceCall coordinator wires these to the
    // JitsiConference. `onLocalAnswer` fires once with our parsed SDP answer; the
    // signaling layer turns it into the Jingle `session-accept` (which owns the
    // XMPP addressing). `onLocalCandidate` fires per trickled ICE candidate.
    public var onLocalAnswer: ((LocalSDP) -> Void)?
    public var onLocalCandidate: ((ICECandidate, _ sdpMid: String?, _ mLineIndex: Int32) -> Void)?
    public var onIceStateChange: ((RTCIceConnectionState) -> Void)?
    public var onRemoteTrack: ((RTCMediaStreamTrack) -> Void)?
    /// Dominant-speaker endpoint id, delivered over the colibri bridge channel.
    public var onDominantSpeaker: (@Sendable (String) -> Void)?

    public init(factory: RTCPeerConnectionFactory, localMedia: LocalMediaSource) {
        self.factory = factory
        self.localMedia = localMedia
        super.init()
    }

    /// Accept the JVB's offer: build the peer connection, set the remote
    /// description, add local tracks, create + set the local answer, and surface
    /// it (`onLocalAnswer`) for the signaling layer to send as `session-accept`.
    public func accept(offer: ParsedSessionDescription, iceServers: [ICEServer]) {
        self.offer = offer

        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.continualGatheringPolicy = .gatherContinually
        config.iceServers = iceServers.map {
            RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        }

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        guard let pc = peerConnection else { return }

        pc.add(localMedia.audioTrack, streamIds: ["stream0"])
        pc.add(localMedia.videoTrack, streamIds: ["stream0"])

        let remote = SessionDescriptionMapper.remoteOffer(from: offer)
        pc.setRemoteDescription(remote) { [weak self] error in
            guard error == nil else { return }
            self?.createAndSendAnswer()
        }

        // Open the colibri bridge channel (dominant speaker in, receiver
        // constraints out) if the offer advertised one.
        if let wsString = offer.bridgeWebSocketURL, let url = URL(string: wsString) {
            let channel = BridgeChannel(url: url)
            bridge = channel
            let handler = onDominantSpeaker
            Task {
                if let handler { await channel.setDominantSpeakerHandler(handler) }
                await channel.connect()
            }
        }
    }

    /// Update receiver video constraints (lastN, selected endpoints, resolution)
    /// on the bridge — the output of `JitsiCore.QualityController`.
    public func setReceiverConstraints(_ constraints: ReceiverConstraints) {
        Task { try? await bridge?.send(constraints) }
    }

    /// Feed a remote ICE candidate (from a Jingle `transport-info`).
    public func addRemoteCandidate(_ candidate: ICECandidate, sdpMid: String?, mLineIndex: Int32) {
        let rtc = SessionDescriptionMapper.rtcIceCandidate(from: candidate, sdpMid: sdpMid,
                                                           sdpMLineIndex: mLineIndex)
        peerConnection?.add(rtc, completionHandler: { _ in })
    }

    public func close() {
        peerConnection?.close()
        peerConnection = nil
        let channel = bridge
        bridge = nil
        Task { await channel?.close() }
    }

    private func createAndSendAnswer() {
        guard let pc = peerConnection else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc.answer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp, error == nil else { return }
            pc.setLocalDescription(sdp) { error in
                guard error == nil else { return }
                // Surface the parsed answer; the signaling layer owns the Jingle
                // envelope + XMPP addressing (focus occupant, responder JID).
                self.onLocalAnswer?(SDPAnswerParser.parse(sdp.sdp))
            }
        }
    }
}

extension MediaSession: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let mapped = SessionDescriptionMapper.iceCandidate(from: candidate) else { return }
        onLocalCandidate?(mapped, candidate.sdpMid, candidate.sdpMLineIndex)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        onIceStateChange?(newState)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver,
                               streams mediaStreams: [RTCMediaStream]) {
        if let track = rtpReceiver.track { onRemoteTrack?(track) }
    }

    // Remaining required delegate methods — no-ops for now.
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
#endif
