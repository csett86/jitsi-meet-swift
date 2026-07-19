import XCTest
@testable import JitsiCore

final class MUCSessionTests: XCTestCase {
    private let room = "room@conference.jitsi.luki.org"

    private func presence(_ nick: String, type: String? = nil, selfCode: Bool = false,
                          role: String? = "participant", jid: String? = nil) -> Presence {
        Presence(
            from: "\(room)/\(nick)",
            type: type,
            occupantID: "occ-\(nick)",
            mucItem: MUCItem(role: role, affiliation: "none", jid: jid),
            statusCodes: selfCode ? [110] : []
        )
    }

    func testJoinUpdateLeaveSequence() {
        var muc = MUCSession()
        XCTAssertEqual(muc.apply(presence("alice", selfCode: true)), .joined(
            Participant(nick: "alice", occupantID: "occ-alice", role: "participant",
                        affiliation: "none", isSelf: true)))
        // Second presence for the same nick is an update, not a re-join.
        if case .updated(let p)? = muc.apply(presence("alice", selfCode: true, role: "moderator")) {
            XCTAssertEqual(p.role, "moderator")
        } else {
            XCTFail("expected .updated")
        }
        // A new nick joins.
        XCTAssertEqual(muc.apply(presence("bob"))?.isJoin, true)
        XCTAssertEqual(muc.participants.count, 2)
        // Leave removes.
        XCTAssertEqual(muc.apply(presence("bob", type: "unavailable"))?.isLeave, true)
        XCTAssertEqual(muc.participants.count, 1)
    }

    func testFocusIsExcluded() {
        var muc = MUCSession()
        XCTAssertNil(muc.apply(presence("focus", role: "moderator")))
        // Also excluded when identified by its real JID.
        XCTAssertNil(muc.apply(Presence(
            from: "\(room)/somenick",
            mucItem: MUCItem(role: "moderator", affiliation: "owner",
                             jid: "focus@auth.jitsi.luki.org/focus"))))
        XCTAssertTrue(muc.participants.isEmpty)
    }

    func testLocalParticipantIsSelf() {
        var muc = MUCSession()
        muc.apply(presence("me", selfCode: true))
        muc.apply(presence("them"))
        XCTAssertEqual(muc.localParticipant?.nick, "me")
        XCTAssertEqual(muc.ordered.first?.nick, "me")   // self sorts first
    }

    func testUnknownLeaveIsIgnored() {
        var muc = MUCSession()
        XCTAssertNil(muc.apply(presence("ghost", type: "unavailable")))
    }
}

private extension RosterChange {
    var isJoin: Bool { if case .joined = self { return true } else { return false } }
    var isLeave: Bool { if case .left = self { return true } else { return false } }
}
