//
//  StanzaParserTests.swift
//  JitsiSignalingTests
//
//  Created for Jitsi Native macOS Client
//

import XCTest
@testable import JitsiSignaling

class StanzaParserTests: XCTestCase {
    
    func testParsePresence() {
        let xml = """
        <presence from='testroom123@conference.alpha.jitsi.net/Participant1' 
                  to='user@alpha.jitsi.net/resource' 
                  xmlns='jabber:client'>
          <show>away</show>
          <status>Be right back</status>
          <video-type xmlns='http://jitsi.org/protocol/videotype'>camera</video-type>
          <region xmlns='http://jitsi.org/protocol/region'>global</region>
          <stats-id xmlns='http://jitsi.org/protocol/stats'>stats123</stats-id>
          <dominant-speaker xmlns='http://jitsi.org/protocol/dominantspeaker'/>
        </presence>
        """
        
        let presence = StanzaParser.parsePresence(from: xml)
        
        XCTAssertNotNil(presence)
        XCTAssertEqual(presence?.show, .away)
        XCTAssertEqual(presence?.status, "Be right back")
        XCTAssertEqual(presence?.videoType, "camera")
        XCTAssertEqual(presence?.region, "global")
        XCTAssertEqual(presence?.statsId, "stats123")
        XCTAssertTrue(presence?.isDominantSpeaker ?? false)
    }
    
    func testParsePresenceWithChatShow() {
        let xml = """
        <presence from='user@domain/resource' xmlns='jabber:client'>
          <show>chat</show>
        </presence>
        """
        
        let presence = StanzaParser.parsePresence(from: xml)
        
        XCTAssertNotNil(presence)
        XCTAssertEqual(presence?.show, .chat)
    }
    
    func testParsePresenceWithDNDShow() {
        let xml = """
        <presence from='user@domain/resource' xmlns='jabber:client'>
          <show>dnd</show>
        </presence>
        """
        
        let presence = StanzaParser.parsePresence(from: xml)
        
        XCTAssertNotNil(presence)
        XCTAssertEqual(presence?.show, .dnd)
    }
    
    func testParseIQ() {
        let xml = """
        <iq type='set' id='jingle_1' from='focus@auth.alpha.jitsi.net/focus' to='user@alpha.jitsi.net/resource'>
          <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate'/>
        </iq>
        """
        
        let iq = StanzaParser.parseIQ(from: xml)
        
        XCTAssertNotNil(iq)
        XCTAssertEqual(iq?.type, .set)
        XCTAssertEqual(iq?.id, "jingle_1")
        XCTAssertEqual(iq?.from, "focus@auth.alpha.jitsi.net/focus")
        XCTAssertEqual(iq?.to, "user@alpha.jitsi.net/resource")
    }
    
    func testParseIQResult() {
        let xml = """
        <iq type='result' id='bind_1' to='user@alpha.jitsi.net/resource'>
          <bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'>
            <jid>user@alpha.jitsi.net/resource</jid>
          </bind>
        </iq>
        """
        
        let iq = StanzaParser.parseIQ(from: xml)
        
        XCTAssertNotNil(iq)
        XCTAssertEqual(iq?.type, .result)
        XCTAssertEqual(iq?.id, "bind_1")
    }
    
    func testParseMessage() {
        let xml = """
        <message type='groupchat' from='testroom123@conference.alpha.jitsi.net/Participant1' to='user@alpha.jitsi.net/resource'>
          <body>Hello everyone!</body>
        </message>
        """
        
        let message = StanzaParser.parseMessage(from: xml)
        
        XCTAssertNotNil(message)
        XCTAssertEqual(message?.type, .groupchat)
        XCTAssertEqual(message?.body, "Hello everyone!")
        XCTAssertEqual(message?.from, "testroom123@conference.alpha.jitsi.net/Participant1")
        XCTAssertEqual(message?.to, "user@alpha.jitsi.net/resource")
    }
    
    func testParseMessageWithSubject() {
        let xml = """
        <message type='groupchat' from='testroom123@conference.alpha.jitsi.net/Participant1'>
          <subject>Meeting Topic</subject>
          <body>Let's discuss the topic</body>
        </message>
        """
        
        let message = StanzaParser.parseMessage(from: xml)
        
        XCTAssertNotNil(message)
        XCTAssertEqual(message?.subject, "Meeting Topic")
        XCTAssertEqual(message?.body, "Let's discuss the topic")
    }
    
    func testParseMessageChatType() {
        let xml = """
        <message type='chat' from='user@domain/resource'>
          <body>Private message</body>
        </message>
        """
        
        let message = StanzaParser.parseMessage(from: xml)
        
        XCTAssertNotNil(message)
        XCTAssertEqual(message?.type, .chat)
    }
}
