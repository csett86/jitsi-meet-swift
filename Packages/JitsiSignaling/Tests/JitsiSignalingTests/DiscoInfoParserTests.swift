//
//  DiscoInfoParserTests.swift
//  JitsiSignalingTests
//
//  Created for Jitsi Native macOS Client
//

import XCTest
@testable import JitsiSignaling

class DiscoInfoParserTests: XCTestCase {
    
    func testParseDiscoInfo() {
        let xml = """
        <iq type='result' id='disco_1' from='alpha.jitsi.net'>
          <query xmlns='http://jabber.org/protocol/disco#info' node=''>
            <identity category='conference' type='text' name='Jitsi Meet'/>
            <feature var='http://jabber.org/protocol/muc'/>
            <feature var='urn:xmpp:jingle:1'/>
            <feature var='http://jitsi.org/protocol/colibri'/>
            <feature var='http://jitsi.org/protocol/lobby'/>
            <feature var='http://jitsi.org/protocol/e2ee'/>
          </query>
        </iq>
        """
        
        let discoInfo = DiscoInfoParser.parse(from: xml)
        
        XCTAssertNotNil(discoInfo)
        XCTAssertEqual(discoInfo?.from, "alpha.jitsi.net")
        XCTAssertEqual(discoInfo?.identities.count, 1)
        
        let identity = discoInfo?.identities.first
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity?.category, "conference")
        XCTAssertEqual(identity?.type, "text")
        XCTAssertEqual(identity?.name, "Jitsi Meet")
        
        XCTAssertEqual(discoInfo?.features.count, 4)
        XCTAssertTrue(discoInfo?.features.contains("http://jabber.org/protocol/muc") ?? false)
        XCTAssertTrue(discoInfo?.features.contains("urn:xmpp:jingle:1") ?? false)
        XCTAssertTrue(discoInfo?.features.contains("http://jitsi.org/protocol/colibri") ?? false)
        XCTAssertTrue(discoInfo?.features.contains("http://jitsi.org/protocol/lobby") ?? false)
    }
    
    func testBackendCapabilitiesFromDiscoInfo() {
        let xml = """
        <iq type='result' id='disco_1' from='alpha.jitsi.net'>
          <query xmlns='http://jabber.org/protocol/disco#info'>
            <feature var='http://jitsi.org/protocol/lobby'/>
            <feature var='http://jitsi.org/protocol/e2ee'/>
            <feature var='http://jitsi.org/protocol/visitors'/>
            <feature var='http://jitsi.org/protocol/recording'/>
            <feature var='http://jitsi.org/protocol/livestreaming'/>
            <feature var='http://jitsi.org/protocol/sip'/>
            <feature var='http://jitsi.org/protocol/pstn'/>
            <feature var='http://jitsi.org/protocol/colibri'/>
            <feature var='urn:xmpp:jingle:1'/>
          </query>
        </iq>
        """
        
        let discoInfo = DiscoInfoParser.parse(from: xml)
        XCTAssertNotNil(discoInfo)
        
        let capabilities = BackendCapabilities.from(discoInfo: discoInfo!)
        
        XCTAssertTrue(capabilities.supportsLobby)
        XCTAssertTrue(capabilities.supportsE2EE)
        XCTAssertTrue(capabilities.supportsVisitors)
        XCTAssertTrue(capabilities.supportsRecording)
        XCTAssertTrue(capabilities.supportsLiveStreaming)
        XCTAssertTrue(capabilities.supportsSIP)
        XCTAssertTrue(capabilities.supportsPSTN)
        XCTAssertTrue(capabilities.supportsColibri2)
        XCTAssertTrue(capabilities.supportsJingle)
    }
    
    func testParseIdentity() {
        let xml = """
        <identity category='conference' type='text' name='Jitsi Meet' xml:lang='en'/>
        """
        
        let identity = DiscoInfoParser.parseIdentity(from: xml)
        
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity?.category, "conference")
        XCTAssertEqual(identity?.type, "text")
        XCTAssertEqual(identity?.name, "Jitsi Meet")
        XCTAssertEqual(identity?.lang, "en")
    }
    
    func testParseFeature() {
        let xml = """
        <feature var='urn:xmpp:jingle:1'/>
        """
        
        let feature = DiscoInfoParser.parseFeature(from: xml)
        
        XCTAssertEqual(feature, "urn:xmpp:jingle:1")
    }
}
