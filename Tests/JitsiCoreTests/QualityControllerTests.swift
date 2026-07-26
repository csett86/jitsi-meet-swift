import XCTest
@testable import JitsiCore

final class QualityControllerTests: XCTestCase {

    private let visible9 = (1...9).map { "ep\($0)-v0" }

    func testLowBandwidthCapsLastNAndResolution() {
        let c = QualityController.constraints(visibleSources: visible9, bandwidth: .low)
        XCTAssertEqual(c.lastN, 4)
        XCTAssertEqual(c.defaultMaxHeight, 180)
    }

    func testHighBandwidthAllowsMoreAndHigherStage() {
        let c = QualityController.constraints(visibleSources: visible9, bandwidth: .high)
        XCTAssertEqual(c.lastN, 9)                 // fewer visible than the cap of 20
        XCTAssertEqual(c.onStageMaxHeight, 720)
    }

    func testLastNNeverExceedsVisibleCount() {
        let c = QualityController.constraints(visibleSources: ["a", "b"], bandwidth: .high)
        XCTAssertEqual(c.lastN, 2)
    }

    func testSelectedSourcesGetStageResolution() {
        let c = QualityController.constraints(visibleSources: visible9,
                                              selectedSources: ["ep1-v0"], bandwidth: .medium)
        XCTAssertEqual(c.perSourceMaxHeight["ep1-v0"], 540)
        XCTAssertEqual(c.selectedSources, ["ep1-v0"])
    }

    func testSelectedSourcesAlwaysReceivableEvenBeyondCap() {
        // 10 selected on a low tier (cap 4): lastN must grow to include them all.
        let many = (1...10).map { "sel\($0)-v0" }
        let c = QualityController.constraints(visibleSources: many, selectedSources: many, bandwidth: .low)
        XCTAssertEqual(c.lastN, 10)
    }

    func testColibriMessageJSON() throws {
        let c = QualityController.constraints(visibleSources: (1...9).map { "ep\($0)-v0" },
                                              selectedSources: ["ep1-v0"], bandwidth: .medium)
        let json = c.colibriMessageJSON()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["colibriClass"] as? String, "ReceiverVideoConstraints")
        XCTAssertEqual(object["lastN"] as? Int, 9)
        XCTAssertEqual(object["selectedSources"] as? [String], ["ep1-v0"])
        let defaults = try XCTUnwrap(object["defaultConstraints"] as? [String: Int])
        XCTAssertEqual(defaults["maxHeight"], 360)
        let perSource = try XCTUnwrap(object["constraints"] as? [String: [String: Int]])
        XCTAssertEqual(perSource["ep1-v0"]?["maxHeight"], 540)
    }
}

final class DominantSpeakerTests: XCTestCase {

    func testTracksChangesAndHistory() {
        var tracker = DominantSpeakerTracker()
        XCTAssertTrue(tracker.update(to: "alice"))
        XCTAssertEqual(tracker.current, "alice")
        XCTAssertFalse(tracker.update(to: "alice"))   // no change
        XCTAssertTrue(tracker.update(to: "bob"))
        XCTAssertEqual(tracker.current, "bob")
        XCTAssertEqual(tracker.history, ["alice"])
        XCTAssertTrue(tracker.update(to: "carol"))
        XCTAssertEqual(tracker.history, ["bob", "alice"])   // most-recent first
    }

    func testHistoryIsCapped() {
        var tracker = DominantSpeakerTracker(historyLimit: 2)
        for name in ["a", "b", "c", "d"] { tracker.update(to: name) }
        XCTAssertEqual(tracker.current, "d")
        XCTAssertEqual(tracker.history, ["c", "b"])
    }

    func testParsesColibriDominantSpeakerJSON() {
        let json = #"{"colibriClass":"DominantSpeakerEndpointChangeEvent","dominantSpeakerEndpoint":"a1b2c3d4","previousSpeakers":["x"]}"#
        XCTAssertEqual(EndpointMessage.dominantSpeaker(fromJSON: json), "a1b2c3d4")
    }

    func testIgnoresUnrelatedJSON() {
        XCTAssertNil(EndpointMessage.dominantSpeaker(fromJSON: #"{"colibriClass":"EndpointStats"}"#))
        XCTAssertNil(EndpointMessage.dominantSpeaker(fromJSON: "not json"))
    }
}
