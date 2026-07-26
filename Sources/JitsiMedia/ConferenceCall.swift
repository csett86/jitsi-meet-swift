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
    /// A remote participant's track is now being received, with the participant
    /// it belongs to. This is what the UI puts in a tile.
    public var onRemoteMediaTrack: ((RemoteMediaTrack) -> Void)?
    /// A previously received remote track went away, by mid.
    public var onRemoteTrackEnded: ((String) -> Void)?
    /// Every conference event, re-broadcast. The call owns the conference's
    /// single-consumer `AsyncStream`, so this is how the app sees roster,
    /// connection state and dominant-speaker changes.
    public var onEvent: ((ConferenceEvent) -> Void)?
    /// A media-layer error (renegotiation refused, no peer connection, …).
    public var onError: ((String) -> Void)?
    /// The negotiated transceiver layout after each (re)negotiation.
    public var onNegotiated: ((String) -> Void)?
    /// The colibri bridge wss handshake completed.
    public var onBridgeOpen: (@Sendable () -> Void)?
    /// Every raw colibri message from the JVB (diagnostics).
    public var onBridgeMessage: (@Sendable (String) -> Void)?
    /// The colibri bridge socket closed (close code). Load-bearing for call
    /// survival — see `MediaSession.onBridgeClose`.
    public var onBridgeClose: (@Sendable (Int) -> Void)?
    /// Dominant-speaker endpoint id, delivered over the colibri bridge channel.
    public var onDominantSpeaker: (@Sendable (String) -> Void)?
    /// The focus ended the Jingle session, with its `<reason>` if given. Normal
    /// end-of-call signal (e.g. the last other participant left).
    public var onSessionTerminated: ((String?) -> Void)?

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
            onEvent?(event)
            switch event {
            case .iceServers(let servers):
                iceServers = servers
            case .remoteTracks(let tracks):
                // Another participant published or dropped media: give the peer
                // connection a matching receive section and renegotiate.
                session?.syncRemoteTracks(tracks)
            case .sessionDescription(let offer):
                // A re-invite replaces any previous session; close the old peer
                // connection rather than leaking it.
                startSession(offer: offer)
            case .sessionTerminated(let reason):
                // Jicofo ended the session (commonly: everyone else left). Tear
                // the media down instead of leaving a peer connection that will
                // later report a misleading ICE failure.
                onSessionTerminated?(reason)
                closeSession()
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

    public func close() { closeSession() }

    /// Tear down the current media session and reset the per-session state, so
    /// a later re-invite (`session-initiate`) starts from a clean slate.
    private func closeSession() {
        session?.close()
        session = nil
        localCreds = [:]
        bufferedCandidates = []
        answerReady = false
    }

    /// RTP counters for the current call — proof that media is actually flowing,
    /// not merely that ICE connected. Yields zeroed stats when there is no call.
    public func statistics(_ completion: @escaping (MediaStats) -> Void) {
        guard let session else { return completion(MediaStats()) }
        session.statistics(completion)
    }

    /// Push receiver video constraints (lastN / selected / resolution) to the
    /// bridge — the output of `JitsiCore.QualityController`. No-op before a call.
    public func setReceiverConstraints(_ constraints: ReceiverConstraints) {
        session?.setReceiverConstraints(constraints)
    }

    private func startSession(offer: ParsedSessionDescription) {
        closeSession()      // a re-invite must not leak the previous connection
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
        session.onRemoteMediaTrack = { [weak self] track in self?.onRemoteMediaTrack?(track) }
        session.onRemoteTrackEnded = { [weak self] mid in self?.onRemoteTrackEnded?(mid) }
        session.onError = { [weak self] message in self?.onError?(message) }
        session.onNegotiated = { [weak self] shape in self?.onNegotiated?(shape) }
        // Forward the @Sendable bridge handlers as-is (no self capture) — these
        // must be set before accept(), which opens the bridge channel.
        session.onBridgeOpen = onBridgeOpen
        session.onBridgeClose = onBridgeClose
        session.onBridgeMessage = onBridgeMessage
        session.onDominantSpeaker = onDominantSpeaker

        session.accept(offer: offer, iceServers: iceServers)
    }

    private func trickle(_ candidate: ICECandidate, mid: String) async {
        let creds = localCreds[mid]
        await conference.sendLocalCandidates(mediaName: mid, ufrag: creds?.ufrag,
                                             pwd: creds?.pwd, candidates: [candidate])
    }
}
#endif
