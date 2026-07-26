import Foundation

/// Timing for the signaling keepalive. **Keepalive is mandatory** — there is
/// deliberately no way to switch it off.
///
/// An XMPP-over-WebSocket connection that sends nothing gets dropped by the
/// server after roughly a minute. When that happens the client silently leaves
/// the MUC; if that empties the conference of everyone else, the focus ends the
/// session, and the media path dies with no stanza that obviously explains it.
/// That was the root cause of the "call dies after 60–95s" bug (docs/findings.md),
/// so the ability to run without a keepalive was removed rather than left as a
/// footgun.
///
/// `lib-jitsi-meet` pings (XEP-0199) every 10s; we do the same.
public struct KeepAlivePolicy: Equatable, Sendable {
    /// Seconds between pings.
    public var interval: TimeInterval
    /// Consecutive unanswered pings tolerated before the link is declared dead.
    public var missedPingThreshold: Int

    public init(interval: TimeInterval = 10, missedPingThreshold: Int = 3) {
        // A non-positive interval would mean "never ping", i.e. the disabled
        // behavior this type exists to prevent.
        self.interval = interval > 0 ? interval : 10
        self.missedPingThreshold = max(1, missedPingThreshold)
    }

    /// Ping every 10s, give up after 3 unanswered (≈30s), matching
    /// `lib-jitsi-meet`.
    public static let `default` = KeepAlivePolicy()
}

/// Health of the signaling link, derived purely from ping/pong bookkeeping.
public enum KeepAliveHealth: Equatable, Sendable {
    /// Every ping so far has been answered.
    case healthy
    /// One or more pings are outstanding, but still under the threshold.
    case degraded(missed: Int)
    /// The threshold was reached — treat the link as dead.
    case dead(missed: Int)
}

/// Pure ping/pong bookkeeping: which pings are outstanding and what that implies
/// about the link. Separated from the timer so it is exhaustively unit-testable
/// offline; ``JitsiConference`` owns the actual scheduling and I/O.
public struct KeepAliveTracker: Equatable, Sendable {
    private let policy: KeepAlivePolicy
    private var sequence = 0
    /// Pings sent but not yet answered, oldest first.
    private var outstanding: [String] = []

    public init(policy: KeepAlivePolicy = .default) {
        self.policy = policy
    }

    /// Number of pings sent and still unanswered.
    public var missedCount: Int { outstanding.count }

    public var health: KeepAliveHealth {
        let missed = outstanding.count
        if missed == 0 { return .healthy }
        if missed >= policy.missedPingThreshold { return .dead(missed: missed) }
        return .degraded(missed: missed)
    }

    /// Allocate the id for the next outgoing ping and record it as outstanding.
    public mutating func nextPingID() -> String {
        sequence += 1
        let id = "ka-\(sequence)"
        outstanding.append(id)
        return id
    }

    /// Record a reply. Any response — a result *or* an error — proves the link
    /// is alive (an error means the server is talking to us), so both clear the
    /// ping. Returns true if the id was one of ours.
    ///
    /// Older outstanding pings are cleared too: XMPP replies can arrive out of
    /// order, and a newer pong implies the link carried the older ones.
    @discardableResult
    public mutating func handleReply(id: String) -> Bool {
        guard let index = outstanding.firstIndex(of: id) else { return false }
        outstanding.removeFirst(index + 1)
        return true
    }

    /// Any inbound traffic at all proves the link is alive, so it clears
    /// outstanding pings — this keeps a busy conference from ever tripping the
    /// dead threshold just because a pong was slow.
    public mutating func noteInboundTraffic() {
        outstanding.removeAll()
    }

    /// True when the id looks like one of our keepalive pings.
    public static func isKeepAliveID(_ id: String?) -> Bool {
        id?.hasPrefix("ka-") ?? false
    }
}
