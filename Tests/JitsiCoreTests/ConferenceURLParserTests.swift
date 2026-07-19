import XCTest
@testable import JitsiCore

final class ConferenceURLParserTests: XCTestCase {

    func testBareHostAndRoom() throws {
        let parsed = try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/SomeRoom123"))
        XCTAssertEqual(parsed.roomName, "SomeRoom123")
        XCTAssertEqual(parsed.config.displayName, "jitsi.luki.org")
        XCTAssertEqual(
            parsed.config.xmppWebSocketURL,
            URL(string: "wss://jitsi.luki.org/xmpp-websocket")
        )
        XCTAssertEqual(parsed.config.mucDomain, "conference.jitsi.luki.org")
        XCTAssertEqual(parsed.config.focusJID, "focus.jitsi.luki.org")
    }

    func testFullURL() throws {
        let parsed = try XCTUnwrap(ConferenceURLParser.parse("https://jitsi.luki.org/SomeRoom123"))
        XCTAssertEqual(parsed.roomName, "SomeRoom123")
        XCTAssertEqual(parsed.config.displayName, "jitsi.luki.org")
    }

    func testHTTPSchemeIsAccepted() throws {
        let parsed = try XCTUnwrap(ConferenceURLParser.parse("http://jitsi.luki.org/Room"))
        XCTAssertEqual(parsed.roomName, "Room")
        // The signaling transport is always wss regardless of the pasted scheme.
        XCTAssertEqual(
            parsed.config.xmppWebSocketURL,
            URL(string: "wss://jitsi.luki.org/xmpp-websocket")
        )
    }

    func testTrailingSlash() throws {
        let parsed = try XCTUnwrap(ConferenceURLParser.parse("https://jitsi.luki.org/SomeRoom123/"))
        XCTAssertEqual(parsed.roomName, "SomeRoom123")
    }

    func testPercentEncodedRoom() throws {
        let parsed = try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/My%20Room"))
        XCTAssertEqual(parsed.roomName, "My Room")
    }

    func testLeadingAndTrailingWhitespace() throws {
        let parsed = try XCTUnwrap(ConferenceURLParser.parse("   jitsi.luki.org/Room   \n"))
        XCTAssertEqual(parsed.roomName, "Room")
        XCTAssertEqual(parsed.config.displayName, "jitsi.luki.org")
    }

    func testMultiTenantPathTakesLastSegment() throws {
        // Multi-tenant deployments use /<tenant>/<room>; v1 keeps the room only.
        let parsed = try XCTUnwrap(ConferenceURLParser.parse("https://meet.example.com/tenant/Room42"))
        XCTAssertEqual(parsed.roomName, "Room42")
        XCTAssertEqual(parsed.config.mucDomain, "conference.meet.example.com")
    }

    func testMissingRoomReturnsNil() {
        XCTAssertNil(ConferenceURLParser.parse("jitsi.luki.org"))
        XCTAssertNil(ConferenceURLParser.parse("https://jitsi.luki.org"))
        XCTAssertNil(ConferenceURLParser.parse("https://jitsi.luki.org/"))
    }

    func testMissingHostReturnsNil() {
        XCTAssertNil(ConferenceURLParser.parse("https:///Room"))
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(ConferenceURLParser.parse(""))
        XCTAssertNil(ConferenceURLParser.parse("    "))
        XCTAssertNil(ConferenceURLParser.parse("\n\t"))
    }

    func testRoomNameCaseIsPreserved() throws {
        let parsed = try XCTUnwrap(ConferenceURLParser.parse("jitsi.luki.org/CamelCaseRoom"))
        XCTAssertEqual(parsed.roomName, "CamelCaseRoom")
    }
}
