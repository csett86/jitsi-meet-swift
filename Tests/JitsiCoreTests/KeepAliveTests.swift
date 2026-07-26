import XCTest
@testable import JitsiCore

final class KeepAliveTrackerTests: XCTestCase {

    func testHealthyUntilAPingGoesUnanswered() {
        var tracker = KeepAliveTracker(policy: KeepAlivePolicy(interval: 10, missedPingThreshold: 3))
        XCTAssertEqual(tracker.health, .healthy)

        let first = tracker.nextPingID()
        XCTAssertEqual(tracker.health, .degraded(missed: 1))
        XCTAssertTrue(tracker.handleReply(id: first))
        XCTAssertEqual(tracker.health, .healthy)
    }

    func testReachesDeadAtThreshold() {
        var tracker = KeepAliveTracker(policy: KeepAlivePolicy(interval: 10, missedPingThreshold: 3))
        _ = tracker.nextPingID()
        _ = tracker.nextPingID()
        XCTAssertEqual(tracker.health, .degraded(missed: 2))
        _ = tracker.nextPingID()
        XCTAssertEqual(tracker.health, .dead(missed: 3))
    }

    func testPingIDsAreUniqueAndRecognizable() {
        var tracker = KeepAliveTracker()
        let a = tracker.nextPingID()
        let b = tracker.nextPingID()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(KeepAliveTracker.isKeepAliveID(a))
        XCTAssertTrue(KeepAliveTracker.isKeepAliveID(b))
        XCTAssertFalse(KeepAliveTracker.isKeepAliveID("jingle-1"))
        XCTAssertFalse(KeepAliveTracker.isKeepAliveID(nil))
    }

    func testUnknownReplyIsIgnored() {
        var tracker = KeepAliveTracker()
        _ = tracker.nextPingID()
        XCTAssertFalse(tracker.handleReply(id: "not-ours"))
        XCTAssertEqual(tracker.missedCount, 1)
    }

    func testLatePongClearsOlderOutstandingPings() {
        // Replies can arrive out of order; a newer pong proves the link carried
        // the older pings too, so they must not accumulate toward "dead".
        var tracker = KeepAliveTracker(policy: KeepAlivePolicy(interval: 10, missedPingThreshold: 3))
        _ = tracker.nextPingID()
        _ = tracker.nextPingID()
        let third = tracker.nextPingID()
        XCTAssertEqual(tracker.health, .dead(missed: 3))
        tracker.handleReply(id: third)
        XCTAssertEqual(tracker.health, .healthy)
    }

    func testAnyInboundTrafficProvesLiveness() {
        var tracker = KeepAliveTracker(policy: KeepAlivePolicy(interval: 10, missedPingThreshold: 3))
        _ = tracker.nextPingID()
        _ = tracker.nextPingID()
        tracker.noteInboundTraffic()
        XCTAssertEqual(tracker.health, .healthy)
    }

    func testDisabledPolicyHasNoInterval() {
        XCTAssertNil(KeepAlivePolicy.disabled.interval)
        XCTAssertEqual(KeepAlivePolicy.default.interval, 10)
        XCTAssertEqual(KeepAlivePolicy.default.missedPingThreshold, 3)
    }
}

/// Wiring tests: the conference must actually emit pings on the wire and answer
/// the server's. Uses a short interval so the test stays fast.
final class ConferenceKeepAliveTests: XCTestCase {

    private func config() throws -> BackendConfig {
        try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/KeepAliveRoom")).config
    }

    func testConferenceSendsPingsAfterBind() async throws {
        // Replay the real join far enough to bind, then hold the stream open so
        // the keepalive timer has something to ping on.
        let inbound = try Fixtures.payloads("lukijitsi-join.json", direction: "in")
        let transport = HoldingTransport(inboundFrames: inbound)
        let conference = JitsiConference(
            transport: transport, config: try config(), roomName: "KeepAliveRoom",
            nick: "ka", machineUID: "uid",
            keepAlive: KeepAlivePolicy(interval: 0.05, missedPingThreshold: 3))

        let joinTask = Task { await conference.join() }
        // Give the timer room to fire a few times.
        try await Task.sleep(nanoseconds: 400_000_000)
        let sent = await transport.sent()
        await transport.finish()
        joinTask.cancel()

        let pings = sent.filter { $0.contains("urn:xmpp:ping") }
        XCTAssertFalse(pings.isEmpty, "conference must send XEP-0199 keepalive pings")
        let first = try XCTUnwrap(pings.first)
        XCTAssertTrue(first.contains("type='get'"))
        XCTAssertTrue(first.contains("to='jitsi.luki.org'"))
        XCTAssertTrue(first.contains("id='ka-"))
    }

    func testDisabledPolicySendsNoPings() async throws {
        let inbound = try Fixtures.payloads("lukijitsi-join.json", direction: "in")
        let transport = HoldingTransport(inboundFrames: inbound)
        let conference = JitsiConference(
            transport: transport, config: try config(), roomName: "KeepAliveRoom",
            nick: "ka", machineUID: "uid", keepAlive: .disabled)

        let joinTask = Task { await conference.join() }
        try await Task.sleep(nanoseconds: 300_000_000)
        let sent = await transport.sent()
        await transport.finish()
        joinTask.cancel()

        XCTAssertTrue(sent.filter { $0.contains("urn:xmpp:ping") }.isEmpty,
                      "keepalive disabled must not ping")
    }

    func testRespondsToServerPing() async throws {
        // The server pinging us requires a reply, or it may drop the connection.
        let ping = "<iq type='get' id='server-ping-1' from='jitsi.luki.org' "
            + "to='me@jitsi.luki.org/res' xmlns='jabber:client'>"
            + "<ping xmlns='urn:xmpp:ping'/></iq>"
        let transport = HoldingTransport(inboundFrames: [ping])
        let conference = JitsiConference(
            transport: transport, config: try config(), roomName: "KeepAliveRoom",
            nick: "ka", machineUID: "uid", keepAlive: .disabled)

        let joinTask = Task { await conference.join() }
        try await Task.sleep(nanoseconds: 200_000_000)
        let sent = await transport.sent()
        await transport.finish()
        joinTask.cancel()

        XCTAssertTrue(sent.contains { $0.contains("type='result'") && $0.contains("server-ping-1") },
                      "must answer the server's ping; sent: \(sent)")
    }

    func testPingStanzaParsesAsPingPayload() {
        let xml = "<iq type='get' id='p1' from='jitsi.luki.org' xmlns='jabber:client'>"
            + "<ping xmlns='urn:xmpp:ping'/></iq>"
        guard case let .iq(iq)? = StanzaParser.parse(xml) else {
            return XCTFail("expected an IQ")
        }
        XCTAssertEqual(iq.payload, .ping)
    }
}

/// Like `FakeTransport`, but keeps the inbound stream open after replaying the
/// fixture so time-based behavior (the keepalive timer) can be observed.
actor HoldingTransport: StanzaTransport {
    private let inboundFrames: [String]
    private var sentStanzas: [String] = []

    private let incomingStream: AsyncStream<Data>
    private let incomingContinuation: AsyncStream<Data>.Continuation
    private let stateStream: AsyncStream<ConnectionState>
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    var incoming: AsyncStream<Data> { incomingStream }
    var state: AsyncStream<ConnectionState> { stateStream }

    init(inboundFrames: [String]) {
        self.inboundFrames = inboundFrames
        (incomingStream, incomingContinuation) = AsyncStream.makeStream(of: Data.self)
        (stateStream, stateContinuation) = AsyncStream.makeStream(of: ConnectionState.self)
    }

    func connect() async throws {
        stateContinuation.yield(.connected)
        for frame in inboundFrames { incomingContinuation.yield(Data(frame.utf8)) }
        // Deliberately NOT finished — the connection stays open.
    }

    func send(_ stanza: String) async throws { sentStanzas.append(stanza) }
    func disconnect() async { finish() }
    func sent() -> [String] { sentStanzas }
    func finish() {
        incomingContinuation.finish()
        stateContinuation.finish()
    }
}
