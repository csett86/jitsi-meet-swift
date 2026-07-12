import Foundation

/// The single source of connection details for a Jitsi conference.
///
/// Create via ``init(conferenceURL:)-swift.init`` by passing a full conference
/// URL such as `"https://alpha.jitsi.net/SomeRoom"`. Nothing else in the
/// signaling layer constructs `BackendConfig` values by hand.
public struct BackendConfig: Sendable, Equatable {
    /// Room name exactly as it appears in the URL path (preserves original casing).
    public let displayName: String
    /// WebSocket endpoint — always a `wss://` URL.
    public let xmppWebSocketURL: URL
    /// XMPP server domain, e.g. `alpha.jitsi.net`.
    public let xmppDomain: String
    /// Multi-User Chat domain, e.g. `conference.alpha.jitsi.net`.
    public let mucDomain: String
    /// Auth sub-domain used by Jicofo, e.g. `auth.alpha.jitsi.net`.
    public let authDomain: String
    /// Bare JID of the focus component, e.g. `focus@auth.alpha.jitsi.net`.
    public let focusUserJID: String
    /// Lowercased room name — used as the MUC local part.
    public let roomName: String
    /// Full JID of the conference room, e.g. `myroom@conference.alpha.jitsi.net`.
    public let conferenceJID: String
}

// MARK: - Parsing

extension BackendConfig {
    /// Errors thrown when a conference URL cannot produce a valid `BackendConfig`.
    public enum ParseError: LocalizedError, Sendable {
        case invalidURL
        case unsupportedScheme(String)
        case missingHost
        case missingRoomName

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The conference URL is not valid."
            case .unsupportedScheme(let s):
                return "Unsupported URL scheme '\(s)'; only 'https' is accepted."
            case .missingHost:
                return "The conference URL does not contain a host."
            case .missingRoomName:
                return "The conference URL does not contain a room name (path component)."
            }
        }
    }

    /// Parses a `BackendConfig` from a conference URL string.
    ///
    /// - Parameter urlString: e.g. `"https://alpha.jitsi.net/MyRoom"`.
    /// - Throws: ``ParseError`` if the URL is malformed or missing components.
    public init(conferenceURL urlString: String) throws {
        guard let url = URL(string: urlString) else { throw ParseError.invalidURL }
        try self.init(conferenceURL: url)
    }

    /// Parses a `BackendConfig` from a conference `URL`.
    public init(conferenceURL url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw ParseError.unsupportedScheme(url.scheme ?? "(none)")
        }
        guard let host = url.host, !host.isEmpty else {
            throw ParseError.missingHost
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let rawRoom = pathComponents.first else {
            throw ParseError.missingRoomName
        }

        let room = rawRoom.lowercased()
        let mucd = "conference.\(host)"
        let authd = "auth.\(host)"

        var wsComps = URLComponents()
        wsComps.scheme = "wss"
        wsComps.host = host
        wsComps.path = "/xmpp-websocket"
        guard let wsURL = wsComps.url else { throw ParseError.invalidURL }

        self.displayName = rawRoom
        self.roomName = room
        self.xmppDomain = host
        self.mucDomain = mucd
        self.authDomain = authd
        self.focusUserJID = "focus@\(authd)"
        self.conferenceJID = "\(room)@\(mucd)"
        self.xmppWebSocketURL = wsURL
    }
}
