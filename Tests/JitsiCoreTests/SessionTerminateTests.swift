import XCTest
@testable import JitsiCore

/// `session-terminate` is how Jicofo routinely ends a session — notably once
/// every other participant has left, so the conference no longer needs a bridge.
/// Ignoring it leaves a live peer connection whose ICE later fails for no
/// visible reason, which is exactly how the "call dies after 60–95s" symptom
/// presented. See docs/findings.md.
final class SessionTerminateTests: XCTestCase {

    private let terminate = """
    <iq type='set' from='room@conference.jitsi.luki.org/focus' to='me@jitsi.luki.org/res' id='t1' xmlns='jabber:client'>\
    <jingle xmlns='urn:xmpp:jingle:1' action='session-terminate' sid='abc'>\
    <reason><success/><text>Nobody is left in the conference</text></reason>\
    </jingle></iq>
    """

    func testParsesTerminateWithReason() throws {
        guard case let .iq(iq)? = StanzaParser.parse(terminate),
              case let .jingle(jingle) = iq.payload else {
            return XCTFail("expected a Jingle IQ")
        }
        XCTAssertEqual(jingle.action, "session-terminate")
        XCTAssertEqual(jingle.sid, "abc")
        // The condition, not the free-text explanation.
        XCTAssertEqual(jingle.reason, "success")
    }

    func testTerminateWithoutReasonParses() throws {
        let xml = "<iq type='set' from='room@x/focus' id='t2' xmlns='jabber:client'>"
            + "<jingle xmlns='urn:xmpp:jingle:1' action='session-terminate' sid='s'/></iq>"
        guard case let .iq(iq)? = StanzaParser.parse(xml),
              case let .jingle(jingle) = iq.payload else {
            return XCTFail("expected a Jingle IQ")
        }
        XCTAssertNil(jingle.reason)
    }

    func testConferenceEmitsSessionTerminatedAndAcksIt() async throws {
        let config = try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/Room")).config
        let transport = FakeTransport(inboundFrames: [terminate])
        let conference = JitsiConference(transport: transport, config: config,
                                         roomName: "Room", nick: "me", machineUID: "uid")
        var events: [ConferenceEvent] = []
        let stream = await conference.events
        async let collected: [ConferenceEvent] = {
            var out: [ConferenceEvent] = []
            for await event in stream { out.append(event) }
            return out
        }()
        await conference.join()
        events = await collected

        let reasons = events.compactMap { event -> String?? in
            if case let .sessionTerminated(reason) = event { return reason }
            return nil
        }
        XCTAssertEqual(reasons.count, 1, "session-terminate must be surfaced")
        XCTAssertEqual(reasons.first ?? nil, "success")

        // XMPP requires a reply to every type='set'.
        let sent = await transport.sent()
        XCTAssertTrue(sent.contains { $0.contains("type='result'") && $0.contains("id='t1'") },
                      "session-terminate must be acked; sent: \(sent)")
    }

    func testTerminateClearsSessionStateSoReinviteIsClean() async throws {
        // After a terminate, a stale offer must not linger: acceptSession() for
        // the old session must be a no-op, otherwise a re-invite would answer
        // with the wrong sid.
        let config = try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/Room")).config
        var frames = try Fixtures.payloads("lukijitsi-join.json", direction: "in")
        frames.append(terminate)
        let transport = FakeTransport(inboundFrames: frames)
        let conference = JitsiConference(transport: transport, config: config,
                                         roomName: "Room", nick: "me", machineUID: "uid")
        await conference.join()

        let before = await transport.sent().count
        await conference.acceptSession(local: LocalSDP(media: []))
        let after = await transport.sent().count
        XCTAssertEqual(before, after,
                       "no session-accept may be sent after the session was terminated")
    }
}
