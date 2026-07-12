// MARK: - Jingle session (XEP-0166)

/// A parsed Jingle stanza — covers session-initiate, session-accept,
/// transport-info, and session-terminate actions.
public struct JingleSession: Sendable {
    public enum Action: String, Sendable {
        case sessionInitiate  = "session-initiate"
        case sessionAccept    = "session-accept"
        case sessionTerminate = "session-terminate"
        case transportInfo    = "transport-info"
        case contentAdd       = "content-add"
        case contentRemove    = "content-remove"
        case contentModify    = "content-modify"
        case contentAccept    = "content-accept"
        case contentReject    = "content-reject"
        case transportAccept  = "transport-accept"
        case transportReject  = "transport-reject"
        case transportReplace = "transport-replace"
        case descriptionInfo  = "description-info"
        case sourceAdd        = "source-add"
        case sourceRemove     = "source-remove"
    }

    public let action: Action
    /// Opaque session identifier assigned by the initiator.
    public let sid: String
    public let initiator: String?
    public let responder: String?
    /// BUNDLE group (urn:ietf:rfc:5888) content names, if present.
    public let bundleGroup: [String]
    public let contents: [JingleContent]

    init(element: XMLElement) {
        let actionStr = element.attr("action") ?? ""
        action    = Action(rawValue: actionStr) ?? .sessionInitiate
        sid       = element.attr("sid") ?? ""
        initiator = element.attr("initiator")
        responder = element.attr("responder")

        bundleGroup = element
            .firstChild(localName: "group", namespace: XMPPNS.bundle)?
            .allChildren(localName: "content")
            .compactMap { $0.attr("name") } ?? []

        contents = element.allChildren(localName: "content").map { JingleContent(element: $0) }
    }
}

// MARK: - Jingle content

public struct JingleContent: Sendable {
    public let name: String
    public let creator: String
    public let senders: String?
    public let description: RTPDescription?
    public let transport: ICEUDPTransport?

    init(element: XMLElement) {
        name    = element.attr("name") ?? ""
        creator = element.attr("creator") ?? "initiator"
        senders = element.attr("senders")

        description = element
            .firstChild(localName: "description", namespace: XMPPNS.jingleRTP)
            .map { RTPDescription(element: $0) }

        transport = element
            .firstChild(localName: "transport", namespace: XMPPNS.jingleICE)
            .map { ICEUDPTransport(element: $0) }
    }
}

// MARK: - RTP description (XEP-0167)

public struct RTPDescription: Sendable {
    public let media: String       // "audio" | "video"
    public let payloadTypes: [PayloadType]
    public let headerExtensions: [RTPHeaderExtension]
    public let sources: [RTPSource]
    public let ssrcGroups: [SSRCGroup]
    public let rtcpMux: Bool

    init(element: XMLElement) {
        media = element.attr("media") ?? ""
        payloadTypes = element.allChildren(localName: "payload-type").map { PayloadType(element: $0) }
        headerExtensions = element
            .allChildren(localName: "rtp-hdrext", namespace: XMPPNS.jingleHdrExt)
            .map { RTPHeaderExtension(element: $0) }
        sources = element
            .allChildren(localName: "source", namespace: XMPPNS.jingleSSMA)
            .map { RTPSource(element: $0) }
        ssrcGroups = element
            .allChildren(localName: "ssrc-group", namespace: XMPPNS.jingleSSMA)
            .map { SSRCGroup(element: $0) }
        rtcpMux = element.firstChild(localName: "rtcp-mux") != nil
    }
}

public struct PayloadType: Sendable {
    public let id: Int
    public let name: String
    public let clockrate: Int
    public let channels: Int
    public let parameters: [String: String]
    public let rtcpFeedbacks: [RTCPFeedback]

    init(element: XMLElement) {
        id        = element.attr("id").flatMap(Int.init) ?? 0
        name      = element.attr("name") ?? ""
        clockrate = element.attr("clockrate").flatMap(Int.init) ?? 0
        channels  = element.attr("channels").flatMap(Int.init) ?? 1
        parameters = Dictionary(
            uniqueKeysWithValues: element.allChildren(localName: "parameter")
                .compactMap { el -> (String, String)? in
                    guard let k = el.attr("name"), let v = el.attr("value") else { return nil }
                    return (k, v)
                }
        )
        rtcpFeedbacks = element
            .allChildren(localName: "rtcp-fb", namespace: XMPPNS.jingleRtcpFB)
            .map { RTCPFeedback(element: $0) }
    }
}

public struct RTCPFeedback: Sendable {
    public let type: String
    public let subtype: String?

    init(element: XMLElement) {
        type    = element.attr("type") ?? ""
        subtype = element.attr("subtype")
    }
}

public struct RTPHeaderExtension: Sendable {
    public let id: Int
    public let uri: String

    init(element: XMLElement) {
        id  = element.attr("id").flatMap(Int.init) ?? 0
        uri = element.attr("uri") ?? ""
    }
}

public struct RTPSource: Sendable {
    public let ssrc: UInt32
    public let parameters: [String: String]

    init(element: XMLElement) {
        ssrc = element.attr("ssrc").flatMap { UInt32($0) } ?? 0
        parameters = Dictionary(
            uniqueKeysWithValues: element.allChildren(localName: "parameter")
                .compactMap { el -> (String, String)? in
                    guard let k = el.attr("name"), let v = el.attr("value") else { return nil }
                    return (k, v)
                }
        )
    }
}

public struct SSRCGroup: Sendable {
    public let semantics: String
    public let ssrcs: [UInt32]

    init(element: XMLElement) {
        semantics = element.attr("semantics") ?? ""
        ssrcs = element.allChildren(localName: "source")
            .compactMap { $0.attr("ssrc").flatMap { UInt32($0) } }
    }
}

// MARK: - ICE-UDP transport (XEP-0176)

public struct ICEUDPTransport: Sendable {
    public let ufrag: String?
    public let pwd: String?
    public let fingerprint: DTLSFingerprint?
    public let candidates: [ICECandidate]

    init(element: XMLElement) {
        ufrag = element.attr("ufrag")
        pwd   = element.attr("pwd")
        fingerprint = element
            .firstChild(localName: "fingerprint", namespace: XMPPNS.jingleDTLS)
            .map { DTLSFingerprint(element: $0) }
        candidates = element.allChildren(localName: "candidate").map { ICECandidate(element: $0) }
    }
}

public struct DTLSFingerprint: Sendable {
    public let hash: String
    public let setup: String
    public let value: String

    init(element: XMLElement) {
        hash  = element.attr("hash") ?? ""
        setup = element.attr("setup") ?? ""
        value = element.trimmedText
    }
}

public struct ICECandidate: Sendable {
    public let component: Int
    public let foundation: String
    public let generation: Int
    public let id: String?
    public let ip: String
    public let network: Int
    public let port: Int
    public let priority: UInt32
    public let `protocol`: String
    public let type: String
    public let relAddr: String?
    public let relPort: Int?

    init(element: XMLElement) {
        component  = element.attr("component").flatMap(Int.init) ?? 1
        foundation = element.attr("foundation") ?? ""
        generation = element.attr("generation").flatMap(Int.init) ?? 0
        id         = element.attr("id")
        ip         = element.attr("ip") ?? ""
        network    = element.attr("network").flatMap(Int.init) ?? 0
        port       = element.attr("port").flatMap(Int.init) ?? 0
        priority   = element.attr("priority").flatMap { UInt32($0) } ?? 0
        `protocol` = element.attr("protocol") ?? "udp"
        type       = element.attr("type") ?? "host"
        relAddr    = element.attr("rel-addr")
        relPort    = element.attr("rel-port").flatMap(Int.init)
    }
}
