import XCTest
@testable import JitsiCore

/// [CLOUD-LIVE] integration tests against a real Jitsi deployment.
///
/// Non-gating and OFF by default: they only run when `JITSI_LIVE_TESTS=1`, and
/// target `JITSI_TEST_URL` (or a default dedicated test room). CI never runs
/// these as a gate — they catch real-server discrepancies fixtures miss.
///
/// **Platform note:** the shipping `URLSessionStanzaTransport` relies on
/// `URLSessionWebSocketTask`. Apple's Foundation supports `wss://`; Linux's
/// swift-corelibs Foundation returns `NSURLErrorUnsupportedURL (-1002)`, so these
/// tests can only really connect on macOS. On Linux (and if the server is
/// unreachable) they **skip** rather than fail — the live protocol itself is
/// validated on Linux via the Python capture (`Tools/LiveCapture/python`), and
/// this is the [MAC] Apple-URLSession confirmation. See docs/findings.md.
///
/// Courtesy rules apply (docs/live-testing.md): dedicated rooms, short sessions,
/// the fewest clients that answer the question, never scheduled.
final class LiveSignalingTests: XCTestCase {

    private var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["JITSI_LIVE_TESTS"] == "1"
    }
    private var baseURL: String {
        ProcessInfo.processInfo.environment["JITSI_TEST_URL"]
            ?? "https://jitsi.luki.org/jitsimeetswiftlivetest"
    }
    private func dedicatedRoomURL() -> String {
        baseURL + String(UUID().uuidString.prefix(6)).lowercased()
    }

    private struct Outcome {
        var reachedGoal = false
        var transportFailure: String?
    }

    // Deterministic guard — always runs, no network.
    func testConferenceURLResolves() throws {
        let parsed = try XCTUnwrap(ConferenceURLParser.parse(baseURL))
        XCTAssertEqual(parsed.config.xmppWebSocketURL.scheme, "wss")
        XCTAssertTrue(parsed.config.mucDomain.hasPrefix("conference."))
    }

    /// Single client: real connect → SASL ANONYMOUS → bind → disco → conference
    /// ready → MUC join. (A solo participant is not offered session-initiate on
    /// this deployment — see the two-party test.)
    func testLiveConnectAndJoin() async throws {
        try XCTSkipUnless(liveEnabled, "Set JITSI_LIVE_TESTS=1 to run live tests.")
        let parsed = try XCTUnwrap(ConferenceURLParser.parse(dedicatedRoomURL()))
        let conference = makeConference(parsed)

        var joined = false, sawCapabilities = false, sawICE = false, ready = false
        let outcome = await drive(conference, timeout: 25) { event in
            switch event {
            case .stateChanged(.joined): joined = true
            case .capabilities: sawCapabilities = true
            case .iceServers: sawICE = true
            case .conferenceReady(let r): ready = r.ready
            default: break
            }
            return joined && sawCapabilities && sawICE && ready
        }

        try skipIfTransportUnavailable(outcome)
        XCTAssertTrue(ready, "Jicofo should report the conference ready")
        XCTAssertTrue(joined, "should reach MUC self-presence (joined)")
        XCTAssertTrue(sawCapabilities, "should receive disco#info capabilities")
        XCTAssertTrue(sawICE, "should receive TURN/STUN ICE servers")
    }

    /// Two clients in one dedicated room: the second joiner triggers Jicofo to
    /// send the first client a `session-initiate`.
    func testLiveReachesSessionInitiate() async throws {
        try XCTSkipUnless(liveEnabled, "Set JITSI_LIVE_TESTS=1 to run live tests.")
        let parsed = try XCTUnwrap(ConferenceURLParser.parse(dedicatedRoomURL()))
        let primary = makeConference(parsed, nick: "swiftlive-a")
        let secondary = makeConference(parsed, nick: "swiftlive-b")

        var gotOffer = false
        let outcome = await drive(primary, timeout: 30, startAfter: 4.0, second: secondary) { event in
            if case .sessionDescription = event { gotOffer = true; return true }
            return false
        }
        await secondary.leave()

        try skipIfTransportUnavailable(outcome)
        XCTAssertTrue(gotOffer, "two participants should yield a session-initiate")
    }

    // MARK: - Helpers

    private func skipIfTransportUnavailable(_ outcome: Outcome) throws {
        if !outcome.reachedGoal, let failure = outcome.transportFailure {
            throw XCTSkip("Live socket unavailable (\(failure)). "
                + "Expected on Linux (wss URLSession unsupported) or when the server is unreachable.")
        }
    }

    private func makeConference(_ parsed: ParsedConference, nick: String = "swiftlive") -> JitsiConference {
        JitsiConference(
            transport: URLSessionStanzaTransport(url: parsed.config.xmppWebSocketURL),
            config: parsed.config,
            roomName: parsed.roomName,
            nick: nick + "-" + String(UUID().uuidString.prefix(4))
        )
    }

    /// Run a conference live, feeding each event to `until`; stop when it returns
    /// true or the timeout elapses, then leave. Records any transport-level
    /// failure so the caller can skip instead of fail.
    private func drive(_ conference: JitsiConference, timeout: TimeInterval,
                       startAfter delay: TimeInterval? = nil,
                       second: JitsiConference? = nil,
                       until: @escaping (ConferenceEvent) -> Bool) async -> Outcome {
        let events = await conference.events
        let joinTask = Task { await conference.join() }
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await conference.leave()
        }
        if let delay, let second {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await second.join()
            }
        }
        var outcome = Outcome()
        for await event in events {
            if case let .stateChanged(.failed(reason)) = event {
                outcome.transportFailure = reason
            }
            if until(event) { outcome.reachedGoal = true; break }
        }
        timeoutTask.cancel()
        joinTask.cancel()
        await conference.leave()
        return outcome
    }
}
