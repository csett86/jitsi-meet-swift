import XCTest
@testable import JitsiCore

final class TURNDiscoveryTests: XCTestCase {

    func testStunHasNoCredentials() {
        let services = [ExternalService(type: "stun", host: "turn.example.org", port: 3478,
                                        transport: nil, username: nil, password: nil,
                                        restricted: nil, expires: nil)]
        let servers = TURNDiscovery.iceServers(from: services)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].urls, ["stun:turn.example.org:3478"])
        XCTAssertNil(servers[0].username)
        XCTAssertNil(servers[0].credential)
    }

    func testTurnCarriesCredentialsAndTransport() {
        let services = [ExternalService(type: "turn", host: "turn.example.org", port: 443,
                                        transport: "tcp", username: "user", password: "pass",
                                        restricted: true, expires: nil)]
        let servers = TURNDiscovery.iceServers(from: services)
        XCTAssertEqual(servers[0].urls, ["turn:turn.example.org:443?transport=tcp"])
        XCTAssertEqual(servers[0].username, "user")
        XCTAssertEqual(servers[0].credential, "pass")
    }

    func testUnknownTypeDropped() {
        let services = [ExternalService(type: "sip", host: "x", port: nil, transport: nil,
                                        username: nil, password: nil, restricted: nil, expires: nil)]
        XCTAssertTrue(TURNDiscovery.iceServers(from: services).isEmpty)
    }

    func testDerivedFromFixtureExtdisco() throws {
        // The real extdisco response from jitsi.luki.org.
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("lukijitsi-join.json", direction: "in"))
        var services: [ExternalService] = []
        for case let .iq(iq) in stanzas {
            if case let .externalServices(s) = iq.payload { services = s }
        }
        let servers = TURNDiscovery.iceServers(from: services)
        XCTAssertTrue(servers.contains { $0.urls.contains("stun:turn.jitsi.luki.org:3478") })
        XCTAssertTrue(servers.contains { server in
            server.urls.contains { $0.hasPrefix("turn:turn.jitsi.luki.org") && $0.contains("transport=") }
        })
    }
}

final class BackendCapabilitiesTests: XCTestCase {

    func testDerivedFromFixtureDisco() throws {
        let stanzas = StanzaParser.parse(frames: try Fixtures.payloads("lukijitsi-join.json", direction: "in"))
        var disco: DiscoInfo?
        for case let .iq(iq) in stanzas where iq.type == "result" {
            if case let .discoInfo(d) = iq.payload { disco = d }
        }
        let caps = BackendCapabilities(disco: try XCTUnwrap(disco))
        XCTAssertTrue(caps.supportsLobby)
        XCTAssertTrue(caps.supportsBreakoutRooms)
        XCTAssertTrue(caps.supportsPolls)
        XCTAssertTrue(caps.supportsAVModeration)
        XCTAssertTrue(caps.supportsSpeakerStats)
        XCTAssertFalse(caps.supportsVisitors)   // signaled via conference response, not disco
    }

    func testEmptyDiscoYieldsNoCapabilities() {
        let caps = BackendCapabilities(disco: DiscoInfo(identities: [], features: []))
        XCTAssertFalse(caps.supportsLobby)
        XCTAssertFalse(caps.supportsPolls)
    }
}
