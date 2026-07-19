import Foundation

/// A top-level XMPP stanza, parsed into a typed value. `StanzaParser` produces
/// these from raw WebSocket frames so higher layers never touch XML.
public enum Stanza: Equatable, Sendable {
    case streamOpen(id: String?)
    case streamFeatures(StreamFeatures)
    case saslSuccess
    case saslFailure(condition: String?)
    case presence(Presence)
    case iq(IQ)
    case message(Message)
    /// A stanza we recognized structurally but do not model yet.
    case unknown(name: String)
}

/// The `<stream:features>` advertised after `<open>`: which SASL mechanisms the
/// server offers and whether resource binding is required.
public struct StreamFeatures: Equatable, Sendable {
    public var saslMechanisms: [String]
    public var bindRequired: Bool
    public init(saslMechanisms: [String], bindRequired: Bool) {
        self.saslMechanisms = saslMechanisms
        self.bindRequired = bindRequired
    }
    public var supportsAnonymous: Bool { saslMechanisms.contains("ANONYMOUS") }
}

/// A MUC occupant item (`muc#user`).
public struct MUCItem: Equatable, Sendable {
    public var role: String?
    public var affiliation: String?
    public var jid: String?
    public init(role: String?, affiliation: String?, jid: String?) {
        self.role = role; self.affiliation = affiliation; self.jid = jid
    }
}

public struct Presence: Equatable, Sendable {
    public var from: String?
    public var to: String?
    /// nil means "available"; "unavailable" for a leave.
    public var type: String?
    public var nick: String?
    public var statsID: String?
    public var occupantID: String?
    public var audioMuted: Bool?
    public var videoMuted: Bool?
    public var mucItem: MUCItem?
    /// MUC status codes (110 = self-presence, 100 = anonymous room, ...).
    public var statusCodes: [Int]
    public var isSelfPresence: Bool { statusCodes.contains(110) }

    public init(from: String? = nil, to: String? = nil, type: String? = nil,
                nick: String? = nil, statsID: String? = nil, occupantID: String? = nil,
                audioMuted: Bool? = nil, videoMuted: Bool? = nil,
                mucItem: MUCItem? = nil, statusCodes: [Int] = []) {
        self.from = from; self.to = to; self.type = type; self.nick = nick
        self.statsID = statsID; self.occupantID = occupantID
        self.audioMuted = audioMuted; self.videoMuted = videoMuted
        self.mucItem = mucItem; self.statusCodes = statusCodes
    }
}

public struct Message: Equatable, Sendable {
    public var from: String?
    public var to: String?
    public var type: String?
    public var subject: String?
    /// A Jitsi `<json-message>` payload (endpoint/metadata signaling), raw.
    public var jsonMessage: String?
    public init(from: String? = nil, to: String? = nil, type: String? = nil,
                subject: String? = nil, jsonMessage: String? = nil) {
        self.from = from; self.to = to; self.type = type
        self.subject = subject; self.jsonMessage = jsonMessage
    }
}

public struct IQ: Equatable, Sendable {
    public var type: String       // get / set / result / error
    public var id: String?
    public var from: String?
    public var to: String?
    public var payload: IQPayload
    public init(type: String, id: String?, from: String?, to: String?, payload: IQPayload) {
        self.type = type; self.id = id; self.from = from; self.to = to; self.payload = payload
    }
}

public enum IQPayload: Equatable, Sendable {
    case bind(jid: String?)
    case discoInfo(DiscoInfo)
    case externalServices([ExternalService])   // XEP-0215 TURN/STUN discovery
    case conference(ConferenceResponse)         // Jicofo focus response
    case jingle(Jingle)
    case empty
    case unknown(element: String?)
}

public struct Identity: Equatable, Sendable {
    public var category: String
    public var type: String?
    public var name: String?
    public init(category: String, type: String?, name: String?) {
        self.category = category; self.type = type; self.name = name
    }
}

public struct DiscoInfo: Equatable, Sendable {
    public var identities: [Identity]
    public var features: [String]
    public init(identities: [Identity], features: [String]) {
        self.identities = identities; self.features = features
    }
    public func hasFeature(_ v: String) -> Bool { features.contains(v) }
}

public struct ExternalService: Equatable, Sendable {
    public var type: String          // stun / turn / turns
    public var host: String
    public var port: Int?
    public var transport: String?    // udp / tcp
    public var username: String?
    public var password: String?
    public var restricted: Bool?
    public var expires: String?
    public init(type: String, host: String, port: Int?, transport: String?,
                username: String?, password: String?, restricted: Bool?, expires: String?) {
        self.type = type; self.host = host; self.port = port; self.transport = transport
        self.username = username; self.password = password
        self.restricted = restricted; self.expires = expires
    }
}

/// Jicofo's response to a `conference` request (focus namespace).
public struct ConferenceResponse: Equatable, Sendable {
    public var ready: Bool
    public var room: String?
    public var focusJID: String?
    public var properties: [String: String]
    public init(ready: Bool, room: String?, focusJID: String?, properties: [String: String]) {
        self.ready = ready; self.room = room; self.focusJID = focusJID; self.properties = properties
    }
    public var authenticationRequired: Bool { properties["authentication"] == "true" }
    public var visitorsSupported: Bool { properties["visitors-supported"] == "true" }
}
