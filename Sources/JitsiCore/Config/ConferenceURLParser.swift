import Foundation

/// Turns a single conference URL — the app's only connection input — into a
/// ``BackendConfig`` plus a room name.
///
/// Accepts anything a user is likely to paste:
/// - a bare `host/room` with no scheme (`jitsi.luki.org/SomeRoom123`),
/// - a full URL (`https://jitsi.luki.org/SomeRoom123`),
/// - trailing slashes and percent-encoded room names,
/// - surrounding whitespace.
///
/// Returns `nil` for anything that cannot yield both a host and a room, so the
/// UI never has to invent its own validation.
public enum ConferenceURLParser {
    public static func parse(_ input: String) -> ParsedConference? {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // Default to https:// when the user pasted a bare host/room.
        if !raw.contains("://") {
            raw = "https://" + raw
        }

        guard
            let components = URLComponents(string: raw),
            let host = components.host,
            !host.isEmpty
        else { return nil }

        // The room is the last non-empty path segment, percent-decoded.
        let segments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard
            let last = segments.last,
            let roomName = last.removingPercentEncoding,
            !roomName.isEmpty
        else { return nil }

        let config = BackendConfig(
            displayName: host,
            xmppWebSocketURL: URL(string: "wss://\(host)/xmpp-websocket")!,
            mucDomain: "conference.\(host)",
            focusJID: "focus.\(host)",
            anonymousDomain: nil,
            jwtToken: nil
        )
        return ParsedConference(config: config, roomName: roomName)
    }
}
