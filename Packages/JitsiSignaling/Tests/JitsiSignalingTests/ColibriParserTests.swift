//
//  ColibriParserTests.swift
//  JitsiSignalingTests
//
//  Created for Jitsi Native macOS Client
//

import XCTest
@testable import JitsiSignaling

class ColibriParserTests: XCTestCase {
    
    func testParseColibriContent() {
        let xml = """
        <content xmlns='http://jitsi.org/protocol/colibri' from='focus@auth.alpha.jitsi.net/focus'>
          <conference xmlns='http://jitsi.org/protocol/colibri' 
                      id='conference123' 
                      type='audio'>
            <channel id='channel1' 
                      endpoint='endpoint1' 
                      init='true' 
                      last-n='1' 
                      max-n='1' 
                      expire='60'/>
            <channel id='channel2' 
                      endpoint='endpoint2' 
                      init='true' 
                      last-n='1' 
                      max-n='1' 
                      expire='60'/>
          </conference>
          <conference xmlns='http://jitsi.org/protocol/colibri' 
                      id='conference456' 
                      type='video'>
            <channel id='channel1' 
                      endpoint='endpoint1' 
                      init='true' 
                      last-n='1' 
                      max-n='1' 
                      expire='60'/>
          </conference>
        </content>
        """
        
        let content = ColibriParser.parseContent(from: xml)
        
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.from, "focus@auth.alpha.jitsi.net/focus")
        XCTAssertEqual(content?.conferences.count, 2)
        
        let audioConference = content?.conferences.first(where: { $0.id == "conference123" })
        XCTAssertNotNil(audioConference)
        XCTAssertEqual(audioConference?.type, .audio)
        XCTAssertEqual(audioConference?.channels.count, 2)
        
        let videoConference = content?.conferences.first(where: { $0.id == "conference456" })
        XCTAssertNotNil(videoConference)
        XCTAssertEqual(videoConference?.type, .video)
        XCTAssertEqual(videoConference?.channels.count, 1)
    }
    
    func testParseColibriChannel() {
        let xml = """
        <channel id='channel1' 
                  endpoint='endpoint1' 
                  init='true' 
                  last-n='1' 
                  max-n='1' 
                  expire='60' 
                  ssrc='123456789'/>
        """
        
        let channel = ColibriParser.parseChannel(from: xml)
        
        XCTAssertNotNil(channel)
        XCTAssertEqual(channel?.id, "channel1")
        XCTAssertEqual(channel?.endpoint, "endpoint1")
        XCTAssertTrue(channel?.initFlag ?? false)
        XCTAssertEqual(channel?.lastN, 1)
        XCTAssertEqual(channel?.maxN, 1)
        XCTAssertEqual(channel?.expire, 60)
        XCTAssertEqual(channel?.ssrc, 123456789)
    }
    
    func testParseSourceAdd() {
        let xml = """
        <message from='testroom123@conference.alpha.jitsi.net/focus' 
                 to='user@alpha.jitsi.net/resource' 
                 xmlns='jabber:client'>
          <source-add xmlns='http://jitsi.org/protocol/colibri' 
                      conference='conference123' 
                      ssrc='123456789' 
                      endpoint='endpoint1'/>
        </message>
        """
        
        let sourceAdd = ColibriParser.parseSourceAdd(from: xml)
        
        XCTAssertNotNil(sourceAdd)
        XCTAssertEqual(sourceAdd?.conference, "conference123")
        XCTAssertEqual(sourceAdd?.ssrc, 123456789)
        XCTAssertEqual(sourceAdd?.endpoint, "endpoint1")
    }
    
    func testParseSourceRemove() {
        let xml = """
        <message from='testroom123@conference.alpha.jitsi.net/focus' 
                 to='user@alpha.jitsi.net/resource' 
                 xmlns='jabber:client'>
          <source-remove xmlns='http://jitsi.org/protocol/colibri' 
                         conference='conference123' 
                         ssrc='123456789' 
                         endpoint='endpoint1'/>
        </message>
        """
        
        let sourceRemove = ColibriParser.parseSourceRemove(from: xml)
        
        XCTAssertNotNil(sourceRemove)
        XCTAssertEqual(sourceRemove?.conference, "conference123")
        XCTAssertEqual(sourceRemove?.ssrc, 123456789)
        XCTAssertEqual(sourceRemove?.endpoint, "endpoint1")
    }
    
    func testParseConferenceWithMultipleChannels() {
        let xml = """
        <conference xmlns='http://jitsi.org/protocol/colibri' 
                    id='conference123' 
                    type='video'>
          <channel id='channel1' endpoint='endpoint1' init='true' last-n='1' max-n='1' expire='60'/>
          <channel id='channel2' endpoint='endpoint2' init='true' last-n='1' max-n='1' expire='60'/>
          <channel id='channel3' endpoint='endpoint3' init='false' last-n='2' max-n='2' expire='30'/>
        </conference>
        """
        
        let conference = ColibriParser.parseConference(from: xml)
        
        XCTAssertNotNil(conference)
        XCTAssertEqual(conference?.id, "conference123")
        XCTAssertEqual(conference?.type, .video)
        XCTAssertEqual(conference?.channels.count, 3)
        
        let channel1 = conference?.channels.first(where: { $0.id == "channel1" })
        XCTAssertNotNil(channel1)
        XCTAssertEqual(channel1?.endpoint, "endpoint1")
        XCTAssertTrue(channel1?.initFlag ?? false)
        
        let channel3 = conference?.channels.first(where: { $0.id == "channel3" })
        XCTAssertNotNil(channel3)
        XCTAssertFalse(channel3?.initFlag ?? true)
        XCTAssertEqual(channel3?.lastN, 2)
        XCTAssertEqual(channel3?.maxN, 2)
        XCTAssertEqual(channel3?.expire, 30)
    }
}
