#if os(macOS)
import XCTest
import WebRTC
@testable import JitsiMedia
@testable import JitsiCore

/// [MAC] Phase 2 — the signaling↔media glue (`ConferenceCall`) end to end.
///
/// Offline: `FakeTransport` replays the committed two-party join through to the
/// JVB's `session-initiate`; `ConferenceCall` answers with a real
/// `RTCPeerConnection` and must send a correctly-addressed Jingle
/// `session-accept` back through the transport.
///
/// Live (`JITSI_LIVE_TESTS=1`): a real two-party call whose ICE must reach
/// `connected` — the automatable proof that the JVB accepted our
/// `session-accept` and the transport came up. On-screen rendering of a remote
/// participant still needs the app + a human (docs/mac-signoff.md).
final class ConferenceCallTests: XCTestCase {

    private static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/fixtures", isDirectory: true)
    }
    private struct Frame: Codable { let direction: String; let payload: String }
    private func fixtureInboundFrames() throws -> [String] {
        let url = Self.fixturesDir.appendingPathComponent("lukijitsi-join.json")
        let frames = try JSONDecoder().decode([Frame].self, from: try Data(contentsOf: url))
        return frames.filter { $0.direction == "in" }.map(\.payload)
    }

    // MARK: - Offline: correctly-addressed session-accept through the coordinator

    func testConferenceCallSendsCorrectlyAddressedSessionAccept() async throws {
        let transport = FakeTransport(inboundFrames: try fixtureInboundFrames())
        let config = try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/TestRoom")).config
        let conference = JitsiConference(transport: transport, config: config,
                                         roomName: "TestRoom", nick: "swifttest", machineUID: "test-uid")
        let factory = PeerConnectionFactory()
        let localMedia = LocalMediaSource(factory: factory.factory)
        let call = ConferenceCall(conference: conference, factory: factory, localMedia: localMedia)

        let runTask = Task { await call.run() }
        await conference.join()

        // The answer + acceptSession complete asynchronously after join() returns;
        // poll the transport for the session-accept we sent (≤5s).
        var accept: String?
        for _ in 0..<50 {
            if let sent = await transport.sent().first(where: { $0.contains("action='session-accept'") }) {
                accept = sent; break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        runTask.cancel()
        call.close()

        let xml = try XCTUnwrap(accept, "ConferenceCall never sent a session-accept")
        // Addressed to the focus occupant (the offer's `from`), NOT the auth JID.
        XCTAssertTrue(xml.contains("to='jitsimeetswiftfixturecapture4543a06c@conference.jitsi.luki.org/focus'"),
                      "session-accept must be addressed to the focus occupant JID")
        let boundJID = await conference.localJID
        let localJID = try XCTUnwrap(boundJID)
        XCTAssertTrue(xml.contains("responder='\(localJID)'"), "responder must be our bound JID")
        XCTAssertTrue(xml.contains("initiator='focus@auth.jitsi.luki.org/focus'"))
        // Carries our real media: both bundled sections + a DTLS fingerprint.
        let stanza = StanzaParser.parse(xml)
        guard case let .iq(iq)? = stanza, case let .jingle(jingle) = iq.payload else {
            return XCTFail("session-accept did not round-trip through the parser")
        }
        XCTAssertEqual(jingle.action, "session-accept")
        XCTAssertEqual(Set(jingle.contents.map(\.name)), ["audio", "video"])
        XCTAssertTrue(xml.contains("<fingerprint"), "answer must carry a DTLS fingerprint")
    }

    // MARK: - Live: two-party call ICE connectivity (JVB accepts session-accept)

    func testLiveTwoPartyMediaConnects() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JITSI_LIVE_TESTS"] == "1",
                          "Set JITSI_LIVE_TESTS=1 to run the live media call.")
        let base = ProcessInfo.processInfo.environment["JITSI_TEST_URL"]
            ?? "https://jitsi.luki.org/jitsimeetswiftmedia"
        let room = base + String(UUID().uuidString.prefix(6)).lowercased()
        let parsed = try XCTUnwrap(ConferenceURLParser.parse(room))

        // Primary: real media, driven by the ConferenceCall coordinator.
        let primary = JitsiConference(
            transport: URLSessionStanzaTransport(url: parsed.config.xmppWebSocketURL),
            config: parsed.config, roomName: parsed.roomName, nick: "swiftmedia-a")
        let factory = PeerConnectionFactory()
        let localMedia = LocalMediaSource(factory: factory.factory)
        let call = ConferenceCall(conference: primary, factory: factory, localMedia: localMedia)

        let connected = expectation(description: "ICE connected")
        connected.assertForOverFulfill = false
        call.onIceStateChange = { state in
            if state == .connected || state == .completed { connected.fulfill() }
        }

        // Secondary: signaling-only, present so Jicofo offers primary media.
        let secondary = JitsiConference(
            transport: URLSessionStanzaTransport(url: parsed.config.xmppWebSocketURL),
            config: parsed.config, roomName: parsed.roomName, nick: "swiftmedia-b")

        let callTask = Task { await call.run() }
        let primaryJoin = Task { await primary.join() }
        let secondaryJoin = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await secondary.join()
        }

        await fulfillment(of: [connected], timeout: 45)

        callTask.cancel(); secondaryJoin.cancel(); primaryJoin.cancel()
        await secondary.leave()
        await primary.leave()
        call.close()
    }

    // MARK: - Live: colibri bridge channel connects over wss (Phase 3)

    /// [MAC] Phase 3, item 1 — the colibri `<web-socket>` from the
    /// `session-initiate` is reachable over Apple's `URLSession` wss (Linux
    /// cannot), and receiver constraints can be pushed over it. The dominant
    /// speaker + actual video effect still need multi-party audio + rendering.
    func testLiveBridgeChannelConnects() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JITSI_LIVE_TESTS"] == "1",
                          "Set JITSI_LIVE_TESTS=1 to run the live bridge test.")
        let base = ProcessInfo.processInfo.environment["JITSI_TEST_URL"]
            ?? "https://jitsi.luki.org/jitsimeetswiftbridge"
        let room = base + String(UUID().uuidString.prefix(6)).lowercased()
        let parsed = try XCTUnwrap(ConferenceURLParser.parse(room))

        let primary = JitsiConference(
            transport: URLSessionStanzaTransport(url: parsed.config.xmppWebSocketURL),
            config: parsed.config, roomName: parsed.roomName, nick: "swiftbridge-a")
        let factory = PeerConnectionFactory()
        let localMedia = LocalMediaSource(factory: factory.factory)
        let call = ConferenceCall(conference: primary, factory: factory, localMedia: localMedia)

        let bridgeOpen = expectation(description: "colibri bridge wss opened")
        bridgeOpen.assertForOverFulfill = false
        call.onBridgeOpen = { bridgeOpen.fulfill() }
        // Opportunistic — not asserted (needs real multi-party audio to fire).
        call.onDominantSpeaker = { print("[bridge] dominant speaker: \($0)\n") }

        let secondary = JitsiConference(
            transport: URLSessionStanzaTransport(url: parsed.config.xmppWebSocketURL),
            config: parsed.config, roomName: parsed.roomName, nick: "swiftbridge-b")

        let callTask = Task { await call.run() }
        let primaryJoin = Task { await primary.join() }
        let secondaryJoin = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await secondary.join()
        }

        await fulfillment(of: [bridgeOpen], timeout: 45)
        // Bridge is up — exercise the receiver-constraints send path over it.
        call.setReceiverConstraints(
            QualityController.constraints(visibleEndpoints: ["swiftbridge-b"], bandwidth: .medium))
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        callTask.cancel(); secondaryJoin.cancel(); primaryJoin.cancel()
        await secondary.leave()
        await primary.leave()
        call.close()
    }
}
#endif
