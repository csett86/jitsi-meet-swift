//
//  JitsiConference.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation
import Combine

// MARK: - Conference State

public enum ConferenceState {
    case disconnected
    case connecting
    case connected
    case joined
    case failed(Error)
}

// MARK: - Session Description

public struct SessionDescription {
    public let jingleSession: JingleSession?
    public let colibriContent: ColibriContent?
    public let ssrcMappings: [UInt32: String]  // SSRC to endpoint mapping
    
    public init(
        jingleSession: JingleSession? = nil,
        colibriContent: ColibriContent? = nil,
        ssrcMappings: [UInt32: String] = [:]
    ) {
        self.jingleSession = jingleSession
        self.colibriContent = colibriContent
        self.ssrcMappings = ssrcMappings
    }
}

// MARK: - Conference Events

public enum ConferenceEvent {
    case connectionStateChanged(ConferenceState)
    case participantJoined(MUCParticipant)
    case participantLeft(MUCParticipant)
    case participantUpdated(MUCParticipant)
    case focusJoined(String)
    case sessionDescriptionReceived(SessionDescription)
    case sourceAdded(SourceAdd)
    case sourceRemoved(SourceRemove)
    case messageReceived(Message)
    case error(Error)
}

// MARK: - Jitsi Conference

public class JitsiConference: ObservableObject {
    
    private let config: BackendConfig
    private var connection: XMPPWebSocketConnection?
    private var mucSession: MUCSession?
    private var saslAuthenticator: SASLAuthenticator?
    private var turnDiscovery: TURNDiscovery?
    private var discoInfo: DiscoInfo?
    private var backendCapabilities: BackendCapabilities = BackendCapabilities()
    
    @Published public private(set) var state: ConferenceState = .disconnected
    @Published public private(set) var participants: [String: MUCParticipant] = [:]
    @Published public private(set) var focusJID: String?
    @Published public private(set) var sessionDescription: SessionDescription?
    @Published public private(set) var turnServers: [TURNServer] = []
    
    private var cancellables: Set<AnyCancellable> = []
    
    public var onEvent: ((ConferenceEvent) -> Void)?
    
    public init(config: BackendConfig) {
        self.config = config
    }
    
    // MARK: - Connection
    
    public func connect() {
        guard state == .disconnected else {
            return
        }
        
        state = .connecting
        emitEvent(.connectionStateChanged(.connecting))
        
        // Create connection
        connection = XMPPWebSocketConnection(websocketURL: config.xmppWebSocketURL)
        
        // Setup connection handlers
        connection?.onStateChange = { [weak self] connectionState in
            self?.handleConnectionState(connectionState)
        }
        
        connection?.onStreamOpen = { [weak self] in
            self?.handleStreamOpen()
        }
        
        connection?.onStreamClose = { [weak self] in
            self?.handleStreamClose()
        }
        
        connection?.onStanza = { [weak self] stanza in
            self?.handleStanza(stanza)
        }
        
        // Connect
        connection?.connect()
    }
    
    public func disconnect() {
        guard state != .disconnected else {
            return
        }
        
        state = .disconnected
        emitEvent(.connectionStateChanged(.disconnected))
        
        mucSession?.leave()
        mucSession = nil
        
        saslAuthenticator = nil
        turnDiscovery = nil
        
        connection?.disconnect()
        connection = nil
        
        participants.removeAll()
        focusJID = nil
        sessionDescription = nil
    }
    
    // MARK: - Room Joining
    
    public func join(room: String, nick: String) {
        guard state == .connected else {
            return
        }
        
        // Create MUC session
        let roomJID = "\(room)@\(config.mucDomain)"
        mucSession = MUCSession(connection: connection!, roomJID: roomJID, nick: nick)
        
        // Setup MUC handlers
        mucSession?.onParticipantJoined = { [weak self] participant in
            self?.handleParticipantJoined(participant)
        }
        
        mucSession?.onParticipantLeft = { [weak self] participant in
            self?.handleParticipantLeft(participant)
        }
        
        mucSession?.onParticipantUpdated = { [weak self] participant in
            self?.handleParticipantUpdated(participant)
        }
        
        mucSession?.onFocusJoined = { [weak self] jid in
            self?.handleFocusJoined(jid)
        }
        
        mucSession?.onMessage = { [weak self] message in
            self?.handleMessage(message)
        }
        
        mucSession?.onIQ = { [weak self] iq in
            self?.handleIQ(iq)
        }
        
        // Join MUC
        mucSession?.join()
    }
    
    // MARK: - State Handling
    
    private func handleConnectionState(_ connectionState: XMPPConnectionState) {
        switch connectionState {
        case .connected:
            state = .connected
            emitEvent(.connectionStateChanged(.connected))
            
            // Query disco info
            queryDiscoInfo()
            
        case .authenticated:
            // Stream restarted after auth
            state = .connected
            emitEvent(.connectionStateChanged(.connected))
            
        case .disconnected:
            state = .disconnected
            emitEvent(.connectionStateChanged(.disconnected))
            
        case .connecting:
            state = .connecting
            emitEvent(.connectionStateChanged(.connecting))
            
        case .failed(let error):
            state = .failed(error)
            emitEvent(.connectionStateChanged(.failed(error)))
        }
    }
    
    private func handleStreamOpen() {
        // Stream opened, start SASL authentication
        startSASLAuthentication()
    }
    
    private func handleStreamClose() {
        // Stream closed
        state = .disconnected
        emitEvent(.connectionStateChanged(.disconnected))
    }
    
    // MARK: - Authentication
    
    private func startSASLAuthentication() {
        saslAuthenticator = SASLAuthenticator(
            connection: connection!,
            mechanism: .anonymous
        )
        
        saslAuthenticator?.onSuccess = { [weak self] in
            self?.handleAuthSuccess()
        }
        
        saslAuthenticator?.onFailure = { [weak self] error in
            self?.handleAuthFailure(error)
        }
        
        saslAuthenticator?.start()
    }
    
    private func handleAuthSuccess() {
        // Restart stream after successful authentication
        connection?.restartStream()
        
        // After stream restart, we need to bind the resource
        bindResource()
    }
    
    private func handleAuthFailure(_ error: Error) {
        state = .failed(error)
        emitEvent(.connectionStateChanged(.failed(error)))
    }
    
    private func bindResource() {
        let iqId = UUID().uuidString
        let bindRequest = """
        <iq type='set' id='\(iqId)'>
          <bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'>
            <resource>JitsiNativeMac</resource>
          </bind>
        </iq>
        """
        connection?.send(bindRequest)
    }
    
    // MARK: - Service Discovery
    
    private func queryDiscoInfo() {
        let iqId = UUID().uuidString
        let discoRequest = """
        <iq type='get' id='\(iqId)'>
          <query xmlns='http://jabber.org/protocol/disco#info'/>
        </iq>
        """
        connection?.send(discoRequest)
    }
    
    private func handleDiscoResponse(_ iq: IQ) {
        if let discoInfo = DiscoInfoParser.parse(from: iq.toXML()) {
            self.discoInfo = discoInfo
            self.backendCapabilities = BackendCapabilities.from(discoInfo: discoInfo)
            
            // Discover TURN servers
            discoverTURN()
        }
    }
    
    private func discoverTURN() {
        turnDiscovery = TURNDiscovery(connection: connection!)
        
        turnDiscovery?.onServersDiscovered = { [weak self] servers in
            self?.turnServers = servers
        }
        
        Task {
            do {
                let servers = try await turnDiscovery?.discover()
                if let servers = servers {
                    self.turnServers = servers
                }
            } catch {
                print("TURN discovery failed: \(error)")
            }
        }
    }
    
    // MARK: - Stanza Handling
    
    private func handleStanza(_ stanza: XMPPStanza) {
        // Handle different stanza types
        switch stanza.type {
        case .iq:
            handleIQStanza(stanza)
        case .presence:
            handlePresenceStanza(stanza)
        case .message:
            handleMessageStanza(stanza)
        default:
            break
        }
    }
    
    private func handleIQStanza(_ stanza: XMPPStanza) {
        // Parse IQ
        if let iq = StanzaParser.parseIQ(from: stanza.rawXML) {
            handleIQ(iq)
        }
    }
    
    private func handlePresenceStanza(_ stanza: XMPPStanza) {
        // Presence is handled by MUC session
    }
    
    private func handleMessageStanza(_ stanza: XMPPStanza) {
        // Parse message
        if let message = StanzaParser.parseMessage(from: stanza.rawXML) {
            handleMessage(message)
        }
    }
    
    private func handleIQ(_ iq: IQ) {
        // Check if this is a disco response
        if iq.toXML().contains("xmlns='http://jabber.org/protocol/disco#info'") {
            handleDiscoResponse(iq)
            return
        }
        
        // Check for Jingle session
        if iq.toXML().contains("xmlns='urn:xmpp:jingle:1'") {
            handleJingleIQ(iq)
            return
        }
        
        // Check for Colibri content
        if iq.toXML().contains("xmlns='http://jitsi.org/protocol/colibri'") {
            handleColibriIQ(iq)
            return
        }
        
        // Forward to MUC session
        mucSession?.onIQ?(iq)
    }
    
    private func handleJingleIQ(_ iq: IQ) {
        // Parse Jingle session
        if let jingleSession = JingleParser.parseSession(from: iq.toXML()) {
            // Create session description
            var sessionDescription = SessionDescription(
                jingleSession: jingleSession,
                colibriContent: nil
            )
            
            // Check if we already have Colibri content
            if let existing = self.sessionDescription {
                sessionDescription.colibriContent = existing.colibriContent
                sessionDescription.ssrcMappings = existing.ssrcMappings
            }
            
            self.sessionDescription = sessionDescription
            emitEvent(.sessionDescriptionReceived(sessionDescription))
        }
    }
    
    private func handleColibriIQ(_ iq: IQ) {
        // Parse Colibri content
        if let colibriContent = ColibriParser.parseContent(from: iq.toXML()) {
            // Create or update session description
            if var existing = sessionDescription {
                existing.colibriContent = colibriContent
                self.sessionDescription = existing
            } else {
                sessionDescription = SessionDescription(
                    jingleSession: nil,
                    colibriContent: colibriContent
                )
            }
            
            emitEvent(.sessionDescriptionReceived(sessionDescription!))
        }
    }
    
    private func handleMessage(_ message: Message) {
        // Check for source-add/source-remove
        if let sourceAdd = parseSourceAdd(from: message) {
            emitEvent(.sourceAdded(sourceAdd))
            
            // Update SSRC mappings
            if var sessionDesc = sessionDescription {
                sessionDesc.ssrcMappings[sourceAdd.ssrc] = sourceAdd.endpoint
                sessionDescription = sessionDesc
            }
            return
        }
        
        if let sourceRemove = parseSourceRemove(from: message) {
            emitEvent(.sourceRemoved(sourceRemove))
            
            // Remove from SSRC mappings
            if var sessionDesc = sessionDescription {
                sessionDesc.ssrcMappings.removeValue(forKey: sourceRemove.ssrc)
                sessionDescription = sessionDesc
            }
            return
        }
        
        // Forward to MUC session
        mucSession?.onMessage?(message)
    }
    
    private func parseSourceAdd(from message: Message) -> SourceAdd? {
        // Check if this is a source-add message
        guard let body = message.body else {
            return nil
        }
        
        return ColibriParser.parseSourceAdd(from: body)
    }
    
    private func parseSourceRemove(from message: Message) -> SourceRemove? {
        // Check if this is a source-remove message
        guard let body = message.body else {
            return nil
        }
        
        return ColibriParser.parseSourceRemove(from: body)
    }
    
    // MARK: - Participant Handling
    
    private func handleParticipantJoined(_ participant: MUCParticipant) {
        participants[participant.nick] = participant
        emitEvent(.participantJoined(participant))
    }
    
    private func handleParticipantLeft(_ participant: MUCParticipant) {
        participants.removeValue(forKey: participant.nick)
        emitEvent(.participantLeft(participant))
    }
    
    private func handleParticipantUpdated(_ participant: MUCParticipant) {
        participants[participant.nick] = participant
        emitEvent(.participantUpdated(participant))
    }
    
    private func handleFocusJoined(_ jid: String) {
        focusJID = jid
        emitEvent(.focusJoined(jid))
    }
    
    // MARK: - Event Emission
    
    private func emitEvent(_ event: ConferenceEvent) {
        onEvent?(event)
    }
    
    // MARK: - Public Getters
    
    public func getBackendCapabilities() -> BackendCapabilities {
        return backendCapabilities
    }
    
    public func getDiscoInfo() -> DiscoInfo? {
        return discoInfo
    }
}
