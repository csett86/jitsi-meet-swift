// MARK: - Disco#info result (XEP-0030)

public struct DiscoInfoResult: Sendable {
    public struct Identity: Sendable {
        public let category: String
        public let type: String
        public let name: String?

        init(element: XMLElement) {
            category = element.attr("category") ?? ""
            type     = element.attr("type") ?? ""
            name     = element.attr("name")
        }
    }

    public let node: String?
    public let identities: [Identity]
    /// Feature variable strings (e.g. `"http://jabber.org/protocol/muc"`).
    public let features: [String]

    public func supports(_ featureVar: String) -> Bool { features.contains(featureVar) }

    init(element: XMLElement) {
        node       = element.attr("node")
        identities = element.allChildren(localName: "identity").map { Identity(element: $0) }
        features   = element.allChildren(localName: "feature").compactMap { $0.attr("var") }
    }
}

// MARK: - Disco#items result

public struct DiscoItem: Sendable {
    public let jid: String
    public let node: String?
    public let name: String?

    init(element: XMLElement) {
        jid  = element.attr("jid") ?? ""
        node = element.attr("node")
        name = element.attr("name")
    }
}

// MARK: - External service (XEP-0215)

public struct ExternalService: Sendable {
    public enum ServiceType: String, Sendable {
        case stun  = "stun"
        case turn  = "turn"
        case turns = "turns"
        case other
    }

    public let type: ServiceType
    public let host: String
    public let port: Int
    public let transport: String?
    public let username: String?
    public let password: String?

    init(element: XMLElement) {
        let typeStr = element.attr("type") ?? ""
        type      = ServiceType(rawValue: typeStr) ?? .other
        host      = element.attr("host") ?? ""
        port      = element.attr("port").flatMap(Int.init) ?? 3478
        transport = element.attr("transport")
        username  = element.attr("username")
        password  = element.attr("password")
    }
}
