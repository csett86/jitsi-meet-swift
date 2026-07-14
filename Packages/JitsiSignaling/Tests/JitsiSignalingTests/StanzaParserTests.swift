import Testing
import Foundation
@testable import JitsiSignaling

// MARK: - Fixture loader

fileprivate struct FixtureFrame: Decodable {
    let seq: Int
    let direction: String
    let data: String
}

fileprivate struct Fixture: Decodable {
    let frames: [FixtureFrame]
}

fileprivate func loadFixture() throws -> Fixture {
    let url = Bundle.module.url(forResource: "Fixtures/alphajitsi-join", withExtension: "json")!
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Fixture.self, from: data)
}

// MARK: - StanzaParser tests (driven by the fixture)

@Suite("StanzaParser — fixture-driven")
struct StanzaParserTests {
    fileprivate var receivedFrames: [FixtureFrame] = []
    fileprivate var sentFrames: [FixtureFrame] = []

    init() throws {
        let fixture = try loadFixture()
        receivedFrames = fixture.frames.filter { $0.direction == "received" }
        sentFrames = fixture.frames.filter { $0.direction == "sent" }
    }

    // MARK: Stream open

    @Test("frame 2 — server stream open parsed correctly")
    func serverStreamOpen() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 2 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .streamOpen(let open) = stanza else {
            Issue.record("Expected .streamOpen, got \(stanza)")
            return
        }
        #expect(open.from == "alpha.jitsi.net")
        #expect(open.id != nil)
    }

    // MARK: Stream features

    @Test("frame 3 — stream features contain ANONYMOUS mechanism")
    func streamFeaturesAnonymous() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 3 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .streamFeatures(let features) = stanza else {
            Issue.record("Expected .streamFeatures, got \(stanza)")
            return
        }
        #expect(features.supportsAnonymous)
        #expect(features.mechanisms.contains("ANONYMOUS"))
    }

    @Test("frame 8 — post-SASL features include bind requirement")
    func postSASLFeatures() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 8 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .streamFeatures(let features) = stanza else {
            Issue.record("Expected .streamFeatures, got \(stanza)")
            return
        }
        #expect(features.bindRequired)
    }

    // MARK: SASL

    @Test("frame 5 — SASL success")
    func saslSuccess() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 5 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .saslSuccess = stanza else {
            Issue.record("Expected .saslSuccess, got \(stanza)")
            return
        }
    }

    // MARK: Bind

    @Test("frame 10 — bind result carries full JID")
    func bindResult() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 10 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .iq(let iq) = stanza else {
            Issue.record("Expected .iq, got \(stanza)")
            return
        }
        #expect(iq.type == .result)
        guard case .bind(let jid) = iq.payload else {
            Issue.record("Expected .bind payload, got \(iq.payload)")
            return
        }
        #expect(jid.contains("@alpha.jitsi.net"))
        #expect(jid.contains("/spike"))
    }

    // MARK: Disco#info

    @Test("frame 15 — server disco#info result has extdisco feature")
    func serverDiscoInfo() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 15 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .iq(let iq) = stanza,
              case .discoInfo(let result) = iq.payload else {
            Issue.record("Expected discoInfo IQ, got \(stanza)")
            return
        }
        #expect(result.supports("urn:xmpp:extdisco:2"))
    }

    @Test("frame 16 — conference disco#info reports MUC support")
    func conferenceDiscoInfo() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 16 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .iq(let iq) = stanza,
              case .discoInfo(let result) = iq.payload else {
            Issue.record("Expected discoInfo IQ, got \(stanza)")
            return
        }
        #expect(result.supports("http://jabber.org/protocol/muc"))
        #expect(result.supports("http://jabber.org/protocol/muc#unique"))
    }

    // MARK: External services

    @Test("frame 17 — external services include STUN and TURN")
    func externalServices() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 17 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .iq(let iq) = stanza,
              case .externalServices(let svcs) = iq.payload else {
            Issue.record("Expected externalServices IQ, got \(stanza)")
            return
        }
        #expect(!svcs.isEmpty)
        #expect(svcs.contains { $0.type == .stun })
        #expect(svcs.contains { $0.type == .turn })
    }

    // MARK: MUC presence

    @Test("frame 21 — self-presence in MUC (status code 110)")
    func selfPresence() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 21 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .presence(let p) = stanza else {
            Issue.record("Expected .presence, got \(stanza)")
            return
        }
        #expect(p.mucUser?.isSelfPresence == true)
        #expect(p.from?.hasPrefix("testroom@conference.alpha.jitsi.net") == true)
    }

    @Test("frame 19 — focus presence parsed as moderator")
    func focusPresence() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 19 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .presence(let p) = stanza else {
            Issue.record("Expected .presence, got \(stanza)")
            return
        }
        #expect(p.from?.hasSuffix("/focus") == true)
        #expect(p.mucUser?.items.first?.role == "moderator")
    }

    @Test("frame 18 — participant presence with Jitsi extensions")
    func participantPresenceExtensions() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 18 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .presence(let p) = stanza else {
            Issue.record("Expected .presence, got \(stanza)")
            return
        }
        #expect(p.from?.hasPrefix("testroom@conference.alpha.jitsi.net/") == true)
        #expect(p.mucUser?.items.first?.role == "moderator")
        #expect(p.mucUser?.items.first?.affiliation == "owner")
    }

    // MARK: Jingle session-initiate

    @Test("frame 25 — session-initiate Jingle IQ")
    func sessionInitiate() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 25 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .iq(let iq) = stanza else {
            Issue.record("Expected IQ stanza, got \(stanza)")
            return
        }
        #expect(iq.type == .set)
        #expect(iq.from?.hasPrefix("testroom@conference.alpha.jitsi.net/") == true)

        guard case .jingle(let jingle) = iq.payload else {
            Issue.record("Expected .jingle payload, got \(iq.payload)")
            return
        }
        #expect(jingle.action == .sessionInitiate)
        #expect(!jingle.sid.isEmpty)
        #expect(jingle.contents.count == 2)

        let audio = try #require(jingle.contents.first { $0.name == "0" })
        #expect(audio.description?.media == "audio")
        #expect(audio.description?.payloadTypes.isEmpty == false)
        #expect(audio.transport?.fingerprint != nil)

        let video = try #require(jingle.contents.first { $0.name == "1" })
        #expect(video.description?.media == "video")

        // BUNDLE group
        #expect(jingle.bundleGroup.contains("0"))
        #expect(jingle.bundleGroup.contains("1"))
    }

    @Test("session-initiate opus payload has correct parameters")
    func opusPayloadParameters() throws {
        let frame = try #require(receivedFrames.first { $0.seq == 25 })
        let stanza = StanzaParser.parse(frame.data)
        guard case .iq(let iq) = stanza,
              case .jingle(let jingle) = iq.payload,
              let audio = jingle.contents.first(where: { $0.name == "0" }),
              let opus = audio.description?.payloadTypes.first(where: { $0.name == "opus" }) else {
            Issue.record("Could not reach opus payload type")
            return
        }
        #expect(opus.id == 111)
        #expect(opus.clockrate == 48000)
        #expect(opus.channels == 2)
        #expect(opus.parameters["minptime"] == "10")
        #expect(opus.parameters["useinbandfec"] == "1")
    }

    // MARK: BackendCapabilities from disco

    @Test("BackendCapabilities built from fixture disco results")
    func backendCapabilities() throws {
        let serverFrame = try #require(receivedFrames.first { $0.seq == 15 })
        let mucFrame = try #require(receivedFrames.first { $0.seq == 16 })

        guard case .iq(let serverIQ) = StanzaParser.parse(serverFrame.data),
              case .discoInfo(let serverInfo) = serverIQ.payload else {
            Issue.record("Could not parse server disco#info")
            return
        }
        guard case .iq(let mucIQ) = StanzaParser.parse(mucFrame.data),
              case .discoInfo(let mucInfo) = mucIQ.payload else {
            Issue.record("Could not parse MUC disco#info")
            return
        }

        let caps = BackendCapabilities(serverInfo: serverInfo, mucInfo: mucInfo)
        #expect(caps.supportsExtdisco)
        #expect(!caps.supportsLobby)
        #expect(!caps.supportsVisitors)
        #expect(!caps.supportsE2EE)
    }

    // MARK: TURNDiscovery helpers

    @Test("TURNDiscovery.uri generates correct URIs")
    func turnDiscoveryURIs() throws {
        let stun = ExternalService(element: XMLElement(
            localName: "service", namespaceURI: XMPPNS.extdisco, qualifiedName: nil,
            attributes: ["type": "stun", "host": "stun.example.com", "port": "3478"],
            children: [], text: ""
        ))
        let turn = ExternalService(element: XMLElement(
            localName: "service", namespaceURI: XMPPNS.extdisco, qualifiedName: nil,
            attributes: ["type": "turn", "host": "turn.example.com", "port": "443", "transport": "tcp"],
            children: [], text: ""
        ))

        #expect(TURNDiscovery.uri(for: stun) == "stun:stun.example.com:3478")
        #expect(TURNDiscovery.uri(for: turn) == "turn:turn.example.com:443?transport=tcp")
    }
}
