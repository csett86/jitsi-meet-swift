// MARK: - BackendCapabilities

/// Capabilities derived from live XEP-0030 disco#info queries made immediately
/// after authentication.
///
/// Build via ``BackendCapabilities/init(serverInfo:mucInfo:)`` by passing the
/// parsed ``DiscoInfoResult`` from queries to the XMPP domain and the
/// conference component. The struct avoids hardcoding any assumptions about what
/// a given server supports — which is especially important for alpha.jitsi.net
/// where feature flags can change between deployments.
public struct BackendCapabilities: Sendable {
    // MARK: - Server-level features

    /// Server supports XEP-0215 external service discovery (STUN/TURN).
    public let supportsExtdisco: Bool

    // MARK: - MUC / conference features

    /// Conference component reports `http://jitsi.org/lobby` feature.
    public let supportsLobby: Bool
    /// Conference component reports `http://jitsi.org/visitors` feature.
    public let supportsVisitors: Bool
    /// Conference component reports `http://jitsi.org/e2ee` feature.
    public let supportsE2EE: Bool

    // MARK: - Init

    /// - Parameters:
    ///   - serverInfo: Result of `disco#info` to the XMPP server domain.
    ///   - mucInfo: Result of `disco#info` to the MUC/conference component.
    public init(serverInfo: DiscoInfoResult, mucInfo: DiscoInfoResult) {
        supportsExtdisco  = serverInfo.supports("urn:xmpp:extdisco:2")
        supportsLobby     = mucInfo.supports("http://jitsi.org/lobby")
        supportsVisitors  = mucInfo.supports("http://jitsi.org/visitors")
        supportsE2EE      = mucInfo.supports("http://jitsi.org/e2ee")
    }

    /// Convenience initialiser for when only partial info is available.
    public init(
        supportsExtdisco: Bool = false,
        supportsLobby: Bool = false,
        supportsVisitors: Bool = false,
        supportsE2EE: Bool = false
    ) {
        self.supportsExtdisco = supportsExtdisco
        self.supportsLobby = supportsLobby
        self.supportsVisitors = supportsVisitors
        self.supportsE2EE = supportsE2EE
    }
}
