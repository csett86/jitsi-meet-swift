// MARK: - IQ stanza

public struct IQStanza: Sendable {
    public enum IQType: String, Sendable {
        case get    = "get"
        case set    = "set"
        case result = "result"
        case error  = "error"
    }

    public let id: String?
    public let from: String?
    public let to: String?
    public let type: IQType
    public let payload: IQPayload

    init(element: XMLElement) {
        id   = element.attr("id")
        from = element.attr("from")
        to   = element.attr("to")
        let typeStr = element.attr("type") ?? "get"
        type = IQType(rawValue: typeStr) ?? .get
        payload = IQPayload.parse(from: element)
    }
}

// MARK: - IQ payload

public enum IQPayload: Sendable {
    /// Resource bind result — holds the full JID assigned by the server.
    case bind(fullJID: String)
    /// XEP-0030 disco#info result.
    case discoInfo(DiscoInfoResult)
    /// XEP-0030 disco#items result.
    case discoItems([DiscoItem])
    /// XEP-0166 Jingle session management.
    case jingle(JingleSession)
    /// XEP-0215 external service discovery.
    case externalServices([ExternalService])
    /// IQ error payload.
    case error(IQError)
    /// Result or get/set with no recognised child.
    case empty
    /// Unrecognised child element.
    case unknown(elementName: String, namespace: String?)

    static func parse(from element: XMLElement) -> IQPayload {
        guard let child = element.children.first else { return .empty }

        switch (child.localName, child.namespaceURI) {
        case ("bind", XMPPNS.bind):
            let jid = child.firstChild(localName: "jid")?.trimmedText ?? ""
            return .bind(fullJID: jid)

        case ("query", XMPPNS.discoInfo):
            return .discoInfo(DiscoInfoResult(element: child))

        case ("query", XMPPNS.discoItems):
            let items = child.allChildren(localName: "item").map { DiscoItem(element: $0) }
            return .discoItems(items)

        case ("jingle", XMPPNS.jingle):
            return .jingle(JingleSession(element: child))

        case ("services", XMPPNS.extdisco):
            let services = child.allChildren(localName: "service").map { ExternalService(element: $0) }
            return .externalServices(services)

        case ("error", _):
            return .error(IQError(element: child))

        default:
            return .unknown(elementName: child.localName, namespace: child.namespaceURI)
        }
    }
}

// MARK: - IQ error

public struct IQError: Sendable {
    public let code: Int?
    public let type: String?
    public let condition: String?

    init(element: XMLElement) {
        code = element.attr("code").flatMap(Int.init)
        type = element.attr("type")
        condition = element.children.first?.localName
    }
}
