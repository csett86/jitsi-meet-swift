import Foundation

/// All connection details required to reach a Jitsi deployment, derived from a
/// single conference URL. This is the one source of truth for host/domain
/// information used across the whole app — no other layer hardcodes a hostname.
///
/// The subdomain conventions (`conference.<host>`, `focus.<host>`,
/// `wss://<host>/xmpp-websocket`) follow a standard Jitsi deployment. A
/// self-hosted instance we do not control may deviate; if it does, the real
/// values must be recorded in docs/findings.md and reflected here.
public struct BackendConfig: Equatable, Sendable {
    /// A human-friendly name for the deployment (defaults to the host).
    public let displayName: String
    /// The XMPP-over-WebSocket endpoint, e.g. `wss://jitsi.luki.org/xmpp-websocket`.
    public let xmppWebSocketURL: URL
    /// The MUC (multi-user chat) domain, e.g. `conference.jitsi.luki.org`.
    public let mucDomain: String
    /// The Jicofo focus component JID, e.g. `focus.jitsi.luki.org`.
    public let focusJID: String
    /// The anonymous auth domain, if the deployment exposes one.
    public let anonymousDomain: String?
    /// A JWT token to present during SASL, if authentication is required.
    public let jwtToken: String?

    public init(
        displayName: String,
        xmppWebSocketURL: URL,
        mucDomain: String,
        focusJID: String,
        anonymousDomain: String? = nil,
        jwtToken: String? = nil
    ) {
        self.displayName = displayName
        self.xmppWebSocketURL = xmppWebSocketURL
        self.mucDomain = mucDomain
        self.focusJID = focusJID
        self.anonymousDomain = anonymousDomain
        self.jwtToken = jwtToken
    }
}

/// A parsed conference: where to connect (`config`) and which room to join.
public struct ParsedConference: Equatable, Sendable {
    public let config: BackendConfig
    public let roomName: String

    public init(config: BackendConfig, roomName: String) {
        self.config = config
        self.roomName = roomName
    }
}
