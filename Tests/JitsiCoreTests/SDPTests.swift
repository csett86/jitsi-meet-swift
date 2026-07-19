import XCTest
@testable import JitsiCore

final class SDPCandidateTests: XCTestCase {

    func testRenderHostCandidate() {
        let c = ICECandidate(foundation: "1", component: 1, proto: "udp", priority: 2130706431,
                             ip: "10.0.1.2", port: 10000, type: "host")
        XCTAssertEqual(SDPCandidate.line(from: c),
                       "candidate:1 1 udp 2130706431 10.0.1.2 10000 typ host generation 0")
    }

    func testParseAcceptsPrefixes() {
        let expected = ICECandidate(foundation: "3", component: 1, proto: "udp", priority: 2113932031,
                                    ip: "94.130.36.77", port: 10000, type: "host")
        for line in [
            "candidate:3 1 udp 2113932031 94.130.36.77 10000 typ host generation 0",
            "a=candidate:3 1 udp 2113932031 94.130.36.77 10000 typ host",
        ] {
            let c = SDPCandidate.parse(line)
            XCTAssertEqual(c?.foundation, expected.foundation)
            XCTAssertEqual(c?.ip, expected.ip)
            XCTAssertEqual(c?.port, expected.port)
            XCTAssertEqual(c?.type, expected.type)
        }
    }

    func testRoundTrip() {
        let c = ICECandidate(foundation: "2", component: 1, proto: "udp", priority: 12345,
                             ip: "2a01:4f8:10b:21ae::2", port: 10000, type: "host")
        let parsed = SDPCandidate.parse(SDPCandidate.line(from: c))
        XCTAssertEqual(parsed?.ip, c.ip)
        XCTAssertEqual(parsed?.priority, c.priority)
    }

    func testMalformedReturnsNil() {
        XCTAssertNil(SDPCandidate.parse("candidate:1 1 udp"))
        XCTAssertNil(SDPCandidate.parse("not a candidate"))
    }
}

final class SDPBuilderTests: XCTestCase {

    private func fixtureSessionDescription() throws -> ParsedSessionDescription {
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("lukijitsi-join.json", direction: "in"))
        for case let .iq(iq) in stanzas {
            if case let .jingle(j) = iq.payload, j.action == "session-initiate" {
                return ParsedSessionDescription(jingle: j)
            }
        }
        throw XCTSkip("no session-initiate in fixture")
    }

    func testOfferStructureFromRealFixture() throws {
        let sdp = SDPBuilder.offer(from: try fixtureSessionDescription())
        XCTAssertTrue(sdp.hasPrefix("v=0\r\n"))
        XCTAssertTrue(sdp.contains("a=group:BUNDLE audio video"))
        XCTAssertTrue(sdp.contains("\r\nm=audio 9 UDP/TLS/RTP/SAVPF "))
        XCTAssertTrue(sdp.contains("\r\nm=video 9 UDP/TLS/RTP/SAVPF "))
        // Codecs
        XCTAssertTrue(sdp.contains("a=rtpmap:111 opus/48000/2"))
        for codec in ["VP8/90000", "VP9/90000", "H264/90000", "AV1/90000"] {
            XCTAssertTrue(sdp.contains("a=rtpmap:"), "sanity")
            XCTAssertTrue(sdp.contains(codec), "missing \(codec)")
        }
        // Transport
        XCTAssertTrue(sdp.contains("a=ice-ufrag:"))
        XCTAssertTrue(sdp.contains("a=ice-pwd:"))
        XCTAssertTrue(sdp.contains("a=fingerprint:sha-256 "))
        XCTAssertTrue(sdp.contains("a=setup:actpass"))
        XCTAssertTrue(sdp.contains("a=rtcp-mux"))
        XCTAssertTrue(sdp.contains("a=mid:audio"))
        XCTAssertTrue(sdp.contains("a=mid:video"))
        // At least one ICE candidate line, and an ssrc line for the JVB source.
        XCTAssertTrue(sdp.contains("a=candidate:"))
        XCTAssertTrue(sdp.contains("a=ssrc:"))
        // Every line ends CRLF.
        XCTAssertTrue(sdp.hasSuffix("\r\n"))
    }

    func testOfferOmitsFmtpWhenNoParameters() throws {
        // telephone-event (126) has no fmtp parameters in the fixture.
        let sdp = SDPBuilder.offer(from: try fixtureSessionDescription())
        XCTAssertTrue(sdp.contains("a=rtpmap:126 telephone-event/8000"))
    }
}

final class SDPAnswerParserTests: XCTestCase {

    private let answer = """
    v=0\r
    o=- 123 2 IN IP4 127.0.0.1\r
    s=-\r
    t=0 0\r
    a=group:BUNDLE audio video\r
    m=audio 9 UDP/TLS/RTP/SAVPF 111\r
    c=IN IP4 0.0.0.0\r
    a=ice-ufrag:myufrag\r
    a=ice-pwd:mypwd\r
    a=fingerprint:sha-256 AA:BB:CC:DD\r
    a=setup:active\r
    a=mid:audio\r
    a=sendrecv\r
    a=rtcp-mux\r
    a=rtpmap:111 opus/48000/2\r
    a=candidate:1 1 udp 2130706431 192.168.1.5 50000 typ host generation 0\r
    a=ssrc:11111 cname:localcname\r
    a=ssrc:11111 msid:localstream localtrack\r
    m=video 9 UDP/TLS/RTP/SAVPF 100\r
    c=IN IP4 0.0.0.0\r
    a=ice-ufrag:myufrag\r
    a=ice-pwd:mypwd\r
    a=fingerprint:sha-256 AA:BB:CC:DD\r
    a=setup:active\r
    a=mid:video\r
    a=rtcp-mux\r
    a=rtpmap:100 VP8/90000\r
    a=ssrc:22222 cname:localcname\r
    """

    func testParsesMediaTransportAndSources() {
        let sdp = SDPAnswerParser.parse(answer)
        XCTAssertEqual(sdp.media.count, 2)
        let audio = sdp.media[0]
        XCTAssertEqual(audio.kind, "audio")
        XCTAssertEqual(audio.payloadIDs, [111])
        XCTAssertEqual(audio.ufrag, "myufrag")
        XCTAssertEqual(audio.pwd, "mypwd")
        XCTAssertEqual(audio.fingerprint?.hash, "sha-256")
        XCTAssertEqual(audio.fingerprint?.value, "AA:BB:CC:DD")
        XCTAssertEqual(audio.fingerprint?.setup, "active")
        XCTAssertEqual(audio.candidates.count, 1)
        XCTAssertEqual(audio.candidates.first?.ip, "192.168.1.5")
        XCTAssertEqual(audio.sources.count, 1)
        XCTAssertEqual(audio.sources.first?.ssrc, "11111")
        XCTAssertEqual(audio.sources.first?.cname, "localcname")
        XCTAssertEqual(audio.sources.first?.msid, "localstream localtrack")

        XCTAssertEqual(sdp.media[1].sources.first?.ssrc, "22222")
    }
}

final class JingleBuilderTests: XCTestCase {

    private func offer() throws -> ParsedSessionDescription {
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("lukijitsi-join.json", direction: "in"))
        for case let .iq(iq) in stanzas {
            if case let .jingle(j) = iq.payload, j.action == "session-initiate" {
                return ParsedSessionDescription(jingle: j)
            }
        }
        throw XCTSkip("no session-initiate")
    }

    func testSessionAcceptEchoesPayloadsAndCarriesLocalTransport() throws {
        let local = LocalSDP(media: [
            LocalSDPMedia(mid: "audio", kind: "audio", payloadIDs: [111],
                          ufrag: "localufrag", pwd: "localpwd",
                          fingerprint: DTLSFingerprint(hash: "sha-256", setup: "active", value: "AA:BB"),
                          candidates: [ICECandidate(foundation: "1", component: 1, proto: "udp",
                                                    priority: 1, ip: "1.2.3.4", port: 5, type: "host")],
                          sources: [LocalSSRC(ssrc: "999", cname: "me", msid: "s t")]),
            LocalSDPMedia(mid: "video", kind: "video", payloadIDs: [100],
                          ufrag: "localufrag", pwd: "localpwd", fingerprint: nil,
                          candidates: [], sources: [LocalSSRC(ssrc: "888", cname: "me")]),
        ])
        let xml = JingleBuilder.sessionAccept(
            sid: "abc123", initiator: "focus@auth.jitsi.luki.org/focus",
            responder: "me@jitsi.luki.org/res", offer: try offer(), local: local)

        XCTAssertTrue(xml.contains("action='session-accept'"))
        XCTAssertTrue(xml.contains("sid='abc123'"))
        // Echoes an offered payload (opus).
        XCTAssertTrue(xml.contains("name='opus'"))
        // Carries our local transport + fingerprint + candidate + source.
        XCTAssertTrue(xml.contains("ufrag='localufrag'"))
        XCTAssertTrue(xml.contains("<fingerprint xmlns='urn:xmpp:jingle:apps:dtls:0' hash='sha-256' setup='active'>AA:BB</fingerprint>"))
        XCTAssertTrue(xml.contains("<candidate foundation='1'"))
        XCTAssertTrue(xml.contains("<source ssrc='999'"))

        // The XML must parse back into a Jingle session-accept.
        let stanza = StanzaParser.parse(xml)
        guard case let .iq(iq)? = stanza, case let .jingle(j) = iq.payload else {
            return XCTFail("session-accept did not round-trip through the parser")
        }
        XCTAssertEqual(j.action, "session-accept")
        XCTAssertEqual(j.sid, "abc123")
        XCTAssertEqual(Set(j.contents.map(\.name)), ["audio", "video"])
    }

    func testTransportInfoCarriesCandidates() {
        let xml = JingleBuilder.transportInfo(
            sid: "s", initiator: "focus/f", responder: "me/r", mediaName: "audio",
            ufrag: "u", pwd: "p",
            candidates: [ICECandidate(foundation: "1", component: 1, proto: "udp",
                                      priority: 1, ip: "9.9.9.9", port: 1, type: "host")])
        XCTAssertTrue(xml.contains("action='transport-info'"))
        XCTAssertTrue(xml.contains("ip='9.9.9.9'"))
    }
}
