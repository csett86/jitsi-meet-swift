import XCTest
@testable import JitsiCore

/// [CLOUD-LIVE] integration tests against a real Jitsi deployment.
///
/// These are non-gating and OFF by default: they only run when
/// `JITSI_LIVE_TESTS=1` is set, and they target the URL in `JITSI_TEST_URL`
/// (or the default dedicated test room). CI never runs these as a gate — they
/// exist to catch real-server discrepancies that fixtures miss, on demand.
///
/// Courtesy rules apply (docs/live-testing.md): single client, short session,
/// dedicated room, never scheduled.
final class LiveSignalingTests: XCTestCase {

    private var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["JITSI_LIVE_TESTS"] == "1"
    }

    private var testURL: String {
        ProcessInfo.processInfo.environment["JITSI_TEST_URL"]
            ?? "https://jitsi.luki.org/JitsiMeetSwiftCiProbe"
    }

    func testConferenceURLResolves() throws {
        // This part is deterministic and always runs — it guards the contract
        // the live path depends on without touching the network.
        let parsed = try XCTUnwrap(ConferenceURLParser.parse(testURL))
        XCTAssertEqual(parsed.config.xmppWebSocketURL.scheme, "wss")
        XCTAssertTrue(parsed.config.mucDomain.hasPrefix("conference."))
    }

    func testLiveAccessProbe() async throws {
        try XCTSkipUnless(liveEnabled, "Set JITSI_LIVE_TESTS=1 to run live probes.")
        // Placeholder for the live connect → SASL → join → session-initiate
        // assertion, wired once URLSessionStanzaTransport lands (Phase 1).
        // Kept as an explicit skip so the target compiles and the intent is
        // documented without ever hitting the server unintentionally.
        throw XCTSkip("Live signaling assertions land with URLSessionStanzaTransport (Phase 1).")
    }
}
