import Foundation

/// The single source of connection details for a Jitsi conference.
///
/// Create one instance by parsing a full Jitsi conference URL
/// (e.g. `https://alpha.jitsi.net/SomeRoomName123`) via ``init(conferenceURL:)-swift.init``.
/// Nothing else in the app should construct or hardcode a `BackendConfig` by hand.
struct BackendConfig: Sendable {
    /// The room name exactly as it appears in the URL path (preserves original casing).
    let displayName: String
    /// WebSocket endpoint for the XMPP connection — always a `wss://` URL.
    let xmppWebSocketURL: URL
    /// XMPP server domain (e.g. `alpha.jitsi.net`).
    let xmppDomain: String
    /// Multi-User Chat domain (e.g. `conference.alpha.jitsi.net`).
    let mucDomain: String
    /// Auth sub-domain used by Jicofo (e.g. `auth.alpha.jitsi.net`).
    let authDomain: String
    /// Bare JID of the focus component (e.g. `focus@auth.alpha.jitsi.net`).
    let focusUserJID: String
    /// Lowercased room name — used as the MUC local part.
    let roomName: String
    /// Full JID of the conference room (e.g. `myroomname@conference.alpha.jitsi.net`).
    let conferenceJID: String
}

// MARK: - Parsing

extension BackendConfig {
    /// Errors thrown when a conference URL cannot be parsed into a ``BackendConfig``.
    enum ParseError: LocalizedError {
        case invalidURL
        case unsupportedScheme(String)
        case missingHost
        case missingRoomName

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The conference URL is not valid."
            case .unsupportedScheme(let scheme):
                return "Unsupported URL scheme '\(scheme)'; only 'https' is accepted."
            case .missingHost:
                return "The conference URL does not contain a host."
            case .missingRoomName:
                return "The conference URL does not contain a room name (path component after the host)."
            }
        }
    }

    /// Parses a `BackendConfig` from a conference URL string.
    ///
    /// - Parameter urlString: A full conference URL, e.g. `"https://alpha.jitsi.net/MyRoom"`.
    /// - Throws: ``ParseError`` if the URL is malformed or missing required components.
    init(conferenceURL urlString: String) throws {
        guard let url = URL(string: urlString) else {
            throw ParseError.invalidURL
        }
        try self.init(conferenceURL: url)
    }

    /// Parses a `BackendConfig` from a conference `URL`.
    ///
    /// - Parameter url: A full conference URL, e.g. `https://alpha.jitsi.net/MyRoom`.
    /// - Throws: ``ParseError`` if the URL is malformed or missing required components.
    init(conferenceURL url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw ParseError.unsupportedScheme(url.scheme ?? "(none)")
        }
        guard let host = url.host, !host.isEmpty else {
            throw ParseError.missingHost
        }

        // The room is the first non-empty, non-slash path component.
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
        guard let wsURL = wsComps.url else {
            throw ParseError.invalidURL
        }

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
