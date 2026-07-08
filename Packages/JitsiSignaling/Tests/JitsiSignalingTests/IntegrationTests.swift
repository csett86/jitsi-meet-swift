//
//  IntegrationTests.swift
//  JitsiSignalingTests
//
//  Created for Jitsi Native macOS Client
//

import XCTest
@testable import JitsiSignaling

class IntegrationTests: XCTestCase {
    
    func testConferenceStateTransitions() {
        let config = BackendConfig.alpha
        let conference = JitsiConference(config: config)
        
        // Initial state
        XCTAssertEqual(conference.state, .disconnected)
        
        // Test state transitions
        conference.state = .connecting
        XCTAssertEqual(conference.state, .connecting)
        
        conference.state = .connected
        XCTAssertEqual(conference.state, .connected)
        
        conference.state = .authenticated
        XCTAssertEqual(conference.state, .authenticated)
        
        conference.state = .joined(room: "testroom", nick: "TestUser")
        if case let .joined(room, nick) = conference.state {
            XCTAssertEqual(room, "testroom")
            XCTAssertEqual(nick, "TestUser")
        } else {
            XCTFail("State should be .joined")
        }
        
        conference.state = .disconnected
        XCTAssertEqual(conference.state, .disconnected)
    }
    
    func testConferenceStateEquality() {
        let state1: ConferenceState = .disconnected
        let state2: ConferenceState = .disconnected
        XCTAssertEqual(state1, state2)
        
        let state3: ConferenceState = .joined(room: "room1", nick: "nick1")
        let state4: ConferenceState = .joined(room: "room1", nick: "nick1")
        XCTAssertEqual(state3, state4)
        
        let state5: ConferenceState = .joined(room: "room2", nick: "nick2")
        XCTAssertNotEqual(state3, state5)
        
        XCTAssertNotEqual(state1, state3)
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
    
    func testBackendConfig() {
        let config = BackendConfig(
            displayName: "Test Server",
            xmppWebSocketURL: URL(string: "wss://test.example.com/xmpp-websocket")!,
            mucDomain: "conference.test.example.com",
            focusJID: "focus.test.example.com",
            anonymousDomain: "anonymous.test.example.com",
            jwtToken: "test_token"
        )
        
        XCTAssertEqual(config.displayName, "Test Server")
        XCTAssertEqual(config.xmppWebSocketURL.absoluteString, "wss://test.example.com/xmpp-websocket")
        XCTAssertEqual(config.mucDomain, "conference.test.example.com")
        XCTAssertEqual(config.focusJID, "focus.test.example.com")
        XCTAssertEqual(config.anonymousDomain, "anonymous.test.example.com")
        XCTAssertEqual(config.jwtToken, "test_token")
    }
    
    func testXMPPWebSocketConfiguration() {
        let url = URL(string: "wss://test.example.com/xmpp-websocket")!
        let config = XMPPWebSocketConfiguration(
            websocketURL: url,
            reconnectEnabled: true,
            maxReconnectAttempts: 10,
            reconnectBaseTimeout: 2.0,
            reconnectMaxTimeout: 60.0,
            pingInterval: 60.0,
            timeoutInterval: 60.0
        )
        
        XCTAssertEqual(config.websocketURL, url)
        XCTAssertTrue(config.reconnectEnabled)
        XCTAssertEqual(config.maxReconnectAttempts, 10)
        XCTAssertEqual(config.reconnectBaseTimeout, 2.0)
        XCTAssertEqual(config.reconnectMaxTimeout, 60.0)
        XCTAssertEqual(config.pingInterval, 60.0)
        XCTAssertEqual(config.timeoutInterval, 60.0)
    }
    
    func testXMPPConnectionState() {
        let state1: XMPPConnectionState = .disconnected
        let state2: XMPPConnectionState = .disconnected
        XCTAssertEqual(state1, state2)
        
        let state3: XMPPConnectionState = .connecting
        XCTAssertNotEqual(state1, state3)
        
        let state4: XMPPConnectionState = .connected
        XCTAssertNotEqual(state1, state4)
        
        let state5: XMPPConnectionState = .authenticated
        XCTAssertNotEqual(state1, state5)
        
        let error = NSError(domain: "Test", code: -1)
        let state6: XMPPConnectionState = .failed(error)
        let state7: XMPPConnectionState = .failed(error)
        XCTAssertEqual(state6, state7)
        
        let state8: XMPPConnectionState = .reconnecting(timeout: 5.0, attempt: 1)
        let state9: XMPPConnectionState = .reconnecting(timeout: 5.0, attempt: 1)
        XCTAssertEqual(state8, state9)
        
        let state10: XMPPConnectionState = .reconnecting(timeout: 10.0, attempt: 2)
        XCTAssertNotEqual(state8, state10)
    }
    
    func testMUCParticipant() {
        let participant = MUCParticipant(
            id: "participant1",
            jid: "participant1@domain/resource",
            nick: "Participant1",
            role: .participant,
            affiliation: .member,
            presence: ParticipantPresence(
                show: .away,
                status: "Be right back",
                videoType: "camera",
                region: "global",
                statsId: "stats123",
                isDominantSpeaker: true,
                isVideoMuted: false,
                isAudioMuted: false
            )
        )
        
        XCTAssertEqual(participant.id, "participant1")
        XCTAssertEqual(participant.jid, "participant1@domain/resource")
        XCTAssertEqual(participant.nick, "Participant1")
        XCTAssertEqual(participant.role, .participant)
        XCTAssertEqual(participant.affiliation, .member)
        XCTAssertEqual(participant.presence.show, .away)
        XCTAssertEqual(participant.presence.status, "Be right back")
        XCTAssertEqual(participant.presence.videoType, "camera")
        XCTAssertTrue(participant.presence.isDominantSpeaker)
    }
    
    func testConferenceEvent() {
        // Test all conference event cases
        let participant = MUCParticipant(
            id: "test",
            jid: "test@domain",
            nick: "Test",
            role: .participant,
            affiliation: .none,
            presence: ParticipantPresence()
        )
        
        let events: [ConferenceEvent] = [
            .connectionStateChanged(.disconnected),
            .participantJoined(participant),
            .participantLeft(participant),
            .participantUpdated(participant),
            .focusJoined("focus@domain"),
            .sessionDescriptionReceived(SessionDescription()),
            .sourceAdded(SourceAdd(conference: "conf1", ssrc: 123, endpoint: "ep1")),
            .sourceRemoved(SourceRemove(conference: "conf1", ssrc: 123, endpoint: "ep1")),
            .messageReceived(Message(type: .chat, body: "Hello")),
            .error(NSError(domain: "Test", code: -1)),
            .backendCapabilitiesUpdated(BackendCapabilities()),
            .turnServersDiscovered([])
        ]
        
        // Just verify we can create all event types
        XCTAssertEqual(events.count, 11)
    }
    
    func testTURNServer() {
        let server = TURNServer(
            hostname: "turn.example.com",
            port: 3478,
            transport: "udp",
            username: "testuser",
            credential: "testpass",
            credentialType: "password"
        )
        
        XCTAssertEqual(server.hostname, "turn.example.com")
        XCTAssertEqual(server.port, 3478)
        XCTAssertEqual(server.transport, "udp")
        XCTAssertEqual(server.username, "testuser")
        XCTAssertEqual(server.credential, "testpass")
        XCTAssertEqual(server.credentialType, "password")
        
        let iceServer = server.toICEServer()
        XCTAssertNotNil(iceServer["urls"])
        XCTAssertNotNil(iceServer["username"])
        XCTAssertNotNil(iceServer["credential"])
    }
    
    func testColibriChannel() {
        let channel = ColibriChannel(
            id: "channel1",
            endpoint: "endpoint1",
            initFlag: true,
            lastN: 1,
            maxN: 1,
            expire: 60,
            ssrc: 123456789
        )
        
        XCTAssertEqual(channel.id, "channel1")
        XCTAssertEqual(channel.endpoint, "endpoint1")
        XCTAssertTrue(channel.initFlag)
        XCTAssertEqual(channel.lastN, 1)
        XCTAssertEqual(channel.maxN, 1)
        XCTAssertEqual(channel.expire, 60)
        XCTAssertEqual(channel.ssrc, 123456789)
    }
    
    func testColibriConference() {
        let channel = ColibriChannel(
            id: "channel1",
            endpoint: "endpoint1"
        )
        
        let conference = ColibriConference(
            id: "conference123",
            type: .audio,
            channels: [channel]
        )
        
        XCTAssertEqual(conference.id, "conference123")
        XCTAssertEqual(conference.type, .audio)
        XCTAssertEqual(conference.channels.count, 1)
    }
}
