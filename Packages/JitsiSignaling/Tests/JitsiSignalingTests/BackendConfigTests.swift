import Testing
import Foundation
@testable import JitsiSignaling

// MARK: - BackendConfig tests

@Suite("BackendConfig parsing")
struct BackendConfigTests {
    @Test("parses alpha.jitsi.net URL correctly")
    func parseAlphaURL() throws {
        let config = try BackendConfig(conferenceURL: "https://alpha.jitsi.net/MyRoom")

        #expect(config.displayName == "MyRoom")
        #expect(config.roomName == "myroom")
        #expect(config.xmppDomain == "alpha.jitsi.net")
        #expect(config.mucDomain == "conference.alpha.jitsi.net")
        #expect(config.authDomain == "auth.alpha.jitsi.net")
        #expect(config.focusUserJID == "focus@auth.alpha.jitsi.net")
        #expect(config.conferenceJID == "myroom@conference.alpha.jitsi.net")
        #expect(config.xmppWebSocketURL.scheme == "wss")
        #expect(config.xmppWebSocketURL.host == "alpha.jitsi.net")
        #expect(config.xmppWebSocketURL.path == "/xmpp-websocket")
    }

    @Test("room name is lowercased")
    func roomNameLowercased() throws {
        let config = try BackendConfig(conferenceURL: "https://alpha.jitsi.net/CamelCaseRoom")
        #expect(config.roomName == "camelcaseroom")
        #expect(config.displayName == "CamelCaseRoom")
    }

    @Test("throws on non-https scheme")
    func throwsOnHTTP() {
        #expect(throws: BackendConfig.ParseError.self) {
            try BackendConfig(conferenceURL: "http://alpha.jitsi.net/Room")
        }
    }

    @Test("throws on missing room name")
    func throwsOnMissingRoom() {
        #expect(throws: BackendConfig.ParseError.self) {
            try BackendConfig(conferenceURL: "https://alpha.jitsi.net/")
        }
    }

    @Test("throws on invalid URL")
    func throwsOnInvalidURL() {
        #expect(throws: BackendConfig.ParseError.self) {
            try BackendConfig(conferenceURL: "not a url")
        }
    }

    @Test("handles meet.jit.si correctly")
    func parseMeetJitSi() throws {
        let config = try BackendConfig(conferenceURL: "https://meet.jit.si/TestRoom")
        #expect(config.xmppDomain == "meet.jit.si")
        #expect(config.mucDomain == "conference.meet.jit.si")
        #expect(config.authDomain == "auth.meet.jit.si")
        #expect(config.focusUserJID == "focus@auth.meet.jit.si")
    }
}
