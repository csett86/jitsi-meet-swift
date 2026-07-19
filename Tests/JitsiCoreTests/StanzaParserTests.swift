import XCTest
@testable import JitsiCore

/// Offline regression suite over the committed `docs/fixtures/*.json` captures
/// from jitsi.luki.org. These assert the typed output of `StanzaParser` against
/// real server traffic, including that `session-initiate` is classic Jingle
/// (XEP-0166), not Colibri2.
final class StanzaParserTests: XCTestCase {

    // MARK: - Helpers

    /// All inbound frames of a fixture, parsed to stanzas.
    private func inboundStanzas(_ fixture: String) throws -> [Stanza] {
        let payloads = try Fixtures.payloads(fixture, direction: "in")
        return StanzaParser.parse(frames: payloads)
    }

    private func firstFeatures(_ stanzas: [Stanza]) -> StreamFeatures? {
        for case let .streamFeatures(f) in stanzas { return f }
        return nil
    }

    private func firstIQPayload<T>(_ stanzas: [Stanza], _ transform: (IQPayload) -> T?) -> T? {
        for case let .iq(iq) in stanzas {
            if let value = transform(iq.payload) { return value }
        }
        return nil
    }

    // MARK: - Access probe

    func testAccessProbeAdvertisesAnonymousSASL() throws {
        let stanzas = try inboundStanzas("lukijitsi-access-probe.json")
        let features = try XCTUnwrap(firstFeatures(stanzas))
        XCTAssertTrue(features.supportsAnonymous, "jitsi.luki.org should offer SASL ANONYMOUS")
        XCTAssertEqual(features.saslMechanisms, ["ANONYMOUS"])
    }

    // MARK: - Join flow

    func testStreamFeaturesParsed() throws {
        let stanzas = try inboundStanzas("lukijitsi-join.json")
        let features = try XCTUnwrap(firstFeatures(stanzas))
        XCTAssertTrue(features.supportsAnonymous)
    }

    func testBindResultYieldsJID() throws {
        let stanzas = try inboundStanzas("lukijitsi-join.json")
        let jidString = firstIQPayload(stanzas) { payload -> String? in
            if case let .bind(jid) = payload { return jid }
            return nil
        }
        let bound = try XCTUnwrap(jidString)
        let jid = try XCTUnwrap(JID(bound))
        XCTAssertEqual(jid.domain, "jitsi.luki.org")
        XCTAssertNotNil(jid.resource)
    }

    func testDiscoInfoParsed() throws {
        let stanzas = try inboundStanzas("lukijitsi-join.json")
        let disco = try XCTUnwrap(firstIQPayload(stanzas) { payload -> DiscoInfo? in
            if case let .discoInfo(d) = payload { return d }
            return nil
        })
        // The Prosody server identity and the Jitsi component identities.
        XCTAssertTrue(disco.identities.contains { $0.name == "Prosody" })
        XCTAssertTrue(disco.identities.contains { $0.type == "lobbyrooms" })
        // Advertised features include external-service discovery.
        XCTAssertTrue(disco.hasFeature("urn:xmpp:extdisco:2"))
        XCTAssertTrue(disco.hasFeature("http://jabber.org/protocol/disco#info"))
    }

    func testExternalServicesYieldTURN() throws {
        let stanzas = try inboundStanzas("lukijitsi-join.json")
        let services = try XCTUnwrap(firstIQPayload(stanzas) { payload -> [ExternalService]? in
            if case let .externalServices(s) = payload { return s }
            return nil
        })
        XCTAssertTrue(services.contains { $0.type == "stun" })
        let turn = try XCTUnwrap(services.first { $0.type == "turn" })
        XCTAssertEqual(turn.host, "turn.jitsi.luki.org")
        XCTAssertNotNil(turn.port)
    }

    func testConferenceResponseIsReadyAndAnonymous() throws {
        let stanzas = try inboundStanzas("lukijitsi-join.json")
        let conf = try XCTUnwrap(firstIQPayload(stanzas) { payload -> ConferenceResponse? in
            if case let .conference(c) = payload { return c }
            return nil
        })
        XCTAssertTrue(conf.ready)
        XCTAssertEqual(conf.focusJID, "focus@auth.jitsi.luki.org")
        XCTAssertFalse(conf.authenticationRequired)
    }

    func testSelfPresenceDetected() throws {
        let stanzas = try inboundStanzas("lukijitsi-join.json")
        let selfPresence = stanzas.contains { stanza in
            if case let .presence(p) = stanza { return p.isSelfPresence }
            return false
        }
        XCTAssertTrue(selfPresence, "Expected a MUC self-presence (status 110)")
    }

    // MARK: - Jingle session-initiate (the linchpin finding)

    private func sessionInitiate() throws -> Jingle {
        let stanzas = try inboundStanzas("lukijitsi-join.json")
        let jingle = firstIQPayload(stanzas) { payload -> Jingle? in
            if case let .jingle(j) = payload, j.action == "session-initiate" { return j }
            return nil
        }
        return try XCTUnwrap(jingle, "No session-initiate found in the join fixture")
    }

    func testSessionInitiateIsClassicJingle() throws {
        let jingle = try sessionInitiate()
        // Classic Jingle (XEP-0166): action + sid + separate audio/video contents.
        XCTAssertEqual(jingle.action, "session-initiate")
        XCTAssertFalse(jingle.sid.isEmpty)
        XCTAssertTrue(jingle.initiator?.contains("focus@auth.jitsi.luki.org") ?? false)
        let names = Set(jingle.contents.map(\.name))
        XCTAssertEqual(names, ["audio", "video"])
    }

    func testSessionInitiateAudioOffersOpus() throws {
        let jingle = try sessionInitiate()
        let audio = try XCTUnwrap(jingle.contents.first { $0.name == "audio" })
        XCTAssertEqual(audio.media, "audio")
        let opus = try XCTUnwrap(audio.payloadTypes.first { $0.name == "opus" })
        XCTAssertEqual(opus.clockrate, 48000)
        XCTAssertEqual(opus.channels, 2)
    }

    func testSessionInitiateVideoOffersExpectedCodecs() throws {
        let jingle = try sessionInitiate()
        let video = try XCTUnwrap(jingle.contents.first { $0.name == "video" })
        let codecs = Set(video.payloadTypes.compactMap(\.name))
        XCTAssertTrue(codecs.isSuperset(of: ["VP8", "VP9", "H264", "AV1"]),
                      "Expected VP8/VP9/H264/AV1; got \(codecs)")
    }

    func testSessionInitiateTransportHasICEAndDTLSAndBridgeWebSocket() throws {
        let jingle = try sessionInitiate()
        let audio = try XCTUnwrap(jingle.contents.first { $0.name == "audio" })
        let transport = try XCTUnwrap(audio.transport)
        XCTAssertNotNil(transport.ufrag)
        XCTAssertNotNil(transport.pwd)
        XCTAssertFalse(transport.candidates.isEmpty)

        let fingerprint = try XCTUnwrap(transport.fingerprint)
        XCTAssertEqual(fingerprint.hash, "sha-256")
        XCTAssertEqual(fingerprint.setup, "actpass")

        let ws = try XCTUnwrap(transport.webSocketURL)
        XCTAssertTrue(ws.contains("colibri-ws"), "Expected the JVB colibri bridge WebSocket URL")
    }
}
