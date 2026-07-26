import Foundation

/// Turns raw XMPP-over-WebSocket frames into typed ``Stanza`` values.
///
/// Each frame is a single, self-contained stanza (the server enforces a stanza
/// size limit), so parsing is frame-at-a-time: read the frame into an XML node
/// tree, then map the root element to a typed stanza. All XML lives here; no
/// other layer sees the wire format.
public enum StanzaParser {

    public static func parse(_ frame: String) -> Stanza? {
        guard let root = XMLReader.parse(frame) else { return nil }
        return map(root)
    }

    /// Parse many frames, dropping any that fail to parse.
    public static func parse(frames: [String]) -> [Stanza] {
        frames.compactMap { parse($0) }
    }

    static func map(_ root: XMLElementNode) -> Stanza {
        switch root.localName {
        case "open":
            return .streamOpen(id: root.attribute("id"))
        case "features":
            return .streamFeatures(parseFeatures(root))
        case "success":
            return .saslSuccess
        case "failure":
            return .saslFailure(condition: root.children.first?.localName)
        case "presence":
            return .presence(parsePresence(root))
        case "iq":
            return .iq(parseIQ(root))
        case "message":
            return .message(parseMessage(root))
        default:
            return .unknown(name: root.name)
        }
    }

    // MARK: - Stream features

    private static func parseFeatures(_ node: XMLElementNode) -> StreamFeatures {
        let mechanisms = node.firstDescendant("mechanisms")?
            .children("mechanism").map { $0.text } ?? []
        let bindRequired = node.firstDescendant("bind")?.child("required") != nil
        return StreamFeatures(saslMechanisms: mechanisms, bindRequired: bindRequired)
    }

    // MARK: - Presence

    private static func parsePresence(_ node: XMLElementNode) -> Presence {
        // muc#user carries the occupant item + status codes.
        let mucUser = node.children.first {
            $0.localName == "x" && ($0.namespace?.contains("muc#user") ?? false)
        }
        return Presence(
            from: node.attribute("from"),
            to: node.attribute("to"),
            type: node.attribute("type"),
            nick: node.child("nick")?.text,
            statsID: node.child("stats-id")?.text,
            occupantID: node.firstDescendant("occupant-id")?.attribute("id"),
            audioMuted: node.child("audiomuted").map { $0.text == "true" },
            videoMuted: node.child("videomuted").map { $0.text == "true" },
            mucItem: mucUser?.child("item").map {
                MUCItem(role: $0.attribute("role"),
                        affiliation: $0.attribute("affiliation"),
                        jid: $0.attribute("jid"))
            },
            statusCodes: mucUser?.children("status")
                .compactMap { $0.attribute("code").flatMap(Int.init) } ?? []
        )
    }

    // MARK: - Message

    private static func parseMessage(_ node: XMLElementNode) -> Message {
        Message(
            from: node.attribute("from"),
            to: node.attribute("to"),
            type: node.attribute("type"),
            subject: node.child("subject")?.text,
            jsonMessage: node.firstDescendant("json-message")?.text
        )
    }

    // MARK: - IQ

    private static func parseIQ(_ node: XMLElementNode) -> IQ {
        let payload = parseIQPayload(node)
        return IQ(
            type: node.attribute("type") ?? "get",
            id: node.attribute("id"),
            from: node.attribute("from"),
            to: node.attribute("to"),
            payload: payload
        )
    }

    private static func parseIQPayload(_ node: XMLElementNode) -> IQPayload {
        guard let child = node.children.first else { return .empty }
        let ns = child.namespace ?? ""
        switch child.localName {
        case "bind":
            return .bind(jid: child.child("jid")?.text)
        case "query" where ns.contains("disco#info"):
            return .discoInfo(parseDiscoInfo(child))
        case "services" where ns.contains("extdisco"):
            return .externalServices(child.children("service").map(parseService))
        case "conference":
            return .conference(parseConference(child))
        case "jingle":
            return .jingle(parseJingle(child))
        default:
            return .unknown(element: child.name)
        }
    }

    private static func parseDiscoInfo(_ node: XMLElementNode) -> DiscoInfo {
        let identities = node.children("identity").map {
            Identity(category: $0.attribute("category") ?? "",
                     type: $0.attribute("type"), name: $0.attribute("name"))
        }
        let features = node.children("feature").compactMap { $0.attribute("var") }
        return DiscoInfo(identities: identities, features: features)
    }

    private static func parseService(_ node: XMLElementNode) -> ExternalService {
        ExternalService(
            type: node.attribute("type") ?? "",
            host: node.attribute("host") ?? "",
            port: node.attribute("port").flatMap(Int.init),
            transport: node.attribute("transport"),
            username: node.attribute("username"),
            password: node.attribute("password"),
            restricted: node.attribute("restricted").map { $0 == "1" || $0 == "true" },
            expires: node.attribute("expires")
        )
    }

    private static func parseConference(_ node: XMLElementNode) -> ConferenceResponse {
        ConferenceResponse(
            ready: node.attribute("ready") == "true",
            room: node.attribute("room"),
            focusJID: node.attribute("focusjid"),
            properties: node.namedValues("property")
        )
    }

    // MARK: - Jingle

    private static func parseJingle(_ node: XMLElementNode) -> Jingle {
        Jingle(
            action: node.attribute("action") ?? "",
            sid: node.attribute("sid") ?? "",
            initiator: node.attribute("initiator"),
            responder: node.attribute("responder"),
            contents: node.children("content").map(parseContent)
        )
    }

    private static func parseContent(_ node: XMLElementNode) -> JingleContent {
        let description = node.child("description")
        let transport = node.child("transport")
        return JingleContent(
            name: node.attribute("name") ?? "",
            senders: node.attribute("senders"),
            media: description?.attribute("media"),
            payloadTypes: description?.children("payload-type").map(parsePayloadType) ?? [],
            headerExtensions: description?.children("rtp-hdrext").compactMap(parseHeaderExtension) ?? [],
            sources: description?.children("source").map(parseSource) ?? [],
            sourceGroups: description?.children("ssrc-group").map(parseSourceGroup) ?? [],
            transport: transport.map(parseTransport),
            rtcpMux: description?.child("rtcp-mux") != nil
        )
    }

    private static func parsePayloadType(_ node: XMLElementNode) -> PayloadType {
        PayloadType(
            id: node.attribute("id").flatMap(Int.init) ?? -1,
            name: node.attribute("name"),
            clockrate: node.attribute("clockrate").flatMap(Int.init),
            channels: node.attribute("channels").flatMap(Int.init),
            parameters: node.namedValues("parameter"),
            rtcpFeedback: node.children("rtcp-fb").map {
                RTCPFeedback(type: $0.attribute("type") ?? "", subtype: $0.attribute("subtype"))
            }
        )
    }

    private static func parseHeaderExtension(_ node: XMLElementNode) -> RTPHeaderExtension? {
        guard let id = node.attribute("id").flatMap(Int.init),
              let uri = node.attribute("uri") else { return nil }
        return RTPHeaderExtension(id: id, uri: uri)
    }

    private static func parseSource(_ node: XMLElementNode) -> Source {
        Source(
            ssrc: node.attribute("ssrc") ?? "",
            name: node.attribute("name"),
            owner: node.child("ssrc-info")?.attribute("owner"),
            parameters: node.namedValues("parameter")
        )
    }

    private static func parseSourceGroup(_ node: XMLElementNode) -> SourceGroup {
        SourceGroup(
            semantics: node.attribute("semantics") ?? "",
            ssrcs: node.children("source").compactMap { $0.attribute("ssrc") }
        )
    }

    private static func parseTransport(_ node: XMLElementNode) -> JingleTransport {
        JingleTransport(
            ufrag: node.attribute("ufrag"),
            pwd: node.attribute("pwd"),
            fingerprint: node.child("fingerprint").map {
                DTLSFingerprint(hash: $0.attribute("hash") ?? "",
                                setup: $0.attribute("setup"), value: $0.text)
            },
            candidates: node.children("candidate").map(parseCandidate),
            webSocketURL: node.child("web-socket")?.attribute("url")
        )
    }

    private static func parseCandidate(_ node: XMLElementNode) -> ICECandidate {
        ICECandidate(
            foundation: node.attribute("foundation"),
            component: node.attribute("component").flatMap(Int.init),
            proto: node.attribute("protocol"),
            priority: node.attribute("priority").flatMap(Int.init),
            ip: node.attribute("ip"),
            port: node.attribute("port").flatMap(Int.init),
            type: node.attribute("type")
        )
    }
}
