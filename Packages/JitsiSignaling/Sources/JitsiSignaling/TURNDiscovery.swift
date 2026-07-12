// MARK: - TURN Discovery (XEP-0215)

/// Convenience wrapper around XEP-0215 external service discovery.
///
/// Call ``TURNDiscovery/discover(via:to:)`` immediately after authentication to
/// populate your ICE candidate policy with live STUN/TURN servers — do not
/// hardcode these.
public enum TURNDiscovery {
    /// Queries the server for external services (STUN/TURN).
    ///
    /// - Parameters:
    ///   - connection: A ready (authenticated, bound) XMPP connection.
    ///   - domain: The XMPP server domain to query (same domain as the connection).
    /// - Returns: Array of external services; may be empty if the server doesn't
    ///   support XEP-0215 or returns an error IQ.
    public static func discover(
        via connection: XMPPWebSocketConnection,
        to domain: String
    ) async throws -> [ExternalService] {
        let iqID = try await connection.sendIQ(
            type: "get",
            to: domain,
            payload: "<services xmlns=\"\(XMPPNS.extdisco)\"/>"
        )

        let stanzaStream = await connection.stanzas
        for await stanza in stanzaStream {
            guard case .iq(let iq) = stanza, iq.id == iqID else { continue }
            if case .externalServices(let svcs) = iq.payload { return svcs }
            if case .error = iq.payload { return [] }
        }
        return []
    }

    /// Filters a service list to STUN endpoints only.
    public static func stun(from services: [ExternalService]) -> [ExternalService] {
        services.filter { $0.type == .stun }
    }

    /// Filters a service list to TURN endpoints only (plain and TLS).
    public static func turn(from services: [ExternalService]) -> [ExternalService] {
        services.filter { $0.type == .turn || $0.type == .turns }
    }

    /// Builds an RFC 5389 STUN URI string from a service descriptor.
    public static func uri(for service: ExternalService) -> String? {
        switch service.type {
        case .stun:
            return "stun:\(service.host):\(service.port)"
        case .turn:
            let transport = service.transport.map { "?transport=\($0)" } ?? ""
            return "turn:\(service.host):\(service.port)\(transport)"
        case .turns:
            let transport = service.transport.map { "?transport=\($0)" } ?? ""
            return "turns:\(service.host):\(service.port)\(transport)"
        case .other:
            return nil
        }
    }
}
