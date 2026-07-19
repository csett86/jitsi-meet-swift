#if os(macOS)
import Foundation
import WebRTC
import JitsiCore

/// Wires a `JitsiConference` (pure signaling) to a `MediaSession` (WebRTC) so a
/// received offer becomes a connected call: on the JVB's `session-initiate` it
/// answers with a real peer connection, sends the Jingle `session-accept` back
/// through the conference with correct addressing, trickles local ICE
/// candidates as `transport-info`, and feeds the focus's remote candidates in.
///
/// [MAC] — links WebRTC. The signaling half is pure `JitsiCore`; this is the
/// Apple-only glue. Callbacks fire on WebRTC's signaling thread; async hops to
/// the `JitsiConference` actor are made via `Task`.
public final class ConferenceCall {
    private let conference: JitsiConference
    private let factory: PeerConnectionFactory
    private let localMedia: LocalMediaSource
    private var session: MediaSession?

    private var iceServers: [ICEServer] = []
    /// ICE ufrag/pwd from our answer, per media kind — needed on `transport-info`.
    private var localCreds: [String: (ufrag: String?, pwd: String?)] = [:]
    /// Candidates gathered before the answer was parsed (creds not known yet).
    private var bufferedCandidates: [(candidate: ICECandidate, mid: String)] = []
    private var answerReady = false

    /// Observability for the harness / app.
    public var onIceStateChange: ((RTCIceConnectionState) -> Void)?
    public var onRemoteTrack: ((RTCMediaStreamTrack) -> Void)?
    /// The colibri bridge wss handshake completed.
    public var onBridgeOpen: (@Sendable () -> Void)?
    /// Dominant-speaker endpoint id, delivered over the colibri bridge channel.
    public var onDominantSpeaker: (@Sendable (String) -> Void)?

    public init(conference: JitsiConference, factory: PeerConnectionFactory,
                localMedia: LocalMediaSource) {
        self.conference = conference
        self.factory = factory
        self.localMedia = localMedia
    }

    /// Consume conference events and drive the media call. Returns when the
    /// event stream ends (conference left / disconnected).
    public func run() async {
        let events = await conference.events
        for await event in events {
            switch event {
            case .iceServers(let servers):
                iceServers = servers
            case .sessionDescription(let offer):
                startSession(offer: offer)
            case .remoteCandidates(let remote):
                let mLineIndex: Int32 = remote.mediaName == "video" ? 1 : 0
                for candidate in remote.candidates {
                    session?.addRemoteCandidate(candidate, sdpMid: remote.mediaName,
                                                mLineIndex: mLineIndex)
                }
            default:
                break
            }
        }
    }

    public func close() { session?.close() }

    /// Push receiver video constraints (lastN / selected / resolution) to the
    /// bridge — the output of `JitsiCore.QualityController`. No-op before a call.
    public func setReceiverConstraints(_ constraints: ReceiverConstraints) {
        session?.setReceiverConstraints(constraints)
    }

    private func startSession(offer: ParsedSessionDescription) {
        let session = MediaSession(factory: factory.factory, localMedia: localMedia)
        self.session = session

        session.onLocalAnswer = { [weak self] local in
            guard let self else { return }
            for media in local.media { self.localCreds[media.kind] = (media.ufrag, media.pwd) }
            self.answerReady = true
            let buffered = self.bufferedCandidates
            self.bufferedCandidates = []
            Task {
                await self.conference.acceptSession(local: local)
                for item in buffered { await self.trickle(item.candidate, mid: item.mid) }
            }
        }
        session.onLocalCandidate = { [weak self] candidate, sdpMid, _ in
            guard let self else { return }
            let mid = sdpMid ?? "audio"
            if self.answerReady {
                Task { await self.trickle(candidate, mid: mid) }
            } else {
                self.bufferedCandidates.append((candidate, mid))
            }
        }
        session.onIceStateChange = { [weak self] state in self?.onIceStateChange?(state) }
        session.onRemoteTrack = { [weak self] track in self?.onRemoteTrack?(track) }
        // Forward the @Sendable bridge handlers directly (no self capture) — these
        // must be set before accept(), which opens the bridge channel.
        let bridgeOpen = onBridgeOpen
        session.onBridgeOpen = { bridgeOpen?() }
        let speaker = onDominantSpeaker
        session.onDominantSpeaker = { endpoint in speaker?(endpoint) }

        session.accept(offer: offer, iceServers: iceServers)
    }

    private func trickle(_ candidate: ICECandidate, mid: String) async {
        let creds = localCreds[mid]
        await conference.sendLocalCandidates(mediaName: mid, ufrag: creds?.ufrag,
                                             pwd: creds?.pwd, candidates: [candidate])
    }
}
#endif
