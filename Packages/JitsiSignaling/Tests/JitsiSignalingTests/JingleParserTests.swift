//
//  JingleParserTests.swift
//  JitsiSignalingTests
//
//  Created for Jitsi Native macOS Client
//

import XCTest
@testable import JitsiSignaling

class JingleParserTests: XCTestCase {
    
    func testParseJingleSessionInitiate() {
        let xml = """
        <iq type='set' id='jingle_1' from='focus@auth.alpha.jitsi.net/focus' to='user@alpha.jitsi.net/resource'>
          <jingle xmlns='urn:xmpp:jingle:1' 
                  action='session-initiate' 
                  initiator='focus@auth.alpha.jitsi.net/focus' 
                  sid='abc123def456'>
            <content creator='initiator' name='audio' senders='both'>
              <description xmlns='urn:xmpp:jingle:apps:rtp:1' media='audio'/>
              <transport xmlns='urn:xmpp:jingle:transports:ice-udp:1' 
                         ufrag='abc123' 
                         pwd='def456' 
                         fingerprint='SHA-1 ABCDEF1234567890ABCDEF1234567890ABCDEF12' 
                         fingerprint-algorithm='sha-1'>
                <candidate component='1' foundation='1' generation='0' id='1' 
                           ip='1.2.3.4' network='1' port='10000' 
                           priority='2130706431' protocol='udp' type='host'/>
              </transport>
            </content>
          </jingle>
        </iq>
        """
        
        let session = JingleParser.parseSession(from: xml)
        
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.action, .sessionInitiate)
        XCTAssertEqual(session?.initiator, "focus@auth.alpha.jitsi.net/focus")
        XCTAssertEqual(session?.sid, "abc123def456")
        XCTAssertEqual(session?.contents.count, 1)
        
        let content = session?.contents.first
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.name, "audio")
        XCTAssertEqual(content?.senders, .both)
        XCTAssertEqual(content?.creator, "initiator")
        
        XCTAssertNotNil(content?.description)
        XCTAssertEqual(content?.description?.media, "audio")
        
        XCTAssertNotNil(content?.transport)
        XCTAssertEqual(content?.transport?.ufrag, "abc123")
        XCTAssertEqual(content?.transport?.pwd, "def456")
        XCTAssertEqual(content?.transport?.fingerprintAlgorithm, "sha-1")
        
        XCTAssertEqual(content?.transport?.candidates.count, 1)
        let candidate = content?.transport?.candidates.first
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.component, 1)
        XCTAssertEqual(candidate?.ip, "1.2.3.4")
        XCTAssertEqual(candidate?.port, 10000)
        XCTAssertEqual(candidate?.protocolType, "udp")
        XCTAssertEqual(candidate?.type, "host")
    }
    
    func testParseJingleSessionWithMultipleContents() {
        let xml = """
        <iq type='set' id='jingle_1' from='focus@auth.alpha.jitsi.net/focus' to='user@alpha.jitsi.net/resource'>
          <jingle xmlns='urn:xmpp:jingle:1' 
                  action='session-initiate' 
                  initiator='focus@auth.alpha.jitsi.net/focus' 
                  sid='abc123def456'>
            <content creator='initiator' name='audio' senders='both'>
              <description xmlns='urn:xmpp:jingle:apps:rtp:1' media='audio'/>
            </content>
            <content creator='initiator' name='video' senders='both'>
              <description xmlns='urn:xmpp:jingle:apps:rtp:1' media='video'/>
            </content>
          </jingle>
        </iq>
        """
        
        let session = JingleParser.parseSession(from: xml)
        
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.contents.count, 2)
        
        let audioContent = session?.contents.first(where: { $0.name == "audio" })
        XCTAssertNotNil(audioContent)
        XCTAssertEqual(audioContent?.description?.media, "audio")
        
        let videoContent = session?.contents.first(where: { $0.name == "video" })
        XCTAssertNotNil(videoContent)
        XCTAssertEqual(videoContent?.description?.media, "video")
    }
    
    func testParseICECandidate() {
        let xml = """
        <candidate component='1' foundation='1' generation='0' id='1' 
                   ip='192.168.1.100' network='1' port='50000' 
                   priority='2130706431' protocol='udp' type='host'/
        """
        
        let candidate = JingleParser.parseCandidate(from: xml)
        
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.component, 1)
        XCTAssertEqual(candidate?.foundation, "1")
        XCTAssertEqual(candidate?.generation, 0)
        XCTAssertEqual(candidate?.id, "1")
        XCTAssertEqual(candidate?.ip, "192.168.1.100")
        XCTAssertEqual(candidate?.network, 1)
        XCTAssertEqual(candidate?.port, 50000)
        XCTAssertEqual(candidate?.priority, 2130706431)
        XCTAssertEqual(candidate?.protocolType, "udp")
        XCTAssertEqual(candidate?.type, "host")
    }
    
    func testParseICECandidateSRFLX() {
        let xml = """
        <candidate component='1' foundation='2' generation='0' id='2' 
                   ip='10.0.0.1' network='1' port='50001' 
                   priority='16777215' protocol='udp' type='srflx'/
        """
        
        let candidate = JingleParser.parseCandidate(from: xml)
        
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.type, "srflx")
        XCTAssertEqual(candidate?.ip, "10.0.0.1")
        XCTAssertEqual(candidate?.port, 50001)
    }
    
    func testParseICETransport() {
        let xml = """
        <transport xmlns='urn:xmpp:jingle:transports:ice-udp:1' 
                   ufrag='abc123' 
                   pwd='def456' 
                   fingerprint='SHA-1 ABCDEF' 
                   fingerprint-algorithm='sha-1'>
          <candidate component='1' foundation='1' generation='0' id='1' 
                     ip='1.2.3.4' network='1' port='10000' 
                     priority='2130706431' protocol='udp' type='host'/>
          <candidate component='1' foundation='2' generation='0' id='2' 
                     ip='5.6.7.8' network='1' port='10001' 
                     priority='16777215' protocol='udp' type='srflx'/>
        </transport>
        """
        
        let transport = JingleParser.parseTransport(from: xml)
        
        XCTAssertNotNil(transport)
        XCTAssertEqual(transport?.ufrag, "abc123")
        XCTAssertEqual(transport?.pwd, "def456")
        XCTAssertEqual(transport?.fingerprint, "SHA-1 ABCDEF")
        XCTAssertEqual(transport?.fingerprintAlgorithm, "sha-1")
        XCTAssertEqual(transport?.candidates.count, 2)
    }
    
    func testParseRTPDescription() {
        let xml = """
        <description xmlns='urn:xmpp:jingle:apps:rtp:1' media='video' ssrc='123456789'/>
        """
        
        let description = JingleParser.parseDescription(from: xml)
        
        XCTAssertNotNil(description)
        XCTAssertEqual(description?.media, "video")
        XCTAssertEqual(description?.ssrc, 123456789)
    }
    
    func testParseJingleSessionAccept() {
        let xml = """
        <iq type='set' id='jingle_2' from='user@alpha.jitsi.net/resource' to='focus@auth.alpha.jitsi.net/focus'>
          <jingle xmlns='urn:xmpp:jingle:1' 
                  action='session-accept' 
                  initiator='focus@auth.alpha.jitsi.net/focus' 
                  responder='user@alpha.jitsi.net/resource' 
                  sid='abc123def456'>
            <content creator='responder' name='audio' senders='both'>
              <description xmlns='urn:xmpp:jingle:apps:rtp:1' media='audio'/>
              <transport xmlns='urn:xmpp:jingle:transports:ice-udp:1' 
                         ufrag='xyz789' 
                         pwd='abc012' 
                         fingerprint='SHA-1 XYZ123' 
                         fingerprint-algorithm='sha-1'/>
            </content>
          </jingle>
        </iq>
        """
        
        let session = JingleParser.parseSession(from: xml)
        
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.action, .sessionAccept)
        XCTAssertEqual(session?.initiator, "focus@auth.alpha.jitsi.net/focus")
        XCTAssertEqual(session?.responder, "user@alpha.jitsi.net/resource")
        XCTAssertEqual(session?.sid, "abc123def456")
        
        let content = session?.contents.first
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.creator, "responder")
    }
    
    func testParseJingleSessionTerminate() {
        let xml = """
        <iq type='set' id='jingle_3' from='focus@auth.alpha.jitsi.net/focus' to='user@alpha.jitsi.net/resource'>
          <jingle xmlns='urn:xmpp:jingle:1' 
                  action='session-terminate' 
                  initiator='focus@auth.alpha.jitsi.net/focus' 
                  sid='abc123def456'>
            <reason>
              <success/>
            </reason>
          </jingle>
        </iq>
        """
        
        let session = JingleParser.parseSession(from: xml)
        
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.action, .sessionTerminate)
    }
    
    func testParseInvalidJingle() {
        let xml = """
        <iq type='set' id='jingle_1'>
          <invalid xmlns='urn:xmpp:jingle:1'/>
        </iq>
        """
        
        let session = JingleParser.parseSession(from: xml)
        
        XCTAssertNil(session)
    }
}
