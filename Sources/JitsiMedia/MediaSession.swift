#if os(macOS)
import Foundation
import WebRTC
import JitsiCore

/// A remote participant's track, once WebRTC has actually created a receiver for
/// it. `endpointID` is exact — it comes from the mid the client allocated for
/// that participant's source, not from string-matching an msid.
public struct RemoteMediaTrack {
    public let endpointID: String
    public let kind: String              // audio / video
    public let mid: String
    /// The Jitsi source name (`<endpoint>-v0`) — what receiver constraints are
    /// keyed by, so the UI must pass it back when it asks for a resolution.
    public let sourceName: String?
    public let track: RTCMediaStreamTrack

    public var videoTrack: RTCVideoTrack? { track as? RTCVideoTrack }
}

/// What is actually on the wire, from WebRTC's own RTP statistics. "The call is
/// connected" and "media is flowing" are different claims — this is the second
/// one, and it is the only way to tell a working camera from a black frame.
public struct MediaStats: Equatable, Sendable {
    public var audioBytesSent: Int64 = 0
    public var videoBytesSent: Int64 = 0
    public var audioBytesReceived: Int64 = 0
    public var videoBytesReceived: Int64 = 0
    public var framesEncoded: Int64 = 0
    public var framesDecoded: Int64 = 0
    /// Remote video streams currently being received.
    public var inboundVideoStreams: Int = 0
    /// Bytes received on the selected ICE candidate pair — everything the bridge
    /// sent us, before RTP demuxing. If this grows while the RTP counters stay at
    /// zero, the packets are arriving but not being matched to a track.
    public var transportBytesReceived: Int64 = 0
    /// DTLS state of the bundled transport. Without `connected` there are no SRTP
    /// keys, so neither side can decrypt the other's media — which looks exactly
    /// like "ICE is up but nothing arrives".
    public var dtlsState: String = "unknown"
    /// RTP/RTCP packets received on the bundled transport, whether or not they
    /// were matched to a track.
    public var transportPacketsReceived: Int64 = 0
    /// The codec our video encoder actually settled on — the JVB's first offered
    /// payload type, unless overridden. Worth logging: which codec we send
    /// decides whether every other participant can decode us.
    public var sendVideoCodec: String?
    /// Codecs we are decoding remote video with.
    public var receiveVideoCodecs: Set<String> = []

    public init() {}

    public var isSendingMedia: Bool { audioBytesSent > 0 && videoBytesSent > 0 }
    public var isReceivingMedia: Bool { audioBytesReceived > 0 || videoBytesReceived > 0 }

    public var summary: String {
        let up = "↑ a/v \(audioBytesSent)/\(videoBytesSent)B (\(framesEncoded) frames"
            + (sendVideoCodec.map { ", \($0)" } ?? "") + ")"
        let down = "↓ a/v \(audioBytesReceived)/\(videoBytesReceived)B "
            + "(\(framesDecoded) frames, \(inboundVideoStreams) stream"
            + (inboundVideoStreams == 1 ? "" : "s")
            + (receiveVideoCodecs.isEmpty ? "" : ", " + receiveVideoCodecs.sorted().joined(separator: "+"))
            + ")"
        return up + " · " + down + " · transport ↓ \(transportBytesReceived)B/"
            + "\(transportPacketsReceived)pkt dtls=\(dtlsState)"
    }
}

/// Ties a `JitsiCore` `ParsedSessionDescription` to a live `RTCPeerConnection`:
/// sets the remote offer, adds local media, creates the answer, and surfaces the
/// Jingle `session-accept` and trickle ICE candidates for the signaling layer to
/// send. Remote candidates from `transport-info` are fed back in.
///
/// It also owns the *receive* side: the bridge announces other participants'
/// media with `source-add`/`source-remove` and never re-offers, so this class
/// rebuilds the remote description from ``RemoteSDPSession`` and renegotiates
/// locally whenever the source set changes. That is what makes remote audio and
/// video arrive at all.
///
/// [MAC] — written by the agent, verified by a human on a real call
/// (docs/mac-signoff.md). Codec-neutral: it accepts whatever the JVB negotiates.
public final class MediaSession: NSObject {
    private let factory: RTCPeerConnectionFactory
    private let localMedia: LocalMediaSource

    private var peerConnection: RTCPeerConnection?
    private var bridge: BridgeChannel?
    /// The evolving remote description (bridge sections + one per remote track).
    private var remote: RemoteSDPSession?
    /// Serializes every peer-connection and `remote` mutation; WebRTC callbacks
    /// and conference events arrive on different threads.
    private let queue = DispatchQueue(label: "org.jitsi.swift.media-session")
    private var negotiating = false
    private var renegotiationPending = false
    /// mids we have already surfaced a remote track for.
    private var reportedMids: Set<String> = []
    /// Last receiver constraints, replayed once the bridge channel is open.
    private var lastConstraints: ReceiverConstraints?

    // Outbound signaling — the ConferenceCall coordinator wires these to the
    // JitsiConference. `onLocalAnswer` fires once with our parsed SDP answer; the
    // signaling layer turns it into the Jingle `session-accept` (which owns the
    // XMPP addressing). `onLocalCandidate` fires per trickled ICE candidate.
    public var onLocalAnswer: ((LocalSDP) -> Void)?
    public var onLocalCandidate: ((ICECandidate, _ sdpMid: String?, _ mLineIndex: Int32) -> Void)?
    public var onIceStateChange: ((RTCIceConnectionState) -> Void)?
    /// A remote participant's track became available (after renegotiation).
    public var onRemoteMediaTrack: ((RemoteMediaTrack) -> Void)?
    /// A remote track went away (`source-remove`, or its owner left), by mid.
    public var onRemoteTrackEnded: ((String) -> Void)?
    /// Dominant-speaker endpoint id, delivered over the colibri bridge channel.
    public var onDominantSpeaker: (@Sendable (String) -> Void)?
    /// Fires once the colibri bridge wss handshake completes.
    public var onBridgeOpen: (@Sendable () -> Void)?
    /// Every raw colibri message from the JVB (diagnostics).
    public var onBridgeMessage: (@Sendable (String) -> Void)?
    /// Fires when the colibri bridge socket closes, with the close code. A close
    /// here is load-bearing: the JVB treats the bridge channel as the endpoint's
    /// message transport, so losing it can take the media session with it.
    public var onBridgeClose: (@Sendable (Int) -> Void)?
    /// Renegotiation failed — the receive path is the part most likely to be
    /// rejected by WebRTC, and silence there is impossible to debug.
    public var onError: ((String) -> Void)?
    /// The negotiated transceiver layout (mid/kind/direction) after each
    /// negotiation — diagnostics for live runs.
    public var onNegotiated: ((String) -> Void)?

    public init(factory: RTCPeerConnectionFactory, localMedia: LocalMediaSource) {
        self.factory = factory
        self.localMedia = localMedia
        super.init()
    }

    /// Accept the JVB's offer: build the peer connection, set the remote
    /// description, add local tracks, create + set the local answer, and surface
    /// it (`onLocalAnswer`) for the signaling layer to send as `session-accept`.
    public func accept(offer: ParsedSessionDescription, iceServers: [ICEServer]) {
        queue.async { self.acceptLocked(offer: offer, iceServers: iceServers) }
    }

    /// Reconcile the receive-only m-sections with the conference's current remote
    /// tracks and renegotiate if that changed anything. Driven by `source-add` /
    /// `source-remove` (and participants leaving).
    public func syncRemoteTracks(_ tracks: [RemoteTrack]) {
        queue.async {
            guard var remote = self.remote else { return }
            let changed = remote.sync(tracks: tracks)
            self.remote = remote
            guard changed else { return }
            self.renegotiate()
        }
    }

    /// Update receiver video constraints (lastN, selected endpoints, resolution)
    /// on the bridge — the output of `JitsiCore.QualityController`.
    ///
    /// The JVB forwards no video to an endpoint that has not asked for any, so
    /// this is not merely an optimization: the constraints are what turn remote
    /// video on. They are remembered and re-sent once the bridge channel opens,
    /// because the first tile usually appears before the wss handshake finishes.
    public func setReceiverConstraints(_ constraints: ReceiverConstraints) {
        queue.async {
            self.lastConstraints = constraints
            self.sendConstraints(constraints)
        }
    }

    private func sendConstraints(_ constraints: ReceiverConstraints) {
        guard let bridge else { return }
        Task { try? await bridge.send(constraints) }
    }

    /// Feed a remote ICE candidate (from a Jingle `transport-info`).
    public func addRemoteCandidate(_ candidate: ICECandidate, sdpMid: String?, mLineIndex: Int32) {
        let rtc = SessionDescriptionMapper.rtcIceCandidate(from: candidate, sdpMid: sdpMid,
                                                           sdpMLineIndex: mLineIndex)
        queue.async { self.peerConnection?.add(rtc, completionHandler: { _ in }) }
    }

    /// Current RTP counters, or nil before the call exists.
    public func statistics(_ completion: @escaping (MediaStats) -> Void) {
        queue.async {
            guard let pc = self.peerConnection else { return completion(MediaStats()) }
            pc.statistics { report in
                var stats = MediaStats()
                // codec stats id → "VP8" / "opus"; RTP entries reference them.
                var codecs: [String: String] = [:]
                for entry in report.statistics.values where entry.type == "codec" {
                    if let mime = entry.values["mimeType"] as? String {
                        codecs[entry.id] = mime.components(separatedBy: "/").last ?? mime
                    }
                }
                for entry in report.statistics.values {
                    let kind = (entry.values["kind"] as? String)
                        ?? (entry.values["mediaType"] as? String) ?? ""
                    let bytes = (entry.values["bytesSent"] ?? entry.values["bytesReceived"]) as? Int64 ?? 0
                    let codec = (entry.values["codecId"] as? String).flatMap { codecs[$0] }
                    switch entry.type {
                    case "outbound-rtp":
                        if kind == "audio" { stats.audioBytesSent += bytes }
                        if kind == "video" {
                            stats.videoBytesSent += bytes
                            stats.framesEncoded += entry.values["framesEncoded"] as? Int64 ?? 0
                            stats.sendVideoCodec = codec ?? stats.sendVideoCodec
                        }
                    case "inbound-rtp":
                        if kind == "audio" { stats.audioBytesReceived += bytes }
                        if kind == "video" {
                            stats.videoBytesReceived += bytes
                            stats.framesDecoded += entry.values["framesDecoded"] as? Int64 ?? 0
                            stats.inboundVideoStreams += 1
                            if let codec { stats.receiveVideoCodecs.insert(codec) }
                        }
                    case "candidate-pair":
                        if entry.values["nominated"] as? Bool == true {
                            stats.transportBytesReceived += entry.values["bytesReceived"] as? Int64 ?? 0
                        }
                    case "transport":
                        if let dtls = entry.values["dtlsState"] as? String { stats.dtlsState = dtls }
                        stats.transportPacketsReceived += entry.values["packetsReceived"] as? Int64 ?? 0
                    default:
                        break
                    }
                }
                completion(stats)
            }
        }
    }

    public func close() {
        queue.async {
            self.peerConnection?.close()
            self.peerConnection = nil
            self.remote = nil
            self.reportedMids = []
            let channel = self.bridge
            self.bridge = nil
            Task { await channel?.close() }
        }
    }

    // MARK: - Negotiation (queue-confined)

    private func acceptLocked(offer: ParsedSessionDescription, iceServers: [ICEServer]) {
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
        guard let pc = peerConnection else {
            onError?("could not create the peer connection")
            return
        }

        pc.add(localMedia.audioTrack, streamIds: [LocalMediaSource.streamID])
        pc.add(localMedia.videoTrack, streamIds: [LocalMediaSource.streamID])

        let remote = RemoteSDPSession(offer: offer)
        self.remote = remote
        negotiating = true
        pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: remote.sdp())) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    self.negotiating = false
                    self.onError?("setRemoteDescription failed: \(error.localizedDescription)")
                    return
                }
                self.answer(isInitial: true)
            }
        }

        // Open the colibri bridge channel (dominant speaker in, receiver
        // constraints out) if the offer advertised one.
        if let wsString = offer.bridgeWebSocketURL, let url = URL(string: wsString) {
            let channel = BridgeChannel(url: url)
            bridge = channel
            let speakerHandler = onDominantSpeaker
            let userOpenHandler = onBridgeOpen
            let closeHandler = onBridgeClose
            let messageHandler = onBridgeMessage
            // Anything asked for before the handshake completed has to be sent
            // again now that there is a socket to send it on.
            let openHandler: @Sendable () -> Void = { [weak self] in
                userOpenHandler?()
                self?.queue.async {
                    guard let self, let constraints = self.lastConstraints else { return }
                    self.sendConstraints(constraints)
                }
            }
            Task {
                if let speakerHandler { await channel.setDominantSpeakerHandler(speakerHandler) }
                await channel.setOpenHandler(openHandler)
                if let closeHandler { await channel.setCloseHandler(closeHandler) }
                if let messageHandler { await channel.setMessageHandler(messageHandler) }
                await channel.connect()
            }
        }
    }

    /// Rebuild the remote offer (now with a section per remote track) and answer
    /// it. No Jingle is sent: `source-add` is the bridge telling us what it will
    /// send, so the renegotiation is purely local.
    private func renegotiate() {
        guard let pc = peerConnection, let remote else { return }
        guard !negotiating else { renegotiationPending = true; return }
        negotiating = true
        pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: remote.sdp())) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    self.negotiating = false
                    self.onError?("remote renegotiation failed: \(error.localizedDescription)")
                    return
                }
                self.answer(isInitial: false)
            }
        }
    }

    /// createAnswer + setLocalDescription, then publish what changed.
    private func answer(isInitial: Bool) {
        guard let pc = peerConnection else { negotiating = false; return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc.answer(for: constraints) { [weak self] sdp, error in
            guard let self else { return }
            guard let sdp, error == nil else {
                self.queue.async {
                    self.negotiating = false
                    self.onError?("createAnswer failed: \(error?.localizedDescription ?? "unknown")")
                }
                return
            }
            pc.setLocalDescription(sdp) { error in
                self.queue.async {
                    self.negotiating = false
                    if let error {
                        self.onError?("setLocalDescription failed: \(error.localizedDescription)")
                        return
                    }
                    // Only the first answer becomes a Jingle `session-accept`; the
                    // focus is not party to the receive-side renegotiations.
                    if isInitial {
                        self.onLocalAnswer?(SDPAnswerParser.parse(sdp.sdp))
                    }
                    self.publishRemoteTracks()
                    if self.renegotiationPending {
                        self.renegotiationPending = false
                        self.renegotiate()
                    }
                }
            }
        }
    }

    /// Match the peer connection's transceivers back to participants by mid and
    /// surface what appeared or went away.
    private func publishRemoteTracks() {
        guard let pc = peerConnection, let remote else { return }
        var live: Set<String> = []
        for transceiver in pc.transceivers {
            guard let mid = transceiver.mid as String?, !mid.isEmpty,
                  let endpointID = remote.endpoint(forMid: mid),
                  let track = transceiver.receiver.track else { continue }
            live.insert(mid)
            guard !reportedMids.contains(mid) else { continue }
            reportedMids.insert(mid)
            onRemoteMediaTrack?(RemoteMediaTrack(endpointID: endpointID, kind: track.kind,
                                                 mid: mid,
                                                 sourceName: remote.sourceName(forMid: mid),
                                                 track: track))
        }
        for mid in reportedMids.subtracting(live) {
            reportedMids.remove(mid)
            onRemoteTrackEnded?(mid)
        }
        // The negotiated shape of the session, for the live-run log: which mid is
        // receiving what. A mismatch here is invisible in the SDP alone.
        let shape = pc.transceivers.map {
            "\($0.mid)/\($0.mediaType == .audio ? "a" : "v")/\(Self.describe($0.direction))"
        }.joined(separator: " ")
        onNegotiated?(shape)
    }
}

extension MediaSession {
    static func describe(_ direction: RTCRtpTransceiverDirection) -> String {
        switch direction {
        case .sendRecv: return "sendrecv"
        case .sendOnly: return "sendonly"
        case .recvOnly: return "recvonly"
        case .inactive: return "inactive"
        case .stopped: return "stopped"
        @unknown default: return "unknown"
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

    // Remaining required delegate methods — no-ops. Remote tracks are surfaced
    // from `publishRemoteTracks()` instead, because only the mid (assigned during
    // renegotiation) says which participant a track belongs to.
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver,
                               streams mediaStreams: [RTCMediaStream]) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
#endif
