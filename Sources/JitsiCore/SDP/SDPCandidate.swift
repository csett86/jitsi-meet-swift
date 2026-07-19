import Foundation

/// Converts between Jingle ICE candidates and SDP `candidate:` lines — pure
/// string logic (no WebRTC types), so it is unit-tested offline and reused by
/// the Apple media layer for trickle ICE.
///
/// SDP form (RFC 8839): `candidate:<foundation> <component> <transport>
/// <priority> <ip> <port> typ <type> [raddr <a> rport <p>] generation 0`.
public enum SDPCandidate {

    /// Render an ICE candidate as the value used by `RTCIceCandidate.sdp`
    /// (no `a=` prefix), e.g. `candidate:1 1 udp 2130706431 10.0.1.2 10000 typ host generation 0`.
    public static func line(from candidate: ICECandidate) -> String {
        let foundation = candidate.foundation ?? "1"
        let component = candidate.component ?? 1
        let proto = (candidate.proto ?? "udp").lowercased()
        let priority = candidate.priority ?? 0
        let ip = candidate.ip ?? "0.0.0.0"
        let port = candidate.port ?? 0
        let type = candidate.type ?? "host"
        return "candidate:\(foundation) \(component) \(proto) \(priority) \(ip) \(port) typ \(type) generation 0"
    }

    /// Parse an SDP candidate line into an ICE candidate. Accepts the line with
    /// or without a leading `a=` and/or `candidate:` prefix.
    public static func parse(_ raw: String) -> ICECandidate? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("a=") { line.removeFirst(2) }
        if line.hasPrefix("candidate:") { line.removeFirst("candidate:".count) }

        let tokens = line.split(separator: " ").map(String.init)
        // foundation component transport priority ip port "typ" type ...
        guard tokens.count >= 8, tokens[6] == "typ" else { return nil }
        return ICECandidate(
            foundation: tokens[0],
            component: Int(tokens[1]),
            proto: tokens[2],
            priority: Int(tokens[3]),
            ip: tokens[4],
            port: Int(tokens[5]),
            type: tokens[7]
        )
    }
}
