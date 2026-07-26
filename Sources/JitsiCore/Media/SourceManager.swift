import Foundation

/// A media source (SSRC) owned by a conference endpoint.
public struct EndpointSource: Equatable, Sendable {
    public var ssrc: String
    /// The full owner value from `<ssrc-info owner=…>` (a MUC JID, or `"jvb"`).
    public var owner: String
    /// The endpoint id — the resource of the owner JID, or `"jvb"` for the bridge.
    public var endpointID: String
    public var media: String        // audio / video
    public var name: String?
    public var msid: String?

    public init(ssrc: String, owner: String, endpointID: String, media: String,
                name: String? = nil, msid: String? = nil) {
        self.ssrc = ssrc; self.owner = owner; self.endpointID = endpointID
        self.media = media; self.name = name; self.msid = msid
    }

    /// The JVB's own mixed sources are not a participant's camera/mic.
    public var isBridge: Bool { endpointID == "jvb" }
}

public enum SourceChange: Equatable, Sendable {
    case added(EndpointSource)
    case removed(EndpointSource)
}

/// Maintains the SSRC ↔ participant mapping from Jingle `source-add` /
/// `source-remove` (and the initial `session-initiate`). Pure value state, so
/// the multi-party wiring is fully unit-tested offline.
///
/// Note: a real participant's sources only appear once they publish media; the
/// committed multi-party fixture is synthesized from the observed Jitsi source
/// format because headless clients can't publish media (see docs/findings.md).
public struct SourceManager: Equatable, Sendable {
    /// SSRC → source.
    public private(set) var sources: [String: EndpointSource] = [:]
    /// `<ssrc-group>`s seen so far (SIM / FID). Several SSRCs in one group are
    /// one *track* — simulcast layers or an RTX stream — and must end up in a
    /// single SDP m-section, so they are kept alongside the flat SSRC map.
    public private(set) var groups: [SourceGroup] = []

    public init() {}

    public func endpoint(forSSRC ssrc: String) -> String? {
        sources[ssrc]?.endpointID
    }

    public func ssrcs(for endpoint: String) -> [String] {
        sources.values.filter { $0.endpointID == endpoint }.map(\.ssrc).sorted()
    }

    /// All participant endpoints that own at least one source (excluding the bridge).
    public var participantEndpoints: Set<String> {
        Set(sources.values.filter { !$0.isBridge }.map(\.endpointID))
    }

    /// Apply a Jingle action, returning the resulting source changes.
    /// `source-remove` removes; any other action (session-initiate/-accept,
    /// `source-add`) adds.
    @discardableResult
    public mutating func apply(_ jingle: Jingle) -> [SourceChange] {
        let removing = jingle.action == "source-remove"
        var changes: [SourceChange] = []
        for content in jingle.contents {
            let media = content.media ?? content.name
            if removing {
                let gone = Set(content.sources.map(\.ssrc))
                groups.removeAll { !$0.ssrcs.filter(gone.contains).isEmpty }
            } else {
                for group in content.sourceGroups where !groups.contains(group) {
                    groups.append(group)
                }
            }
            for source in content.sources {
                let owner = source.owner ?? ""
                let endpointID = JID(owner)?.resource ?? (owner.isEmpty ? "unknown" : owner)
                let endpointSource = EndpointSource(
                    ssrc: source.ssrc, owner: owner, endpointID: endpointID,
                    media: media, name: source.name, msid: source.parameters["msid"])
                if removing {
                    if sources.removeValue(forKey: source.ssrc) != nil {
                        changes.append(.removed(endpointSource))
                    }
                } else if sources[source.ssrc] == nil {
                    sources[source.ssrc] = endpointSource
                    changes.append(.added(endpointSource))
                }
            }
        }
        return changes
    }

    /// Drop every source owned by an endpoint (e.g. when they leave the MUC).
    @discardableResult
    public mutating func removeEndpoint(_ endpoint: String) -> [SourceChange] {
        let gone = sources.values.filter { $0.endpointID == endpoint }
        for source in gone { sources.removeValue(forKey: source.ssrc) }
        let ssrcs = Set(gone.map(\.ssrc))
        groups.removeAll { !$0.ssrcs.filter(ssrcs.contains).isEmpty }
        return gone.map(SourceChange.removed)
    }

    /// The remote participants' media as *tracks* — the shape the receive path
    /// needs, since one track can be carried by several SSRCs (simulcast/RTX)
    /// but must become exactly one SDP m-section.
    ///
    /// The bridge's own `jvb-a0`/`jvb-v0` placeholders are excluded: they are not
    /// a participant's camera or microphone and never carry media.
    public var tracks: [RemoteTrack] {
        // Union the SSRCs that a source-group ties together, so simulcast layers
        // and an RTX stream collapse into their primary's track.
        var primaryOf: [String: String] = [:]
        for group in groups {
            guard let primary = group.ssrcs.first else { continue }
            let root = primaryOf[primary] ?? primary
            for ssrc in group.ssrcs { primaryOf[ssrc] = root }
        }

        var byPrimary: [String: RemoteTrack] = [:]
        // Deterministic order (dictionary iteration is not): SSRCs numerically.
        for source in sources.values.filter({ !$0.isBridge }).sorted(by: Self.bySSRC) {
            let primary = primaryOf[source.ssrc] ?? source.ssrc
            if var track = byPrimary[primary] {
                track.ssrcs.append(source.ssrc)
                track.msid = track.msid ?? source.msid
                byPrimary[primary] = track
            } else {
                byPrimary[primary] = RemoteTrack(
                    endpointID: source.endpointID, kind: source.media,
                    name: source.name, primarySSRC: primary,
                    ssrcs: [source.ssrc], msid: source.msid)
            }
        }
        // A group's primary can arrive after a secondary; put it back in front.
        return byPrimary.values.map { track in
            var track = track
            track.ssrcs = [track.primarySSRC] + track.ssrcs.filter { $0 != track.primarySSRC }
            return track
        }.sorted { ($0.endpointID, $0.kind, $0.primarySSRC) < ($1.endpointID, $1.kind, $1.primarySSRC) }
    }

    private static func bySSRC(_ lhs: EndpointSource, _ rhs: EndpointSource) -> Bool {
        (UInt32(lhs.ssrc) ?? 0, lhs.ssrc) < (UInt32(rhs.ssrc) ?? 0, rhs.ssrc)
    }
}

/// One remote *track*: every SSRC that carries a single participant's camera or
/// microphone, plus who owns it. Derived from ``SourceManager``; consumed by the
/// receive-path SDP builder, which turns each track into one m-section.
public struct RemoteTrack: Equatable, Sendable {
    public var endpointID: String
    public var kind: String              // audio / video
    /// Jitsi source name (`<endpoint>-v0`), when the deployment signals one.
    public var name: String?
    /// The SSRC the other SSRCs (simulcast layers, RTX) hang off.
    public var primarySSRC: String
    /// All SSRCs of the track, primary first.
    public var ssrcs: [String]
    public var msid: String?

    public init(endpointID: String, kind: String, name: String?, primarySSRC: String,
                ssrcs: [String], msid: String?) {
        self.endpointID = endpointID; self.kind = kind; self.name = name
        self.primarySSRC = primarySSRC; self.ssrcs = ssrcs; self.msid = msid
    }

    /// Stable identity across `source-add`/`source-remove`, so a track keeps its
    /// m-section (and therefore its mid) for the lifetime of the session.
    public var id: String { "\(endpointID)/\(kind)/\(name ?? primarySSRC)" }
}
