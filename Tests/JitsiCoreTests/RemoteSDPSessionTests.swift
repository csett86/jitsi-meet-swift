import XCTest
@testable import JitsiCore

/// The receive path: remote participants' SSRCs (announced with `source-add`)
/// have to become one receive-only m-section each, or their audio and video
/// never arrive. Driven by the committed multi-party fixture.
final class RemoteSDPSessionTests: XCTestCase {

    private func jingles() throws -> [Jingle] {
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("multiparty-sources.json",
                                                                       direction: "in"))
        var out: [Jingle] = []
        for case let .iq(iq) in stanzas {
            if case let .jingle(j) = iq.payload { out.append(j) }
        }
        return out
    }

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

    // MARK: - Track grouping

    func testSimulcastLayersCollapseIntoOneTrack() throws {
        var manager = SourceManager()
        manager.apply(try jingles()[0])     // endpoint A: audio 1001, video SIM 2001/2002/2003

        let tracks = manager.tracks
        XCTAssertEqual(tracks.count, 2, "audio + one video track, not one per SSRC")

        let video = try XCTUnwrap(tracks.first { $0.kind == "video" })
        XCTAssertEqual(video.endpointID, "a1b2c3d4")
        XCTAssertEqual(video.primarySSRC, "2001")
        XCTAssertEqual(video.ssrcs, ["2001", "2002", "2003"])
        XCTAssertEqual(video.msid, "a1b2c3d4-video-0 a1b2c3d4-video-0-1")

        let audio = try XCTUnwrap(tracks.first { $0.kind == "audio" })
        XCTAssertEqual(audio.ssrcs, ["1001"])
    }

    func testBridgeOwnSourcesAreNotTracks() throws {
        var manager = SourceManager()
        manager.apply(try jingles()[0])
        // The JVB's own jvb-a0/jvb-v0 placeholders are in the session-initiate.
        var withBridge = manager
        withBridge.apply(Jingle(action: "session-initiate", sid: "s", initiator: nil, responder: nil,
                                contents: [JingleContent(
                                    name: "audio", senders: "both", media: "audio",
                                    payloadTypes: [], headerExtensions: [],
                                    sources: [Source(ssrc: "999", name: "jvb-a0", owner: "jvb",
                                                     parameters: [:])],
                                    sourceGroups: [], transport: nil, rtcpMux: true)]))
        XCTAssertEqual(withBridge.tracks.count, manager.tracks.count)
    }

    // MARK: - Section lifecycle

    func testEachTrackGetsItsOwnStableMid() throws {
        let all = try jingles()
        var manager = SourceManager()
        var session = RemoteSDPSession(offer: try offer())

        manager.apply(all[0])
        XCTAssertTrue(session.sync(tracks: manager.tracks))
        let firstMids = session.sections.map(\.mid)
        XCTAssertEqual(firstMids.count, 2)

        manager.apply(all[1])                       // a second participant joins
        XCTAssertTrue(session.sync(tracks: manager.tracks))
        XCTAssertEqual(session.sections.count, 4)
        XCTAssertEqual(Array(session.sections.map(\.mid).prefix(2)), firstMids,
                       "existing sections keep their mid — Unified Plan forbids renumbering")
        XCTAssertEqual(Set(session.sections.map(\.mid)).count, 4, "mids are unique")

        // Idempotent: re-syncing the same tracks is not a renegotiation.
        XCTAssertFalse(session.sync(tracks: manager.tracks))
    }

    func testRemovedTrackLeavesAnInactiveTombstone() throws {
        let all = try jingles()
        var manager = SourceManager()
        var session = RemoteSDPSession(offer: try offer())
        manager.apply(all[0])
        session.sync(tracks: manager.tracks)
        let videoMid = try XCTUnwrap(session.sections.first { $0.kind == "video" }?.mid)

        manager.apply(all[2])                       // endpoint A turns the camera off
        XCTAssertTrue(session.sync(tracks: manager.tracks))
        XCTAssertEqual(session.sections.count, 2, "the section stays, only its track is gone")
        XCTAssertNil(session.sections.first { $0.mid == videoMid }?.track)
        XCTAssertNil(session.endpoint(forMid: videoMid))

        let sdp = session.sdp()
        XCTAssertTrue(sdp.contains("a=mid:\(videoMid)\r\na=inactive"))
        XCTAssertFalse(sdp.contains("a=ssrc:2001"))
    }

    func testVersionIncrementsOnlyOnChange() throws {
        var manager = SourceManager()
        var session = RemoteSDPSession(offer: try offer())
        XCTAssertTrue(session.sdp().contains("o=- 0 2 IN IP4"))

        manager.apply(try jingles()[0])
        session.sync(tracks: manager.tracks)
        XCTAssertTrue(session.sdp().contains("o=- 0 3 IN IP4"))
        session.sync(tracks: manager.tracks)
        XCTAssertTrue(session.sdp().contains("o=- 0 3 IN IP4"), "no change, no new offer version")
    }

    // MARK: - Generated SDP

    func testReceiveSectionsAreSendonlyBundledAndCarryTheirSSRCs() throws {
        var manager = SourceManager()
        manager.apply(try jingles()[0])
        var session = RemoteSDPSession(offer: try offer())
        session.sync(tracks: manager.tracks)
        let sdp = session.sdp()
        let lines = sdp.components(separatedBy: "\r\n")

        // Two offered sections (our own audio/video) plus one per remote track.
        XCTAssertEqual(lines.filter { $0.hasPrefix("m=") }.count, 4)

        let bundle = try XCTUnwrap(lines.first { $0.hasPrefix("a=group:BUNDLE") })
        for mid in ["audio", "video"] + session.sections.map(\.mid) {
            XCTAssertTrue(bundle.contains(" \(mid)"), "\(mid) missing from \(bundle)")
        }

        let videoMid = try XCTUnwrap(session.sections.first { $0.kind == "video" }?.mid)
        XCTAssertTrue(sdp.contains("a=mid:\(videoMid)\r\na=sendonly"),
                      "the bridge sends, we receive")
        // The simulcast layers stay one track.
        XCTAssertTrue(sdp.contains("a=ssrc-group:SIM 2001 2002 2003"))
        XCTAssertTrue(sdp.contains("a=ssrc:2003 msid:a1b2c3d4-video-0 a1b2c3d4-video-0-1"))
        // Codecs and header extensions are inherited from the offered section.
        XCTAssertTrue(sdp.contains("a=rtpmap:100 VP8/90000"))
        // ICE/DTLS is repeated per section (all bundled onto one transport), but
        // candidates are not — they belong to the bundle tag.
        XCTAssertEqual(lines.filter { $0.hasPrefix("a=ice-ufrag:") }.count, 4)
        XCTAssertEqual(lines.filter { $0.hasPrefix("a=candidate:") }.count, 6)
    }

    /// WebRTC encodes with the first payload type of the section, so the codec we
    /// send is whichever one the deployment announced first in its
    /// `session-initiate` — its own preference order (AV1 on jitsi.luki.org). We
    /// do not second-guess it.
    func testSendSectionKeepsTheJVBsAnnouncedCodecOrder() throws {
        let sdp = SDPBuilder.offer(from: try offer())
        XCTAssertTrue(sdp.contains("m=video 9 UDP/TLS/RTP/SAVPF 41 100 107 101"),
                      "the offered payload-type order must survive untouched")
        XCTAssertTrue(sdp.contains("m=audio 9 UDP/TLS/RTP/SAVPF 111 126"))
    }

    /// The override exists for pinning a codec while debugging interop.
    func testSendCodecCanBePinned() throws {
        let sdp = SDPBuilder.offer(from: try offer(), sendVideoCodec: "H264")
        let videoLine = try XCTUnwrap(sdp.components(separatedBy: "\r\n")
            .first { $0.hasPrefix("m=video") })
        XCTAssertTrue(videoLine.hasSuffix("SAVPF 107 41 100 101"), "got \(videoLine)")
        // Nothing is dropped — we can still receive AV1/VP8/VP9.
        for payload in ["41", "100", "101"] {
            XCTAssertTrue(sdp.contains("a=rtpmap:\(payload) "), "lost payload \(payload)")
        }
        // An unknown codec leaves the offered order alone rather than breaking it.
        let untouched = SDPBuilder.offer(from: try offer(), sendVideoCodec: "VP42")
        XCTAssertTrue(untouched.contains("m=video 9 UDP/TLS/RTP/SAVPF 41 100 107 101"))
    }

    func testMidMapsBackToTheParticipant() throws {
        let all = try jingles()
        var manager = SourceManager()
        manager.apply(all[0])
        manager.apply(all[1])
        var session = RemoteSDPSession(offer: try offer())
        session.sync(tracks: manager.tracks)

        for section in session.sections {
            XCTAssertEqual(session.endpoint(forMid: section.mid), section.endpointID)
            XCTAssertEqual(session.kind(forMid: section.mid), section.kind)
        }
        XCTAssertEqual(Set(session.sections.map(\.endpointID)), ["a1b2c3d4", "e5f6a7b8"])
        XCTAssertNil(session.endpoint(forMid: "video"), "the offered sections are ours, not a peer's")
    }
}
