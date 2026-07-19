#if os(macOS)
import XCTest
import WebRTC
@testable import JitsiMedia
import JitsiCore

/// [MAC] Phase 2 local verification (docs/mac-runbook.md, item 1 + the local half
/// of item 2). These exercise a **real** `RTCPeerConnection` on Apple hardware —
/// the one thing the Linux/cloud agent cannot do — but need no live server and no
/// camera/mic capture: only WebRTC's SDP negotiation engine.
///
///   1. `SDPBuilder.offer` (derived from the JVB's classic-Jingle
///      `session-initiate` fixture) is *accepted* by `setRemoteDescription`.
///      This is the runbook's flagged riskiest point — mids and fmtp lines.
///   2. Driving the shipping `MediaSession.accept()` through `createAnswer`
///      produces a Jingle `session-accept` that round-trips through the parser.
///      (Whether the JVB accepts it still needs a live call — see mac-signoff.)
final class SDPAcceptanceTests: XCTestCase {

    // Locate the committed capture relative to this source file, same as the
    // JitsiCore FixtureLoader — one source of truth, no bundled copies.
    private static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // JitsiMediaTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("docs/fixtures", isDirectory: true)
    }

    private struct Frame: Codable { let direction: String; let payload: String }

    private func fixtureOffer() throws -> ParsedSessionDescription {
        let url = Self.fixturesDir.appendingPathComponent("lukijitsi-join.json")
        let frames = try JSONDecoder().decode([Frame].self, from: try Data(contentsOf: url))
        let stanzas = StanzaParser.parse(frames: frames.filter { $0.direction == "in" }.map(\.payload))
        for case let .iq(iq) in stanzas {
            if case let .jingle(j) = iq.payload, j.action == "session-initiate" {
                return ParsedSessionDescription(jingle: j)
            }
        }
        throw XCTSkip("no session-initiate in fixture")
    }

    private func makePeerConnection(_ factory: PeerConnectionFactory) throws -> RTCPeerConnection {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return try XCTUnwrap(factory.factory.peerConnection(with: config, constraints: constraints, delegate: nil))
    }

    /// Runbook Phase 2, item 1 — the riskiest integration point, pinpointed.
    func testRealPeerConnectionAcceptsOfferSDP() throws {
        let offer = try fixtureOffer()
        let factory = PeerConnectionFactory()
        let pc = try makePeerConnection(factory)
        defer { pc.close() }

        let remote = SessionDescriptionMapper.remoteOffer(from: offer)
        let exp = expectation(description: "setRemoteDescription")
        var setError: Error?
        pc.setRemoteDescription(remote) { error in setError = error; exp.fulfill() }
        wait(for: [exp], timeout: 10)

        XCTAssertNil(setError,
            "real RTCPeerConnection rejected SDPBuilder.offer: \(String(describing: setError))")
        XCTAssertEqual(pc.remoteDescription?.type, .offer)
        // Both BUNDLEd m-sections and their mids survive into WebRTC's own view.
        let sdp = pc.remoteDescription?.sdp ?? ""
        XCTAssertTrue(sdp.contains("m=audio"), "audio m-line lost")
        XCTAssertTrue(sdp.contains("m=video"), "video m-line lost")
        XCTAssertTrue(sdp.contains("a=mid:audio"), "audio mid lost")
        XCTAssertTrue(sdp.contains("a=mid:video"), "video mid lost")
    }

    /// Runbook Phase 2, item 2 (local half) — drive the actual shipping
    /// `MediaSession.accept()` code path (set remote → add tracks → createAnswer →
    /// setLocal), then build the `session-accept` the way `JitsiConference` does
    /// and confirm it round-trips with our real ICE/DTLS + SSRCs.
    func testMediaSessionAnswerBuildsRoundTrippableSessionAccept() throws {
        let offer = try fixtureOffer()
        let factory = PeerConnectionFactory()
        let local = LocalMediaSource(factory: factory.factory)   // tracks only; no startCapture()
        let session = MediaSession(factory: factory.factory, localMedia: local)

        let exp = expectation(description: "onLocalAnswer")
        var answer: LocalSDP?
        session.onLocalAnswer = { sdp in answer = sdp; exp.fulfill() }
        session.accept(offer: offer, iceServers: [])
        wait(for: [exp], timeout: 15)
        session.close()

        let localSDP = try XCTUnwrap(answer, "MediaSession.accept did not surface a local answer")
        // Our real answer describes both bundled media with DTLS fingerprints.
        XCTAssertEqual(Set(localSDP.media.map(\.kind)), ["audio", "video"])
        XCTAssertNotNil(localSDP.media.first?.fingerprint, "answer should carry a DTLS fingerprint")

        // Build the accept exactly as JitsiConference.acceptSession would.
        let xml = JingleBuilder.sessionAccept(
            sid: offer.sid, to: "room@conference.jitsi.luki.org/focus", id: "iq-1",
            initiator: offer.initiator ?? "", responder: "me@jitsi.luki.org/res",
            offer: offer, local: localSDP)
        let stanza = StanzaParser.parse(xml)
        guard case let .iq(iq)? = stanza, case let .jingle(j) = iq.payload else {
            return XCTFail("session-accept did not round-trip through the parser")
        }
        XCTAssertEqual(j.action, "session-accept")
        XCTAssertEqual(Set(j.contents.map(\.name)), ["audio", "video"])
    }
}
#endif
