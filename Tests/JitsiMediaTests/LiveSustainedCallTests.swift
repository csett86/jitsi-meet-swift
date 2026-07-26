#if os(macOS)
import XCTest
import WebRTC
@testable import JitsiCore
@testable import JitsiMedia

/// [MAC][CLOUD-LIVE] Diagnostic + regression test for the "call dies after
/// 60–95s" issue.
///
/// A sustained two-party call, instrumented with a single timestamped timeline
/// covering **every** channel that could explain the drop:
///   * XMPP stanzas in/out and transport state (via a tee transport)
///   * the colibri bridge socket open/close (close code)
///   * ICE connection state
///
/// Run it on macOS CI to decide whether the drop is environmental (a particular
/// home network / power management) or reproducible anywhere:
/// ```sh
/// JITSI_LIVE_TESTS=1 swift test --filter testLiveSustainedCallSurvives
/// ```
/// Courtesy (docs/live-testing.md): 2 clients, one dedicated room, on demand,
/// duration bounded by `JITSI_CALL_SECONDS` (default 150s).
final class LiveSustainedCallTests: XCTestCase {

    // MARK: - Timeline

    /// Thread-safe timestamped event log — the actual deliverable of this test.
    final class Timeline: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(TimeInterval, String)] = []
        private let start = Date()

        func record(_ message: String) {
            let t = Date().timeIntervalSince(start)
            lock.lock(); entries.append((t, message)); lock.unlock()
            // Stream it too, so a hung/timed-out run still shows progress in CI.
            print(String(format: "[%7.1fs] %@", t, message))
            fflush(stdout)
        }

        func dump(_ title: String) {
            lock.lock(); let all = entries; lock.unlock()
            print("\n===== \(title) =====")
            for (t, m) in all { print(String(format: "[%7.1fs] %@", t, m)) }
            print("===== end =====\n")
            fflush(stdout)
        }

        var summary: [(TimeInterval, String)] {
            lock.lock(); defer { lock.unlock() }; return entries
        }
    }

    /// A `StanzaTransport` decorator that tees every frame and state change into
    /// the timeline, so XMPP activity can be correlated with ICE/bridge events.
    actor TeeTransport: StanzaTransport {
        private let inner: URLSessionStanzaTransport
        private let timeline: Timeline
        private let label: String

        private let incomingStream: AsyncStream<Data>
        private let incomingContinuation: AsyncStream<Data>.Continuation
        private let stateStream: AsyncStream<ConnectionState>
        private let stateContinuation: AsyncStream<ConnectionState>.Continuation
        private var pumps: [Task<Void, Never>] = []

        var incoming: AsyncStream<Data> { incomingStream }
        var state: AsyncStream<ConnectionState> { stateStream }

        init(url: URL, timeline: Timeline, label: String) {
            self.inner = URLSessionStanzaTransport(url: url)
            self.timeline = timeline
            self.label = label
            (incomingStream, incomingContinuation) = AsyncStream.makeStream(of: Data.self)
            (stateStream, stateContinuation) = AsyncStream.makeStream(of: ConnectionState.self)
        }

        func connect() async throws {
            let innerIncoming = await inner.incoming
            let innerState = await inner.state
            let timeline = self.timeline
            let label = self.label
            let incomingContinuation = self.incomingContinuation
            let stateContinuation = self.stateContinuation

            pumps.append(Task {
                for await data in innerIncoming {
                    let text = String(decoding: data, as: UTF8.self)
                    timeline.record("\(label) XMPP <- \(Self.describe(text))")
                    incomingContinuation.yield(data)
                }
                timeline.record("\(label) XMPP inbound stream ENDED")
                incomingContinuation.finish()
            })
            pumps.append(Task {
                for await s in innerState {
                    timeline.record("\(label) XMPP state: \(s)")
                    stateContinuation.yield(s)
                }
                stateContinuation.finish()
            })
            try await inner.connect()
        }

        func send(_ stanza: String) async throws {
            timeline.record("\(label) XMPP -> \(Self.describe(stanza))")
            try await inner.send(stanza)
        }

        func disconnect() async {
            for pump in pumps { pump.cancel() }
            await inner.disconnect()
        }

        /// Compact one-line description of a stanza (full XML is far too noisy).
        static func describe(_ xml: String) -> String {
            let name = xml.drop(while: { $0 != "<" }).dropFirst()
                .prefix(while: { !$0.isWhitespace && $0 != ">" && $0 != "/" })
            var bits = [String(name)]
            for attr in ["type", "action", "id"] {
                if let v = value(of: attr, in: xml) { bits.append("\(attr)=\(v)") }
            }
            if xml.contains("urn:xmpp:ping") { bits.append("PING") }
            return bits.joined(separator: " ") + " (\(xml.count)B)"
        }

        private static func value(of attr: String, in xml: String) -> String? {
            for quote in ["'", "\""] {
                let needle = "\(attr)=\(quote)"
                if let r = xml.range(of: needle) {
                    let rest = xml[r.upperBound...]
                    if let end = rest.firstIndex(of: Character(quote)) {
                        return String(rest[..<end])
                    }
                }
            }
            return nil
        }
    }

    // MARK: - Test

    private var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["JITSI_LIVE_TESTS"] == "1"
    }
    private var callSeconds: TimeInterval {
        TimeInterval(ProcessInfo.processInfo.environment["JITSI_CALL_SECONDS"] ?? "") ?? 150
    }
    func testLiveSustainedCallSurvives() async throws {
        try XCTSkipUnless(liveEnabled, "Set JITSI_LIVE_TESTS=1 to run the sustained live call.")

        let timeline = Timeline()
        let base = ProcessInfo.processInfo.environment["JITSI_TEST_URL"]
            ?? "https://jitsi.luki.org/jitsimeetswiftsustained"
        let room = base + String(UUID().uuidString.prefix(6)).lowercased()
        let parsed = try XCTUnwrap(ConferenceURLParser.parse(room))
        timeline.record("room=\(parsed.roomName) duration=\(callSeconds)s "
                        + "(keepalive is always on: \(KeepAlivePolicy.default.interval)s)")

        // Primary: real media + full instrumentation.
        let primary = JitsiConference(
            transport: TeeTransport(url: parsed.config.xmppWebSocketURL, timeline: timeline, label: "A"),
            config: parsed.config, roomName: parsed.roomName, nick: "swiftsustain-a")
        let factory = PeerConnectionFactory()
        let localMedia = LocalMediaSource(factory: factory.factory)
        let call = ConferenceCall(conference: primary, factory: factory, localMedia: localMedia)

        // Secondary: signaling-only, present so Jicofo offers primary media.
        let secondary = JitsiConference(
            transport: URLSessionStanzaTransport(url: parsed.config.xmppWebSocketURL),
            config: parsed.config, roomName: parsed.roomName, nick: "swiftsustain-b")

        // --- instrumentation -------------------------------------------------
        let connected = expectation(description: "ICE connected")
        connected.assertForOverFulfill = false
        let dropped = expectation(description: "ICE dropped")
        dropped.assertForOverFulfill = false
        dropped.isInverted = true          // we WANT this never to fulfill

        let iceStates = IceLog()
        call.onIceStateChange = { state in
            timeline.record("ICE state: \(Self.describeICE(state))")
            iceStates.append(state)
            if state == .connected || state == .completed { connected.fulfill() }
            if state == .disconnected || state == .failed || state == .closed { dropped.fulfill() }
        }
        call.onBridgeOpen = { timeline.record("BRIDGE open (colibri wss handshake ok)") }
        call.onBridgeClose = { code in timeline.record("BRIDGE CLOSED code=\(code)") }
        call.onBridgeMessage = { text in timeline.record("BRIDGE <- \(text.prefix(160))") }
        call.onDominantSpeaker = { ep in timeline.record("dominant speaker: \(ep)") }
        call.onRemoteMediaTrack = { remote in
            timeline.record("remote \(remote.kind) track from \(remote.endpointID) (mid \(remote.mid))")
        }
        call.onError = { message in timeline.record("MEDIA ERROR: \(message)") }

        // A `session-terminate` is Jicofo legitimately ending the session (e.g.
        // once everyone else has left). ICE going down afterwards is then the
        // correct consequence, not the bug — the bug is ICE dying *without* one.
        let terminated = Terminated()
        call.onSessionTerminated = { reason in
            timeline.record("SESSION TERMINATED by focus, reason=\(reason ?? "none")")
            terminated.set()
        }

        // --- run -------------------------------------------------------------
        let callTask = Task { await call.run() }
        let primaryJoin = Task { await primary.join() }
        let secondaryJoin = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await secondary.join()
        }

        await fulfillment(of: [connected], timeout: 60)
        timeline.record("*** ICE CONNECTED — holding the call for \(Int(callSeconds))s ***")

        // Hold the call open and see whether it survives.
        await fulfillment(of: [dropped], timeout: callSeconds)
        timeline.record("*** hold finished — final ICE: \(Self.describeICE(iceStates.last)) ***")

        callTask.cancel(); secondaryJoin.cancel(); primaryJoin.cancel()
        await secondary.leave()
        await primary.leave()
        call.close()

        timeline.dump("SUSTAINED CALL TIMELINE (room \(parsed.roomName))")

        // The assertion: the call must still be up, UNLESS the focus explicitly
        // ended the session (which is correct server behaviour). On failure the
        // timeline shows exactly which channel died first (XMPP / bridge / ICE).
        let states = iceStates.all
        let iceDropped = states.contains(.disconnected) || states.contains(.failed)
        if terminated.value {
            timeline.record("NOTE: focus terminated the session — ICE teardown after that is expected")
        } else {
            XCTAssertFalse(iceDropped,
                           "ICE dropped with no session-terminate — see the timeline for what died "
                           + "first. States: " + states.map(Self.describeICE).joined(separator: " -> "))
        }
        // Either way the peer must not have vanished on us mid-hold: a
        // session-terminate this early means the other participant was lost,
        // which is the failure mode this test exists to catch.
        XCTAssertFalse(terminated.value,
                       "The focus terminated the session during the hold — the other participant "
                       + "was lost (see the timeline for its `presence type=unavailable`).")
    }

    /// Thread-safe one-shot flag.
    final class Terminated: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func set() { lock.lock(); flag = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }

    /// Small lock-guarded log of ICE states (callbacks arrive off the main thread).
    final class IceLog: @unchecked Sendable {
        private let lock = NSLock()
        private var states: [RTCIceConnectionState] = []
        func append(_ s: RTCIceConnectionState) { lock.lock(); states.append(s); lock.unlock() }
        var all: [RTCIceConnectionState] { lock.lock(); defer { lock.unlock() }; return states }
        var last: RTCIceConnectionState { all.last ?? .new }
    }

    static func describeICE(_ state: RTCIceConnectionState) -> String {
        switch state {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }
}
#endif
