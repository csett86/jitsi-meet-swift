import Foundation

/// The remote (bridge) side of the media session as it evolves during a call.
///
/// The JVB offers exactly two m-sections — our own audio and video — and then
/// announces every *other* participant's media out-of-band with Jingle
/// `source-add` / `source-remove`, never a new offer. Unified Plan, however,
/// needs one m-section per received track. So the client keeps this model of the
/// remote description, synthesizes the extra receive-only sections itself, and
/// renegotiates locally (set the rebuilt offer, create a new answer). Nothing is
/// sent back to Jicofo for these — the JVB's own signaling already told it what
/// it is sending us.
///
/// Two invariants make renegotiation safe:
/// * **mids are never renumbered or reused.** A track that goes away leaves an
///   `a=inactive` tombstone section behind, because Unified Plan forbids
///   reordering m-lines between offers.
/// * **the version in `o=` increases on every change**, so WebRTC sees each
///   rebuild as a new offer rather than a repeat.
///
/// Pure Swift and fully unit-tested on Linux; the Apple layer only feeds the
/// resulting SDP string to `RTCPeerConnection`.
public struct RemoteSDPSession: Equatable, Sendable {

    /// One receive-only section, bound to a remote track for the session's life.
    public struct Section: Equatable, Sendable {
        public var mid: String
        public var kind: String
        /// ``RemoteTrack/id`` this section was allocated for.
        public var trackID: String
        public var endpointID: String
        /// The current track, or nil once its sources were removed.
        public var track: RemoteTrack?
    }

    private let offer: ParsedSessionDescription
    public private(set) var sections: [Section] = []
    /// `o=` version. Starts at 2 (matching the initial offer) and increments per
    /// change, so every rebuild is a distinct offer to WebRTC.
    public private(set) var version = 2
    private var midCounter = 0

    public init(offer: ParsedSessionDescription) {
        self.offer = offer
    }

    /// Reconcile the receive sections with the current set of remote tracks.
    /// Returns `true` when the SDP changed and the peer connection must
    /// renegotiate.
    @discardableResult
    public mutating func sync(tracks: [RemoteTrack]) -> Bool {
        var changed = false
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Existing sections: update or tombstone.
        for index in sections.indices {
            let current = byID[sections[index].trackID]
            if sections[index].track != current {
                sections[index].track = current
                changed = true
            }
        }

        // New tracks get a fresh section — appended, never inserted, so earlier
        // mids keep their m-line index.
        let known = Set(sections.map(\.trackID))
        for track in tracks where !known.contains(track.id) {
            midCounter += 1
            sections.append(Section(mid: "\(track.kind)-r\(midCounter)", kind: track.kind,
                                    trackID: track.id, endpointID: track.endpointID,
                                    track: track))
            changed = true
        }

        if changed { version += 1 }
        return changed
    }

    /// The full remote offer SDP: the bridge's two sections plus one per remote
    /// track.
    public func sdp(sessionID: String = "0") -> String {
        SDPBuilder.offer(from: offer, sessionID: sessionID, version: version,
                         receive: sections.map {
                             SDPBuilder.ReceiveMedia(mid: $0.mid, kind: $0.kind, track: $0.track)
                         })
    }

    /// Which participant a received track belongs to, by the mid WebRTC reports
    /// on its transceiver. This is the mapping the UI needs to put a video in the
    /// right tile, and it is exact — no msid string-matching involved.
    public func endpoint(forMid mid: String) -> String? {
        sections.first { $0.mid == mid && $0.track != nil }?.endpointID
    }

    /// The kind (audio/video) of a receive section, by mid.
    public func kind(forMid mid: String) -> String? {
        sections.first { $0.mid == mid }?.kind
    }

    /// The Jitsi source name behind a mid — the identifier receiver constraints
    /// are keyed by.
    public func sourceName(forMid mid: String) -> String? {
        sections.first { $0.mid == mid }?.track?.name
    }
}
