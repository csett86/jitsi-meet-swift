// MARK: - Presence stanza

public struct PresenceStanza: Sendable {
    public enum PresenceType: String, Sendable {
        case available    = "available"
        case unavailable  = "unavailable"
        case subscribe    = "subscribe"
        case subscribed   = "subscribed"
        case unsubscribe  = "unsubscribe"
        case unsubscribed = "unsubscribed"
        case error        = "error"
    }

    public let id: String?
    public let from: String?
    public let to: String?
    public let type: PresenceType
    public let mucUser: MUCUserInfo?
    public let nick: String?
    public let statsID: String?
    public let videoType: String?
    public let region: String?
    public let features: [String]

    /// Raw XML element — retained so callers can inspect Jitsi-specific extensions
    /// not yet modelled here.
    public let rawElement: XMLElementSnapshot

    init(element: XMLElement) {
        id = element.attr("id")
        from = element.attr("from")
        to = element.attr("to")
        let typeStr = element.attr("type") ?? "available"
        type = PresenceType(rawValue: typeStr) ?? .available

        mucUser = element.firstChild(localName: "x", namespace: XMPPNS.mucUser)
            .map { MUCUserInfo(element: $0) }

        nick = element.firstChild(localName: "nick", namespace: XMPPNS.nick)?.trimmedText
        statsID = element.firstChild(localName: "stats-id", namespace: XMPPNS.jitsiMeet)?.trimmedText
        videoType = element.firstChild(localName: "videotype", namespace: XMPPNS.jitsiVideo)?.trimmedText
        region = element.firstChild(localName: "region", namespace: XMPPNS.jitsiMeet)?.trimmedText

        features = element.firstChild(localName: "features", namespace: XMPPNS.jitsiMeet)?
            .allChildren(localName: "feature")
            .compactMap { $0.attr("var") } ?? []

        rawElement = XMLElementSnapshot(element)
    }
}

// MARK: - MUC user info (XEP-0045 muc#user x element)

public struct MUCUserInfo: Sendable {
    public struct Item: Sendable {
        public let affiliation: String?
        public let role: String?
        public let jid: String?
        public let nick: String?
    }

    public let items: [Item]
    public let statusCodes: [Int]
    public let isSelfPresence: Bool   // status code 110
    public let isPublicRoom: Bool     // status code 100

    init(element: XMLElement) {
        items = element.allChildren(localName: "item").map { el in
            Item(
                affiliation: el.attr("affiliation"),
                role: el.attr("role"),
                jid: el.attr("jid"),
                nick: el.attr("nick")
            )
        }
        statusCodes = element.allChildren(localName: "status")
            .compactMap { $0.attr("code").flatMap(Int.init) }
        isSelfPresence = statusCodes.contains(110)
        isPublicRoom = statusCodes.contains(100)
    }
}

// MARK: - XMLElementSnapshot (opaque public carrier for raw XML)

/// An opaque, Sendable snapshot of a parsed XML element exposed in public APIs.
/// Callers can inspect it but the type stays an implementation detail.
public struct XMLElementSnapshot: Sendable {
    let localName: String
    let namespaceURI: String?
    let attributes: [String: String]
    let children: [XMLElementSnapshot]
    let text: String

    init(_ el: XMLElement) {
        localName = el.localName
        namespaceURI = el.namespaceURI
        attributes = el.attributes
        children = el.children.map { XMLElementSnapshot($0) }
        text = el.text
    }

    public func attr(_ name: String) -> String? { attributes[name] }
}
