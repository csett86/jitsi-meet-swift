//
//  JitsiSignalingTests.swift
//  JitsiSignalingTests
//
//  Created for Jitsi Native macOS Client
//

import XCTest
@testable import JitsiSignaling

class JitsiSignalingTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testBackendConfigAlpha() {
        let config = BackendConfig.alpha
        
        XCTAssertEqual(config.displayName, "alpha.jitsi.net")
        XCTAssertEqual(config.xmppWebSocketURL.absoluteString, "wss://alpha.jitsi.net/xmpp-websocket")
        XCTAssertEqual(config.mucDomain, "conference.alpha.jitsi.net")
        XCTAssertEqual(config.focusJID, "focus.alpha.jitsi.net")
        XCTAssertNil(config.anonymousDomain)
        XCTAssertNil(config.jwtToken)
    }
    
    func testXMPPStanzaTypes() {
        let parser = XMPPStanzaParser()
        
        // Test stream open
        let streamOpenXML = "<?xml version='1.0'?><stream:stream xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:client' from='server' id='1' version='1.0'>"
        var stanzaType: StanzaType?
        parser.onStanza = { stanza in
            stanzaType = stanza.type
        }
        parser.parse(string: streamOpenXML)
        XCTAssertEqual(stanzaType, .streamOpen)
        
        // Test presence
        let presenceXML = "<presence from='user@domain' to='contact@domain'><show>away</show></presence>"
        parser.parse(string: presenceXML)
        XCTAssertEqual(stanzaType, .presence)
        
        // Test IQ
        let iqXML = "<iq type='get' id='1' from='user@domain'><query xmlns='jabber:iq:roster'/></iq>"
        parser.parse(string: iqXML)
        XCTAssertEqual(stanzaType, .iq)
        
        // Test message
        let messageXML = "<message from='user@domain' to='contact@domain'><body>Hello</body></message>"
        parser.parse(string: messageXML)
        XCTAssertEqual(stanzaType, .message)
    }
    
    func testXMPPConnectionState() {
        // Test that we can create a connection
        let url = URL(string: "wss://alpha.jitsi.net/xmpp-websocket")!
        let connection = XMPPWebSocketConnection(websocketURL: url)
        
        XCTAssertEqual(connection.state, .disconnected)
    }
    
    func testSASLMechanism() {
        XCTAssertEqual(SASLMechanism.anonymous.rawValue, "ANONYMOUS")
        XCTAssertEqual(SASLMechanism.plain.rawValue, "PLAIN")
        XCTAssertEqual(SASLMechanism.scramSHA1.rawValue, "SCRAM-SHA-1")
    }
    
    func testJingleAction() {
        XCTAssertEqual(JingleAction.sessionInitiate.rawValue, "session-initiate")
        XCTAssertEqual(JingleAction.sessionAccept.rawValue, "session-accept")
        XCTAssertEqual(JingleAction.sessionTerminate.rawValue, "session-terminate")
    }
    
    func testJingleSender() {
        XCTAssertEqual(JingleSender.both.rawValue, "both")
        XCTAssertEqual(JingleSender.initiator.rawValue, "initiator")
        XCTAssertEqual(JingleSender.responder.rawValue, "responder")
        XCTAssertEqual(JingleSender.none.rawValue, "none")
    }
    
    func testColibriConferenceType() {
        XCTAssertEqual(ColibriConferenceType.audio.rawValue, "audio")
        XCTAssertEqual(ColibriConferenceType.video.rawValue, "video")
    }
    
    func testPresenceShow() {
        XCTAssertEqual(PresenceShow.away.rawValue, "away")
        XCTAssertEqual(PresenceShow.chat.rawValue, "chat")
        XCTAssertEqual(PresenceShow.dnd.rawValue, "dnd")
        XCTAssertEqual(PresenceShow.xa.rawValue, "xa")
    }
    
    func testPresenceType() {
        XCTAssertEqual(PresenceType.available.rawValue, "available")
        XCTAssertEqual(PresenceType.unavailable.rawValue, "unavailable")
    }
    
    func testIQType() {
        XCTAssertEqual(IQType.get.rawValue, "get")
        XCTAssertEqual(IQType.set.rawValue, "set")
        XCTAssertEqual(IQType.result.rawValue, "result")
        XCTAssertEqual(IQType.error.rawValue, "error")
    }
    
    func testMessageType() {
        XCTAssertEqual(MessageType.normal.rawValue, "normal")
        XCTAssertEqual(MessageType.chat.rawValue, "chat")
        XCTAssertEqual(MessageType.groupchat.rawValue, "groupchat")
        XCTAssertEqual(MessageType.headline.rawValue, "headline")
        XCTAssertEqual(MessageType.error.rawValue, "error")
    }
    
    func testMUCRole() {
        XCTAssertEqual(MUCRole.none.rawValue, "none")
        XCTAssertEqual(MUCRole.visitor.rawValue, "visitor")
        XCTAssertEqual(MUCRole.participant.rawValue, "participant")
        XCTAssertEqual(MUCRole.moderator.rawValue, "moderator")
    }
    
    func testMUCAffiliation() {
        XCTAssertEqual(MUCAffiliation.none.rawValue, "none")
        XCTAssertEqual(MUCAffiliation.member.rawValue, "member")
        XCTAssertEqual(MUCAffiliation.admin.rawValue, "admin")
        XCTAssertEqual(MUCAffiliation.owner.rawValue, "owner")
    }
    
    func testICECandidateToSDP() {
        let candidate = ICECandidate(
            component: 1,
            foundation: "1",
            generation: 0,
            id: "1",
            ip: "192.168.1.100",
            network: 1,
            port: 50000,
            priority: 2130706431,
            protocolType: "udp",
            type: "host"
        )
        
        let sdp = candidate.toSDP()
        XCTAssertTrue(sdp.contains("1 1 udp 2130706431 192.168.1.100 50000"))
        XCTAssertTrue(sdp.contains("typ host"))
        XCTAssertTrue(sdp.contains("generation 0"))
        XCTAssertTrue(sdp.contains("network-id 1"))
    }
    
    func testSessionDescription() {
        let jingleSession = JingleSession(
            action: .sessionInitiate,
            initiator: "focus@auth.alpha.jitsi.net/focus",
            sid: "abc123"
        )
        
        let colibriContent = ColibriContent(
            from: "focus@auth.alpha.jitsi.net/focus",
            conferences: []
        )
        
        let sessionDescription = SessionDescription(
            jingleSession: jingleSession,
            colibriContent: colibriContent,
            ssrcMappings: [123456789: "endpoint1"]
        )
        
        XCTAssertNotNil(sessionDescription.jingleSession)
        XCTAssertNotNil(sessionDescription.colibriContent)
        XCTAssertEqual(sessionDescription.ssrcMappings.count, 1)
        XCTAssertEqual(sessionDescription.ssrcMappings[123456789], "endpoint1")
    }
}
