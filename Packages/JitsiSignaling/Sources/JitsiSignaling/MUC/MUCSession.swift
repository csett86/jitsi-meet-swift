//
//  MUCSession.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation
import Combine

// MARK: - MUC Participant

public struct MUCParticipant: Identifiable {
    public let id: String
    public let jid: String
    public let nick: String
    public let role: MUCRole
    public let affiliation: MUCAffiliation
    public let presence: ParticipantPresence
    
    public init(
        id: String,
        jid: String,
        nick: String,
        role: MUCRole,
        affiliation: MUCAffiliation,
        presence: ParticipantPresence
    ) {
        self.id = id
        self.jid = jid
        self.nick = nick
        self.role = role
        self.affiliation = affiliation
        self.presence = presence
    }
}

public enum MUCRole: String {
    case none
    case visitor
    case participant
    case moderator
}

public enum MUCAffiliation: String {
    case none
    case member
    case admin
    case owner
}

// MARK: - Participant Presence

public struct ParticipantPresence {
    public let show: PresenceShow?
    public let status: String?
    public let videoType: String?
    public let region: String?
    public let statsId: String?
    public let isDominantSpeaker: Bool
    public let isVideoMuted: Bool
    public let isAudioMuted: Bool
    
    public init(
        show: PresenceShow? = nil,
        status: String? = nil,
        videoType: String? = nil,
        region: String? = nil,
        statsId: String? = nil,
        isDominantSpeaker: Bool = false,
        isVideoMuted: Bool = false,
        isAudioMuted: Bool = false
    ) {
        self.show = show
        self.status = status
        self.videoType = videoType
        self.region = region
        self.statsId = statsId
        self.isDominantSpeaker = isDominantSpeaker
        self.isVideoMuted = isVideoMuted
        self.isAudioMuted = isAudioMuted
    }
}

// MARK: - MUC Session State

public enum MUCSessionState {
    case disconnected
    case connecting
    case connected
    case joined
    case left
    case failed(Error)
}

// MARK: - MUC Session

public class MUCSession: ObservableObject {
    
    private let connection: XMPPWebSocketConnection
    private let roomJID: String
    private let nick: String
    
    @Published public private(set) var state: MUCSessionState = .disconnected
    @Published public private(set) var participants: [String: MUCParticipant] = [:]
    @Published public private(set) var focusJID: String?
    
    public var onParticipantJoined: ((MUCParticipant) -> Void)?
    public var onParticipantLeft: ((MUCParticipant) -> Void)?
    public var onParticipantUpdated: ((MUCParticipant) -> Void)?
    public var onFocusJoined: ((String) -> Void)?
    public var onMessage: ((Message) -> Void)?
    public var onIQ: ((IQ) -> Void)?
    
    public init(
        connection: XMPPWebSocketConnection,
        roomJID: String,
        nick: String
    ) {
        self.connection = connection
        self.roomJID = roomJID
        self.nick = nick
        
        setupHandlers()
    }
    
    private func setupHandlers() {
        connection.onStanza = { [weak self] stanza in
            self?.handleStanza(stanza)
        }
    }
    
    public func join() {
        guard state == .disconnected || state == .left else {
            return
        }
        
        state = .connecting
        
        // Send presence to join MUC
        let presenceXML = """
        <presence to='\(roomJID)/\(nick)'>
          <x xmlns='http://jabber.org/protocol/muc'/>
        </presence>
        """
        connection.send(presenceXML)
    }
    
    public func leave() {
        guard state == .joined else {
            return
        }
        
        state = .left
        
        // Send presence to leave MUC
        let presenceXML = """
        <presence type='unavailable' to='\(roomJID)/\(nick)'>
          <x xmlns='http://jabber.org/protocol/muc'/>
        </presence>
        """
        connection.send(presenceXML)
        
        // Clear participants
        participants.removeAll()
        focusJID = nil
    }
    
    private func handleStanza(_ stanza: XMPPStanza) {
        switch stanza.type {
        case .presence:
            handlePresence(stanza)
        case .message:
            handleMessage(stanza)
        case .iq:
            handleIQ(stanza)
        default:
            break
        }
    }
    
    private func handlePresence(_ stanza: XMPPStanza) {
        // Parse presence
        let presence = StanzaParser.parsePresence(from: stanza.rawXML)
        
        // Check if this is from the MUC room
        guard stanza.rawXML.contains(roomJID) else {
            return
        }
        
        // Extract from JID
        var fromJID: String?
        if let range = stanza.rawXML.range(of: "from='([^']*)'", options: .regularExpression) {
            fromJID = String(stanza.rawXML[range])
        }
        
        guard let fromJID = fromJID else {
            return
        }
        
        // Check if this is our own presence (joined successfully)
        if fromJID.contains(nick) && stanza.rawXML.contains("type=''") {
            state = .joined
            return
        }
        
        // Check if this is from the focus
        if fromJID.contains("focus") {
            focusJID = fromJID
            onFocusJoined?(fromJID)
            return
        }
        
        // Extract nick from JID (part after /)
        let nick: String
        if let slashRange = fromJID.range(of: "/") {
            nick = String(fromJID[slashRange.upperBound...])
        } else {
            nick = fromJID
        }
        
        // Check if participant is leaving
        if stanza.rawXML.contains("type='unavailable'") {
            if let participant = participants[nick] {
                participants.removeValue(forKey: nick)
                onParticipantLeft?(participant)
            }
            return
        }
        
        // Parse participant presence
        let participantPresence = parseParticipantPresence(from: stanza.rawXML)
        
        // Extract role and affiliation from MUC user extension
        var role: MUCRole = .none
        var affiliation: MUCAffiliation = .none
        
        if let range = stanza.rawXML.range(of: "role='([^']*)'", options: .regularExpression) {
            let roleString = String(stanza.rawXML[range])
            role = MUCRole(rawValue: roleString) ?? .none
        }
        
        if let range = stanza.rawXML.range(of: "affiliation='([^']*)'", options: .regularExpression) {
            let affString = String(stanza.rawXML[range])
            affiliation = MUCAffiliation(rawValue: affString) ?? .none
        }
        
        // Extract JID from MUC user extension
        var participantJID = fromJID
        if let range = stanza.rawXML.range(of: "jid='([^']*)'", options: .regularExpression) {
            participantJID = String(stanza.rawXML[range])
        }
        
        let participant = MUCParticipant(
            id: nick,
            jid: participantJID,
            nick: nick,
            role: role,
            affiliation: affiliation,
            presence: participantPresence
        )
        
        // Check if this is a new participant or update
        if participants[nick] == nil {
            participants[nick] = participant
            onParticipantJoined?(participant)
        } else {
            participants[nick] = participant
            onParticipantUpdated?(participant)
        }
    }
    
    private func parseParticipantPresence(from xml: String) -> ParticipantPresence {
        var show: PresenceShow?
        var status: String?
        var videoType: String?
        var region: String?
        var statsId: String?
        var isDominantSpeaker = false
        var isVideoMuted = false
        var isAudioMuted = false
        
        // Extract show
        if let range = xml.range(of: "<show>(.*?)</show>", options: .regularExpression) {
            let showString = String(xml[range])
            show = PresenceShow(rawValue: showString)
        }
        
        // Extract status
        if let range = xml.range(of: "<status>(.*?)</status>", options: .regularExpression) {
            status = String(xml[range])
        }
        
        // Extract Jitsi-specific extensions
        if let range = xml.range(of: "<video-type[^>]*>(.*?)</video-type>", options: .regularExpression) {
            videoType = String(xml[range])
        }
        
        if let range = xml.range(of: "<region[^>]*>(.*?)</region>", options: .regularExpression) {
            region = String(xml[range])
        }
        
        if let range = xml.range(of: "<stats-id[^>]*>(.*?)</stats-id>", options: .regularExpression) {
            statsId = String(xml[range])
        }
        
        if xml.contains("<dominant-speaker") {
            isDominantSpeaker = true
        }
        
        if xml.contains("<video-muted") {
            isVideoMuted = true
        }
        
        if xml.contains("<audio-muted") {
            isAudioMuted = true
        }
        
        return ParticipantPresence(
            show: show,
            status: status,
            videoType: videoType,
            region: region,
            statsId: statsId,
            isDominantSpeaker: isDominantSpeaker,
            isVideoMuted: isVideoMuted,
            isAudioMuted: isAudioMuted
        )
    }
    
    private func handleMessage(_ stanza: XMPPStanza) {
        if let message = StanzaParser.parseMessage(from: stanza.rawXML) {
            onMessage?(message)
        }
    }
    
    private func handleIQ(_ stanza: XMPPStanza) {
        if let iq = StanzaParser.parseIQ(from: stanza.rawXML) {
            onIQ?(iq)
        }
    }
    
    /// Send a message to the MUC room
    public func sendMessage(_ body: String) {
        let messageXML = """
        <message type='groupchat' to='\(roomJID)'>
          <body>\(body)</body>
        </message>
        """
        connection.send(messageXML)
    }
    
    /// Send a private message to a participant
    public func sendPrivateMessage(to nick: String, body: String) {
        let messageXML = """
        <message type='chat' to='\(roomJID)/\(nick)'>
          <body>\(body)</body>
        </message>
        """
        connection.send(messageXML)
    }
}
