// MARK: - XMPP Namespaces

enum XMPPNS {
    static let framing     = "urn:ietf:params:xml:ns:xmpp-framing"
    static let client      = "jabber:client"
    static let sasl        = "urn:ietf:params:xml:ns:xmpp-sasl"
    static let bind        = "urn:ietf:params:xml:ns:xmpp-bind"
    static let session     = "urn:ietf:params:xml:ns:xmpp-session"
    static let streams     = "http://etherx.jabber.org/streams"
    static let muc         = "http://jabber.org/protocol/muc"
    static let mucUser     = "http://jabber.org/protocol/muc#user"
    static let discoInfo   = "http://jabber.org/protocol/disco#info"
    static let discoItems  = "http://jabber.org/protocol/disco#items"
    static let jingle      = "urn:xmpp:jingle:1"
    static let jingleRTP   = "urn:xmpp:jingle:apps:rtp:1"
    static let jingleICE   = "urn:xmpp:jingle:transports:ice-udp:1"
    static let jingleDTLS  = "urn:xmpp:jingle:apps:dtls:0"
    static let jingleSSMA  = "urn:xmpp:jingle:apps:rtp:ssma:0"
    static let jingleRtcpFB = "urn:xmpp:jingle:apps:rtp:rtcp-fb:0"
    static let jingleHdrExt = "urn:xmpp:jingle:apps:rtp:rtp-hdrext:0"
    static let jingleGrouping = "urn:xmpp:jingle:apps:grouping:0"
    static let extdisco    = "urn:xmpp:extdisco:2"
    static let nick        = "http://jabber.org/protocol/nick"
    static let jitsiMeet   = "http://jitsi.org/jitmeet"
    static let jitsiVideo  = "http://jitsi.org/jitmeet/video"
    static let bundle      = "urn:ietf:rfc:5888"
}

// MARK: - Top-level received stanza

/// Every WebSocket frame received from the server maps to one of these cases.
public enum ReceivedStanza: Sendable {
    case streamOpen(StreamOpen)
    case streamClose
    case streamFeatures(StreamFeatures)
    case saslSuccess
    case saslFailure(condition: String)
    case iq(IQStanza)
    case presence(PresenceStanza)
    case message(MessageStanza)
    case unknown(elementName: String, namespace: String?)
}

// MARK: - Stream open

public struct StreamOpen: Sendable {
    public let from: String?
    public let id: String?
    public let version: String?
}

// MARK: - Stream features

public struct StreamFeatures: Sendable {
    public let mechanisms: [String]
    public let bindRequired: Bool
    public let sessionRequired: Bool

    public var supportsAnonymous: Bool { mechanisms.contains("ANONYMOUS") }
}

// MARK: - Parser

/// Parses raw XML strings (one per WebSocket frame) into ``ReceivedStanza`` values.
///
/// Each XMPP-over-WebSocket frame is a complete XML document (RFC 7395 §4),
/// so `Foundation.XMLParser` is invoked once per frame — not in streaming mode.
public enum StanzaParser {
    public static func parse(_ xmlString: String) -> ReceivedStanza {
        guard let root = try? parseXMLElement(xmlString) else {
            return .unknown(elementName: "(parse error)", namespace: nil)
        }
        return dispatch(root: root)
    }

    // MARK: - Dispatch

    private static func dispatch(root: XMLElement) -> ReceivedStanza {
        switch root.localName {
        case "open":
            return .streamOpen(StreamOpen(
                from: root.attr("from"),
                id: root.attr("id"),
                version: root.attr("version")
            ))

        case "close":
            return .streamClose

        case "features":
            return .streamFeatures(parseFeatures(root))

        case "success" where root.namespaceURI == XMPPNS.sasl:
            return .saslSuccess

        case "failure" where root.namespaceURI == XMPPNS.sasl:
            let condition = root.children.first?.localName ?? "unknown"
            return .saslFailure(condition: condition)

        case "iq":
            return .iq(parseIQ(root))

        case "presence":
            return .presence(parsePresence(root))

        case "message":
            return .message(parseMessage(root))

        default:
            return .unknown(elementName: root.localName, namespace: root.namespaceURI)
        }
    }

    // MARK: - Stream features

    private static func parseFeatures(_ el: XMLElement) -> StreamFeatures {
        let mechanisms: [String] = el
            .firstChild(localName: "mechanisms", namespace: XMPPNS.sasl)?
            .allChildren(localName: "mechanism")
            .map(\.trimmedText) ?? []
        let bindRequired = el.firstChild(localName: "bind", namespace: XMPPNS.bind) != nil
        let sessionRequired = el.firstChild(localName: "session", namespace: XMPPNS.session) != nil
        return StreamFeatures(
            mechanisms: mechanisms,
            bindRequired: bindRequired,
            sessionRequired: sessionRequired
        )
    }

    // MARK: - IQ parsing (delegated to IQ.swift)

    internal static func parseIQ(_ el: XMLElement) -> IQStanza {
        IQStanza(element: el)
    }

    // MARK: - Presence parsing (delegated to Presence.swift)

    internal static func parsePresence(_ el: XMLElement) -> PresenceStanza {
        PresenceStanza(element: el)
    }

    // MARK: - Message parsing (delegated to Message.swift)

    internal static func parseMessage(_ el: XMLElement) -> MessageStanza {
        MessageStanza(element: el)
    }
}
