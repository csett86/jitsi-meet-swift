import XCTest
@testable import JitsiCore

/// The send path: what the other participants need in order to actually receive
/// *our* camera and microphone — source-name signaling in the `session-accept`,
/// SSRC grouping, and mute state, which Jitsi carries in MUC presence rather
/// than in the media session.
final class SendPathTests: XCTestCase {

    private func offer() throws -> ParsedSessionDescription {
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("lukijitsi-join.json",
                                                                       direction: "in"))
        for case let .iq(iq) in stanzas {
            if case let .jingle(j) = iq.payload, j.action == "session-initiate" {
                return ParsedSessionDescription(jingle: j)
            }
        }
        throw XCTSkip("no session-initiate in the fixture")
    }

    /// A local answer as WebRTC produces it for a camera + mic, with an RTX
    /// stream grouped onto the video SSRC.
    private let answerSDP = """
    v=0\r
    o=- 1 2 IN IP4 127.0.0.1\r
    s=-\r
    t=0 0\r
    a=ice-ufrag:localufrag\r
    a=ice-pwd:localpwd\r
    a=fingerprint:sha-256 AA:BB\r
    a=setup:active\r
    m=audio 9 UDP/TLS/RTP/SAVPF 111\r
    a=mid:audio\r
    a=ssrc:11111 cname:localcname\r
    a=ssrc:11111 msid:stream0 audio0\r
    m=video 9 UDP/TLS/RTP/SAVPF 100 96\r
    a=mid:video\r
    a=ssrc-group:FID 22222 33333\r
    a=ssrc:22222 cname:localcname\r
    a=ssrc:22222 msid:stream0 video0\r
    a=ssrc:33333 cname:localcname\r
    a=ssrc:33333 msid:stream0 video0\r
    """

    func testAnswerParserKeepsSSRCGroups() {
        let parsed = SDPAnswerParser.parse(answerSDP)
        XCTAssertEqual(parsed.media.count, 2)
        XCTAssertEqual(parsed.media[0].ssrcGroups, [])
        XCTAssertEqual(parsed.media[1].ssrcGroups,
                       [SourceGroup(semantics: "FID", ssrcs: ["22222", "33333"])])
    }

    func testSessionAcceptCarriesJitsiSourceNamesAndGroups() throws {
        let xml = JingleBuilder.sessionAccept(
            sid: "abc", to: "room@conference.jitsi.luki.org/focus", id: "iq-1",
            initiator: "focus@auth.jitsi.luki.org/focus", responder: "me@jitsi.luki.org/res",
            offer: try offer(), local: SDPAnswerParser.parse(answerSDP), endpointID: "swift-7f3a")

        // Source-name signaling: the focus maps our SSRCs to us through these.
        XCTAssertTrue(xml.contains("<source ssrc='11111' name='swift-7f3a-a0'"))
        XCTAssertTrue(xml.contains("<source ssrc='22222' name='swift-7f3a-v0'"))
        // Every SSRC of one track shares the track's name — including RTX.
        XCTAssertTrue(xml.contains("<source ssrc='33333' name='swift-7f3a-v0'"))
        XCTAssertTrue(xml.contains("<ssrc-group semantics='FID' xmlns='urn:xmpp:jingle:apps:rtp:ssma:0'>"
                                   + "<source ssrc='22222'/><source ssrc='33333'/></ssrc-group>"))
        XCTAssertTrue(xml.contains("<parameter name='msid' value='stream0 video0'/>"))
    }

    func testSourceNamesFollowTheJitsiConvention() {
        XCTAssertEqual(JingleBuilder.sourceName(endpointID: "abcd1234", kind: "audio"), "abcd1234-a0")
        XCTAssertEqual(JingleBuilder.sourceName(endpointID: "abcd1234", kind: "video"), "abcd1234-v0")
    }

    func testMutePublishesPresence() async throws {
        let config = try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/Room")).config
        let transport = FakeTransport(
            inboundFrames: try Fixtures.payloads("lukijitsi-join.json", direction: "in"))
        let conference = JitsiConference(transport: transport, config: config,
                                         roomName: "Room", nick: "me", machineUID: "uid")
        await conference.join()

        // The join presence says we are live.
        let sentAtJoin = await transport.sent()
        let joined = try XCTUnwrap(sentAtJoin.first { $0.contains("<presence to=") })
        XCTAssertTrue(joined.contains(">false</audiomuted>"))

        // Per-source state, or other clients never request our camera at all.
        XCTAssertTrue(joined.contains(#"<SourceInfo>{"me-a0":{"muted":false},"#
                                      + #""me-v0":{"muted":false,"videoType":"camera"}}</SourceInfo>"#),
                      "presence must advertise our sources: \(joined)")

        await conference.setMuted(audio: true, video: false)
        let sentAfterMute = await transport.sent()
        let last = try XCTUnwrap(sentAfterMute.last)
        XCTAssertTrue(last.contains(">true</audiomuted>"), "mic mute must be published: \(last)")
        XCTAssertTrue(last.contains(">false</videomuted>"))
    }

    func testEndpointIDIsTheNick() {
        let config = BackendConfig(displayName: "x",
                                   xmppWebSocketURL: URL(string: "wss://x/xmpp-websocket")!,
                                   mucDomain: "conference.x", focusJID: "focus.x")
        let conference = JitsiConference(transport: FakeTransport(inboundFrames: []),
                                         config: config, roomName: "r", nick: "swift-7f3a")
        XCTAssertEqual(conference.endpointID, "swift-7f3a")
    }
}
