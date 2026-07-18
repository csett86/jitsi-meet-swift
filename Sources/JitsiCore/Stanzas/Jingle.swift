import Foundation

/// A Jingle action (XEP-0166). `jitsi.luki.org` was confirmed to use classic
/// Jingle for `session-initiate` (not Colibri2), so this is the wire shape the
/// signaling layer normalizes into a `ParsedSessionDescription`.
public struct Jingle: Equatable, Sendable {
    public var action: String       // session-initiate / session-accept / source-add / ...
    public var sid: String
    public var initiator: String?
    public var responder: String?
    public var contents: [JingleContent]
    public init(action: String, sid: String, initiator: String?, responder: String?,
                contents: [JingleContent]) {
        self.action = action; self.sid = sid; self.initiator = initiator
        self.responder = responder; self.contents = contents
    }
}

public struct JingleContent: Equatable, Sendable {
    public var name: String         // "audio" / "video"
    public var senders: String?     // both / initiator / responder / none
    public var media: String?       // audio / video
    public var payloadTypes: [PayloadType]
    public var headerExtensions: [RTPHeaderExtension]
    public var sources: [Source]
    public var sourceGroups: [SourceGroup]
    public var transport: JingleTransport?
    public var rtcpMux: Bool
    public init(name: String, senders: String?, media: String?,
                payloadTypes: [PayloadType], headerExtensions: [RTPHeaderExtension],
                sources: [Source], sourceGroups: [SourceGroup],
                transport: JingleTransport?, rtcpMux: Bool) {
        self.name = name; self.senders = senders; self.media = media
        self.payloadTypes = payloadTypes; self.headerExtensions = headerExtensions
        self.sources = sources; self.sourceGroups = sourceGroups
        self.transport = transport; self.rtcpMux = rtcpMux
    }
}

public struct PayloadType: Equatable, Sendable {
    public var id: Int
    public var name: String?
    public var clockrate: Int?
    public var channels: Int?
    public var parameters: [String: String]
    public var rtcpFeedback: [RTCPFeedback]
    public init(id: Int, name: String?, clockrate: Int?, channels: Int?,
                parameters: [String: String], rtcpFeedback: [RTCPFeedback]) {
        self.id = id; self.name = name; self.clockrate = clockrate; self.channels = channels
        self.parameters = parameters; self.rtcpFeedback = rtcpFeedback
    }
}

public struct RTCPFeedback: Equatable, Sendable {
    public var type: String
    public var subtype: String?
    public init(type: String, subtype: String?) { self.type = type; self.subtype = subtype }
}

public struct RTPHeaderExtension: Equatable, Sendable {
    public var id: Int
    public var uri: String
    public init(id: Int, uri: String) { self.id = id; self.uri = uri }
}

public struct Source: Equatable, Sendable {
    public var ssrc: String
    public var name: String?
    public var owner: String?
    public var parameters: [String: String]   // e.g. msid
    public init(ssrc: String, name: String?, owner: String?, parameters: [String: String]) {
        self.ssrc = ssrc; self.name = name; self.owner = owner; self.parameters = parameters
    }
}

public struct SourceGroup: Equatable, Sendable {
    public var semantics: String        // e.g. FID, SIM
    public var ssrcs: [String]
    public init(semantics: String, ssrcs: [String]) { self.semantics = semantics; self.ssrcs = ssrcs }
}

public struct JingleTransport: Equatable, Sendable {
    public var ufrag: String?
    public var pwd: String?
    public var fingerprint: DTLSFingerprint?
    public var candidates: [ICECandidate]
    /// The colibri bridge WebSocket URL, when the JVB offers one.
    public var webSocketURL: String?
    public init(ufrag: String?, pwd: String?, fingerprint: DTLSFingerprint?,
                candidates: [ICECandidate], webSocketURL: String?) {
        self.ufrag = ufrag; self.pwd = pwd; self.fingerprint = fingerprint
        self.candidates = candidates; self.webSocketURL = webSocketURL
    }
}

public struct DTLSFingerprint: Equatable, Sendable {
    public var hash: String        // sha-256
    public var setup: String?      // actpass / active / passive
    public var value: String
    public init(hash: String, setup: String?, value: String) {
        self.hash = hash; self.setup = setup; self.value = value
    }
}

public struct ICECandidate: Equatable, Sendable {
    public var foundation: String?
    public var component: Int?
    public var proto: String?      // udp / tcp
    public var priority: Int?
    public var ip: String?
    public var port: Int?
    public var type: String?       // host / srflx / relay
    public init(foundation: String?, component: Int?, proto: String?, priority: Int?,
                ip: String?, port: Int?, type: String?) {
        self.foundation = foundation; self.component = component; self.proto = proto
        self.priority = priority; self.ip = ip; self.port = port; self.type = type
    }
}
