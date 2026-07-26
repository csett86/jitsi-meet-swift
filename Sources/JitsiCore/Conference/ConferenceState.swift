import Foundation

/// The conference's high-level lifecycle, suitable for driving connection-state
/// UI. Distinct from ``ConnectionState`` (the raw socket) — this tracks join
/// progress (auth → join → joined).
public enum ConferenceState: Equatable, Sendable {
    case idle
    case connecting
    case authenticating
    case joining
    case joined
    case reconnecting
    case failed(String)
    case left
}

/// Everything the conference emits as it runs. Consumed as an `AsyncStream`.
public enum ConferenceEvent: Equatable, Sendable {
    case stateChanged(ConferenceState)
    case roster(RosterChange)
    case capabilities(BackendCapabilities)
    case iceServers([ICEServer])
    case conferenceReady(ConferenceResponse)
    case sessionDescription(ParsedSessionDescription)
    /// Trickle ICE candidates the focus sent us in a `transport-info`, per media
    /// section. The media layer feeds these into the peer connection.
    case remoteCandidates(RemoteCandidates)
    /// The focus ended the Jingle session (`session-terminate`), with the
    /// `<reason>` condition if it gave one. Jicofo does this routinely — e.g.
    /// when everyone else leaves and the conference no longer needs a bridge —
    /// so this is a normal end-of-session signal, not an error. The media layer
    /// must tear the peer connection down; ignoring it leaves a zombie
    /// connection that later surfaces as a spurious ICE failure.
    case sessionTerminated(reason: String?)
    /// Remote media sources added/removed (source-add / source-remove).
    case sourceChanged([SourceChange])
    /// The dominant speaker changed to this endpoint id.
    case dominantSpeaker(String)
}

/// Trickle ICE candidates for one media section, parsed from an inbound Jingle
/// `transport-info`.
public struct RemoteCandidates: Equatable, Sendable {
    public var mediaName: String        // "audio" / "video"
    public var candidates: [ICECandidate]
    public init(mediaName: String, candidates: [ICECandidate]) {
        self.mediaName = mediaName; self.candidates = candidates
    }
}
