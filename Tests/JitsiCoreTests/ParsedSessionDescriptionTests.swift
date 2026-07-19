import XCTest
@testable import JitsiCore

final class ParsedSessionDescriptionTests: XCTestCase {

    private func sessionInitiate() throws -> Jingle {
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("lukijitsi-join.json", direction: "in"))
        for case let .iq(iq) in stanzas {
            if case let .jingle(j) = iq.payload, j.action == "session-initiate" { return j }
        }
        throw XCTSkip("no session-initiate in fixture")
    }

    func testNormalizesJingleIntoMediaAgnosticDescription() throws {
        let sdp = ParsedSessionDescription(jingle: try sessionInitiate())
        XCTAssertFalse(sdp.sid.isEmpty)
        XCTAssertEqual(sdp.media.count, 2)
        XCTAssertNotNil(sdp.audio)
        XCTAssertNotNil(sdp.video)
        XCTAssertEqual(sdp.audio?.kind, "audio")
    }

    func testCarriesBridgeWebSocketURL() throws {
        let sdp = ParsedSessionDescription(jingle: try sessionInitiate())
        let ws = try XCTUnwrap(sdp.bridgeWebSocketURL)
        XCTAssertTrue(ws.contains("colibri-ws"))
    }

    func testTransportPreservedForMediaLayer() throws {
        let sdp = ParsedSessionDescription(jingle: try sessionInitiate())
        let audioTransport = try XCTUnwrap(sdp.audio?.transport)
        XCTAssertNotNil(audioTransport.ufrag)
        XCTAssertNotNil(audioTransport.pwd)
        XCTAssertEqual(audioTransport.fingerprint?.hash, "sha-256")
        XCTAssertFalse(audioTransport.candidates.isEmpty)
    }

    func testCodecNamesExposed() throws {
        let sdp = ParsedSessionDescription(jingle: try sessionInitiate())
        XCTAssertEqual(sdp.audio?.codecNames.contains("opus"), true)
        XCTAssertTrue(Set(sdp.video?.codecNames ?? []).isSuperset(of: ["VP8", "VP9", "H264", "AV1"]))
    }
}
