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
        return gone.map(SourceChange.removed)
    }
}
