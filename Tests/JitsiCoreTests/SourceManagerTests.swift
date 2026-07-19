import XCTest
@testable import JitsiCore

/// Drives `SourceManager` with the committed synthetic multi-party fixture
/// (source-add / source-remove) parsed by `StanzaParser`.
final class SourceManagerTests: XCTestCase {

    private func jingles() throws -> [Jingle] {
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("multiparty-sources.json", direction: "in"))
        var out: [Jingle] = []
        for case let .iq(iq) in stanzas {
            if case let .jingle(j) = iq.payload { out.append(j) }
        }
        return out
    }

    func testSourceAddBuildsSSRCToParticipantMapping() throws {
        let all = try jingles()
        var manager = SourceManager()

        // Frame 0: endpoint A joins (audio 1001 + simulcast video 2001/2002/2003).
        let addA = manager.apply(all[0])
        XCTAssertEqual(addA.count, 4)
        XCTAssertEqual(manager.endpoint(forSSRC: "1001"), "a1b2c3d4")
        XCTAssertEqual(manager.endpoint(forSSRC: "2002"), "a1b2c3d4")
        XCTAssertEqual(manager.ssrcs(for: "a1b2c3d4"), ["1001", "2001", "2002", "2003"])
        XCTAssertEqual(manager.sources["1001"]?.media, "audio")
        XCTAssertEqual(manager.sources["2001"]?.media, "video")
        XCTAssertEqual(manager.sources["1001"]?.msid, "a1b2c3d4-audio-0 a1b2c3d4-audio-0-1")

        // Frame 1: endpoint B joins (audio 1003 + video 3001).
        manager.apply(all[1])
        XCTAssertEqual(manager.participantEndpoints, ["a1b2c3d4", "e5f6a7b8"])
        XCTAssertEqual(manager.endpoint(forSSRC: "3001"), "e5f6a7b8")
    }

    func testSourceRemoveDropsOnlyRemovedSSRCs() throws {
        let all = try jingles()
        var manager = SourceManager()
        manager.apply(all[0])
        manager.apply(all[1])

        // Frame 2: endpoint A turns camera off — video SSRCs removed, audio stays.
        let removed = manager.apply(all[2])
        XCTAssertEqual(Set(removed.map { if case let .removed(s) = $0 { return s.ssrc } else { return "" } }),
                       ["2001", "2002", "2003"])
        XCTAssertNil(manager.endpoint(forSSRC: "2001"))
        XCTAssertEqual(manager.endpoint(forSSRC: "1001"), "a1b2c3d4")  // audio kept
        XCTAssertEqual(manager.ssrcs(for: "a1b2c3d4"), ["1001"])
    }

    func testRemoveEndpointDropsAllTheirSources() throws {
        let all = try jingles()
        var manager = SourceManager()
        manager.apply(all[0])
        manager.apply(all[1])

        let removed = manager.removeEndpoint("e5f6a7b8")
        XCTAssertEqual(removed.count, 2)
        XCTAssertEqual(manager.participantEndpoints, ["a1b2c3d4"])
        XCTAssertTrue(manager.ssrcs(for: "e5f6a7b8").isEmpty)
    }

    func testBridgeSourcesAreFlaggedNotParticipants() throws {
        // The real session-initiate carries jvb-owned sources.
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("lukijitsi-join.json", direction: "in"))
        var manager = SourceManager()
        for case let .iq(iq) in stanzas {
            if case let .jingle(j) = iq.payload, j.action == "session-initiate" { manager.apply(j) }
        }
        XCTAssertFalse(manager.sources.isEmpty)
        XCTAssertTrue(manager.sources.values.allSatisfy(\.isBridge))
        XCTAssertTrue(manager.participantEndpoints.isEmpty)  // jvb only, no participants yet
    }

    func testDuplicateSourceAddIsNotDoubleCounted() throws {
        let all = try jingles()
        var manager = SourceManager()
        manager.apply(all[0])
        let again = manager.apply(all[0])   // replayed
        XCTAssertTrue(again.isEmpty)
    }
}
