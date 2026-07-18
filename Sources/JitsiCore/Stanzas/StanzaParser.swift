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
        var presence = Presence(
            from: node.attribute("from"),
            to: node.attribute("to"),
            type: node.attribute("type"),
            nick: node.child("nick")?.text,
            statsID: node.child("stats-id")?.text
        )
        if let occupant = node.firstDescendant("occupant-id") {
            presence.occupantID = occupant.attribute("id")
        }
        if let audio = node.child("audiomuted")?.text { presence.audioMuted = (audio == "true") }
        if let video = node.child("videomuted")?.text { presence.videoMuted = (video == "true") }

        // muc#user carries the occupant item + status codes.
        if let mucUser = node.children.first(where: {
            $0.localName == "x" && ($0.namespace?.contains("muc#user") ?? false)
        }) {
            if let item = mucUser.child("item") {
                presence.mucItem = MUCItem(
                    role: item.attribute("role"),
                    affiliation: item.attribute("affiliation"),
                    jid: item.attribute("jid")
                )
            }
            presence.statusCodes = mucUser.children("status").compactMap {
                $0.attribute("code").flatMap(Int.init)
            }
        }
        return presence
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
        var props: [String: String] = [:]
        for property in node.children("property") {
            if let name = property.attribute("name"), let value = property.attribute("value") {
                props[name] = value
            }
        }
        return ConferenceResponse(
            ready: node.attribute("ready") == "true",
            room: node.attribute("room"),
            focusJID: node.attribute("focusjid"),
            properties: props
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
        var params: [String: String] = [:]
        for p in node.children("parameter") {
            if let name = p.attribute("name") { params[name] = p.attribute("value") ?? "" }
        }
        let feedback = node.children("rtcp-fb").map {
            RTCPFeedback(type: $0.attribute("type") ?? "", subtype: $0.attribute("subtype"))
        }
        return PayloadType(
            id: node.attribute("id").flatMap(Int.init) ?? -1,
            name: node.attribute("name"),
            clockrate: node.attribute("clockrate").flatMap(Int.init),
            channels: node.attribute("channels").flatMap(Int.init),
            parameters: params,
            rtcpFeedback: feedback
        )
    }

    private static func parseHeaderExtension(_ node: XMLElementNode) -> RTPHeaderExtension? {
        guard let id = node.attribute("id").flatMap(Int.init),
              let uri = node.attribute("uri") else { return nil }
        return RTPHeaderExtension(id: id, uri: uri)
    }

    private static func parseSource(_ node: XMLElementNode) -> Source {
        var params: [String: String] = [:]
        for p in node.children("parameter") {
            if let name = p.attribute("name") { params[name] = p.attribute("value") ?? "" }
        }
        return Source(
            ssrc: node.attribute("ssrc") ?? "",
            name: node.attribute("name"),
            owner: node.child("ssrc-info")?.attribute("owner"),
            parameters: params
        )
    }

    private static func parseSourceGroup(_ node: XMLElementNode) -> SourceGroup {
        SourceGroup(
            semantics: node.attribute("semantics") ?? "",
            ssrcs: node.children("source").compactMap { $0.attribute("ssrc") }
        )
    }

    private static func parseTransport(_ node: XMLElementNode) -> JingleTransport {
        var fingerprint: DTLSFingerprint?
        if let fp = node.child("fingerprint") {
            fingerprint = DTLSFingerprint(
                hash: fp.attribute("hash") ?? "",
                setup: fp.attribute("setup"),
                value: fp.text
            )
        }
        let candidates = node.children("candidate").map { c in
            ICECandidate(
                foundation: c.attribute("foundation"),
                component: c.attribute("component").flatMap(Int.init),
                proto: c.attribute("protocol"),
                priority: c.attribute("priority").flatMap(Int.init),
                ip: c.attribute("ip"),
                port: c.attribute("port").flatMap(Int.init),
                type: c.attribute("type")
            )
        }
        return JingleTransport(
            ufrag: node.attribute("ufrag"),
            pwd: node.attribute("pwd"),
            fingerprint: fingerprint,
            candidates: candidates,
            webSocketURL: node.child("web-socket")?.attribute("url")
        )
    }
}
