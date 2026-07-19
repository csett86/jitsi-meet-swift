import XCTest
@testable import JitsiCore

/// Drives the full join → focus-invite → session-description flow offline over
/// `FakeTransport` replaying the committed two-party fixture, and asserts the
/// typed events the conference emits. This is the Phase 1 [CLOUD] gate.
final class JitsiConferenceTests: XCTestCase {

    private struct Run {
        let events: [ConferenceEvent]
        let sent: [String]
    }

    private func runFixture(_ fixture: String = "lukijitsi-join.json") async throws -> Run {
        let inbound = try Fixtures.payloads(fixture, direction: "in")
        let transport = FakeTransport(inboundFrames: inbound)
        let config = try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/TestRoom")).config
        let conference = JitsiConference(
            transport: transport, config: config, roomName: "TestRoom",
            nick: "swifttest", machineUID: "test-uid"
        )
        let events = await conference.events
        async let collected = collect(events)
        await conference.join()
        let all = await collected
        let sent = await transport.sent()
        return Run(events: all, sent: sent)
    }

    private func collect(_ stream: AsyncStream<ConferenceEvent>) async -> [ConferenceEvent] {
        var out: [ConferenceEvent] = []
        for await event in stream { out.append(event) }
        return out
    }

    // MARK: - Roster

    func testRosterExcludesFocusAndTracksJoinsAndLeaves() async throws {
        let run = try await runFixture()
        var joins: [Participant] = []
        var leaves: [Participant] = []
        for case let .roster(change) in run.events {
            switch change {
            case .joined(let p): joins.append(p)
            case .left(let p): leaves.append(p)
            case .updated: break
            }
        }
        let joinedNicks = joins.map(\.nick)
        XCTAssertTrue(joinedNicks.contains("botA3358"))
        XCTAssertTrue(joinedNicks.contains("botB0286"))
        XCTAssertFalse(run.events.contains { event in
            if case let .roster(.joined(p)) = event { return p.nick == "focus" }
            return false
        }, "Jicofo focus must never appear in the roster")

        // The local user (self-presence, code 110) is flagged.
        XCTAssertTrue(joins.first { $0.nick == "botA3358" }?.isSelf ?? false)
        XCTAssertFalse(joins.first { $0.nick == "botB0286" }?.isSelf ?? true)

        // Both participants eventually leave.
        XCTAssertEqual(Set(leaves.map(\.nick)), ["botA3358", "botB0286"])
    }

    // MARK: - Capabilities

    func testCapabilitiesPopulatedFromDisco() async throws {
        let run = try await runFixture()
        let caps = try XCTUnwrap(firstCapabilities(run.events))
        XCTAssertTrue(caps.supportsLobby)
        XCTAssertTrue(caps.supportsBreakoutRooms)
        XCTAssertTrue(caps.supportsPolls)
        XCTAssertTrue(caps.supportsAVModeration)
        XCTAssertFalse(caps.supportsE2EE)     // not advertised on this deployment
    }

    private func firstCapabilities(_ events: [ConferenceEvent]) -> BackendCapabilities? {
        for case let .capabilities(c) in events { return c }
        return nil
    }

    // MARK: - ICE servers

    func testICEServersDerivedFromTURNDiscovery() async throws {
        let run = try await runFixture()
        var servers: [ICEServer] = []
        for case let .iceServers(s) in run.events { servers = s }
        XCTAssertFalse(servers.isEmpty)
        XCTAssertTrue(servers.contains { $0.urls.contains { $0.hasPrefix("stun:") } })
        XCTAssertTrue(servers.contains { server in
            server.urls.contains { $0.contains("turn:turn.jitsi.luki.org") }
        })
    }

    // MARK: - Conference readiness

    func testConferenceReadyIsAnonymous() async throws {
        let run = try await runFixture()
        var response: ConferenceResponse?
        for case let .conferenceReady(r) in run.events { response = r }
        let conf = try XCTUnwrap(response)
        XCTAssertTrue(conf.ready)
        XCTAssertFalse(conf.authenticationRequired)
    }

    // MARK: - Session description (the Phase 1 deliverable)

    func testEmitsParsedSessionDescription() async throws {
        let run = try await runFixture()
        var description: ParsedSessionDescription?
        for case let .sessionDescription(d) in run.events { description = d }
        let sdp = try XCTUnwrap(description, "Expected a ParsedSessionDescription from session-initiate")

        XCTAssertFalse(sdp.sid.isEmpty)
        XCTAssertEqual(Set(sdp.media.map(\.kind)), ["audio", "video"])
        XCTAssertTrue(sdp.audio?.codecNames.contains("opus") ?? false)
        let videoCodecs = Set(sdp.video?.codecNames ?? [])
        XCTAssertTrue(videoCodecs.isSuperset(of: ["VP8", "VP9", "H264", "AV1"]))
        XCTAssertTrue(sdp.bridgeWebSocketURL?.contains("colibri-ws") ?? false)
        XCTAssertNotNil(sdp.audio?.transport?.fingerprint)
    }

    // MARK: - State progression

    func testReachesJoinedState() async throws {
        let run = try await runFixture()
        let states: [ConferenceState] = run.events.compactMap {
            if case let .stateChanged(s) = $0 { return s }
            return nil
        }
        XCTAssertTrue(states.contains(.authenticating))
        XCTAssertTrue(states.contains(.joining))
        XCTAssertTrue(states.contains(.joined))
    }

    // MARK: - Outbound handshake

    func testSendsExpectedHandshakeStanzas() async throws {
        let run = try await runFixture()
        let joined = run.sent.joined(separator: "\n")
        XCTAssertTrue(joined.contains("mechanism='ANONYMOUS'"), "should authenticate anonymously")
        XCTAssertTrue(joined.contains("urn:ietf:params:xml:ns:xmpp-bind"), "should bind a resource")
        XCTAssertTrue(joined.contains("http://jitsi.org/protocol/focus"), "should send a conference request to Jicofo")
        XCTAssertTrue(joined.contains("name='JitsiMeetSwift'"), "should answer Jicofo's disco#info probe")
        XCTAssertTrue(joined.contains("<presence to='testroom@conference.jitsi.luki.org/swifttest'"),
                      "should send a MUC join presence")
    }
}
