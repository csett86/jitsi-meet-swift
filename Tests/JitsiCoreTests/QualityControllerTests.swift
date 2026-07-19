import XCTest
@testable import JitsiCore

final class QualityControllerTests: XCTestCase {

    private let visible9 = (1...9).map { "ep\($0)" }

    func testLowBandwidthCapsLastNAndResolution() {
        let c = QualityController.constraints(visibleEndpoints: visible9, bandwidth: .low)
        XCTAssertEqual(c.lastN, 4)
        XCTAssertEqual(c.defaultMaxHeight, 180)
    }

    func testHighBandwidthAllowsMoreAndHigherStage() {
        let c = QualityController.constraints(visibleEndpoints: visible9, bandwidth: .high)
        XCTAssertEqual(c.lastN, 9)                 // fewer visible than the cap of 20
        XCTAssertEqual(c.onStageMaxHeight, 720)
    }

    func testLastNNeverExceedsVisibleCount() {
        let c = QualityController.constraints(visibleEndpoints: ["a", "b"], bandwidth: .high)
        XCTAssertEqual(c.lastN, 2)
    }

    func testSelectedEndpointsGetStageResolution() {
        let c = QualityController.constraints(visibleEndpoints: visible9,
                                              selectedEndpoints: ["ep1"], bandwidth: .medium)
        XCTAssertEqual(c.perEndpointMaxHeight["ep1"], 540)
        XCTAssertEqual(c.selectedEndpoints, ["ep1"])
    }

    func testSelectedEndpointsAlwaysReceivableEvenBeyondCap() {
        // 10 selected on a low tier (cap 4): lastN must grow to include them all.
        let many = (1...10).map { "sel\($0)" }
        let c = QualityController.constraints(visibleEndpoints: many, selectedEndpoints: many, bandwidth: .low)
        XCTAssertEqual(c.lastN, 10)
    }

    func testColibriMessageJSON() throws {
        let c = QualityController.constraints(visibleEndpoints: (1...9).map { "ep\($0)" },
                                              selectedEndpoints: ["ep1"], bandwidth: .medium)
        let json = c.colibriMessageJSON()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["colibriClass"] as? String, "ReceiverVideoConstraints")
        XCTAssertEqual(object["lastN"] as? Int, 9)
        XCTAssertEqual(object["selectedEndpoints"] as? [String], ["ep1"])
        let defaults = try XCTUnwrap(object["defaultConstraints"] as? [String: Int])
        XCTAssertEqual(defaults["maxHeight"], 360)
        let perEndpoint = try XCTUnwrap(object["constraints"] as? [String: [String: Int]])
        XCTAssertEqual(perEndpoint["ep1"]?["maxHeight"], 540)
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
