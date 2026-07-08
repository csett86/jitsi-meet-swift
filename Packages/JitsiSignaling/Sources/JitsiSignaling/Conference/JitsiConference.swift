//
//  JitsiConference.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation
import Combine

// MARK: - Conference State

public enum ConferenceState: Equatable {
    case disconnected
    case connecting
    case connected
    case authenticated
    case joined(room: String, nick: String)
    case failed(Error)
    
    public static func == (lhs: ConferenceState, rhs: ConferenceState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            return true
        case (.connecting, .connecting):
            return true
        case (.connected, .connected):
            return true
        case (.authenticated, .authenticated):
            return true
        case let (.joined(lRoom, lNick), .joined(rRoom, rNick)):
            return lRoom == rRoom && lNick == rNick
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
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
    case backendCapabilitiesUpdated(BackendCapabilities)
    case turnServersDiscovered([TURNServer])
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
    
    private var currentRoom: String?
    private var currentNick: String?
    private var isAuthenticated = false
    private var isStreamRestarted = false
    private var pendingBindIQ: String?
    private var pendingSessionIQ: String?
    
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
        
        // Create connection with reconnection support
        let wsConfig = XMPPWebSocketConfiguration(
            websocketURL: config.xmppWebSocketURL,
            reconnectEnabled: true,
            maxReconnectAttempts: 5,
            reconnectBaseTimeout: 1.0,
            reconnectMaxTimeout: 30.0,
            pingInterval: 30.0,
            timeoutInterval: 30.0
        )
        connection = XMPPWebSocketConnection(config: wsConfig)
        
        // Setup connection handlers
        setupConnectionHandlers()
        
        // Connect
        connection?.connect()
    }
    
    public func disconnect() {
        guard state != .disconnected else {
            return
        }
        
        // Leave MUC first
        if let mucSession = mucSession {
            mucSession.leave()
            self.mucSession = nil
        }
        
        // Disconnect
        connection?.disconnect()
        connection = nil
        
        // Reset state
        state = .disconnected
        emitEvent(.connectionStateChanged(.disconnected))
        
        // Clear data
        participants.removeAll()
        focusJID = nil
        sessionDescription = nil
        currentRoom = nil
        currentNick = nil
        isAuthenticated = false
        isStreamRestarted = false
    }
    
    // MARK: - Room Joining
    
    public func join(room: String, nick: String) {
        guard state == .connected || state == .authenticated else {
            emitEvent(.error(NSError(domain: "Conference", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Not connected"
            ])))
            return
        }
        
        currentRoom = room
        currentNick = nick
        
        // Create MUC session
        let roomJID = "\(room)@\(config.mucDomain)"
        mucSession = MUCSession(connection: connection!, roomJID: roomJID, nick: nick)
        
        // Setup MUC handlers
        setupMUCHandlers()
        
        // Join MUC
        mucSession?.join()
    }
    
    public func leave() {
        guard let mucSession = mucSession else {
            return
        }
        
        mucSession.leave()
        self.mucSession = nil
        
        // Reset room state
        currentRoom = nil
        currentNick = nil
        participants.removeAll()
        focusJID = nil
        sessionDescription = nil
        
        state = .connected
        emitEvent(.connectionStateChanged(.connected))
    }
    
    // MARK: - Setup Handlers
    
    private func setupConnectionHandlers() {
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
        
        connection?.onConnectionError = { [weak self] error in
            self?.handleConnectionError(error)
        }
    }
    
    private func setupMUCHandlers() {
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
            self?.handleMUCMessage(message)
        }
        
        mucSession?.onIQ = { [weak self] iq in
            self?.handleMUCIQ(iq)
        }
    }
    
    // MARK: - State Handling
    
    private func handleConnectionState(_ connectionState: XMPPConnectionState) {
        switch connectionState {
        case .connected:
            handleConnected()
        case .authenticated:
            handleAuthenticated()
        case .disconnected:
            handleDisconnected()
        case .connecting:
            state = .connecting
            emitEvent(.connectionStateChanged(.connecting))
        case .failed(let error):
            state = .failed(error)
            emitEvent(.connectionStateChanged(.failed(error)))
        case .reconnecting(let timeout, let attempt):
            // Keep current state but emit reconnecting event
            emitEvent(.connectionStateChanged(.connecting))
        }
    }
    
    private func handleConnected() {
        state = .connected
        emitEvent(.connectionStateChanged(.connected))
        
        // Query disco info
        queryDiscoInfo()
    }
    
    private func handleAuthenticated() {
        state = .authenticated
        emitEvent(.connectionStateChanged(.authenticated))
        connection?.setAuthenticated()
        
        // After authentication, we need to bind the resource
        bindResource()
    }
    
    private func handleDisconnected() {
        // Only transition to disconnected if we're not reconnecting
        if case .reconnecting = connection?.state {
            return
        }
        
        state = .disconnected
        emitEvent(.connectionStateChanged(.disconnected))
    }
    
    private func handleConnectionError(_ error: Error) {
        emitEvent(.error(error))
    }
    
    private func handleStreamOpen() {
        // Stream opened, start SASL authentication
        startSASLAuthentication()
    }
    
    private func handleStreamClose() {
        // Stream closed
        if case .joined = state {
            // If we were in a room, transition to connected
            state = .connected
            emitEvent(.connectionStateChanged(.connected))
        }
    }
    
    // MARK: - Authentication
    
    private func startSASLAuthentication() {
        guard let connection = connection else { return }
        
        saslAuthenticator = SASLAuthenticator(
            connection: connection,
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
        isAuthenticated = true
    }
    
    private func handleAuthFailure(_ error: Error) {
        state = .failed(error)
        emitEvent(.connectionStateChanged(.failed(error)))
        emitEvent(.error(error))
    }
    
    private func bindResource() {
        guard let connection = connection else { return }
        
        let iqId = UUID().uuidString
        pendingBindIQ = iqId
        
        let bindRequest = """
        <iq type='set' id='\(iqId)'>
          <bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'>
            <resource>JitsiNativeMac</resource>
          </bind>
        </iq>
        """
        connection.send(bindRequest)
    }
    
    private func startSession() {
        guard let connection = connection else { return }
        
        let iqId = UUID().uuidString
        pendingSessionIQ = iqId
        
        let sessionRequest = """
        <iq type='set' id='\(iqId)'>
          <session xmlns='urn:ietf:params:xml:ns:xmpp-session'/>
        </iq>
        """
        connection.send(sessionRequest)
    }
    
    // MARK: - Service Discovery
    
    private func queryDiscoInfo() {
        guard let connection = connection else { return }
        
        let iqId = UUID().uuidString
        let discoRequest = """
        <iq type='get' id='\(iqId)'>
          <query xmlns='http://jabber.org/protocol/disco#info'/>
        </iq>
        """
        connection.send(discoRequest)
    }
    
    private func discoverTURN() {
        guard let connection = connection else { return }
        
        turnDiscovery = TURNDiscovery(connection: connection)
        
        turnDiscovery?.onServersDiscovered = { [weak self] servers in
            self?.turnServers = servers
            self?.emitEvent(.turnServersDiscovered(servers))
        }
        
        Task {
            do {
                let servers = try await turnDiscovery?.discover()
                if let servers = servers {
                    self.turnServers = servers
                    emitEvent(.turnServersDiscovered(servers))
                }
            } catch {
                print("TURN discovery failed: \(error)")
                emitEvent(.error(error))
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
        case .streamOpen:
            // Handled by connection
            break
        case .streamClose:
            // Handled by connection
            break
        case .unknown:
            // Check for SASL-specific stanzas
            if stanza.rawXML.contains("<challenge") || 
               stanza.rawXML.contains("<success") || 
               stanza.rawXML.contains("<failure") {
                // SASL stanzas are handled by SASLAuthenticator
                saslAuthenticator?.onStanza?(stanza)
            }
        }
    }
    
    private func handleIQStanza(_ stanza: XMPPStanza) {
        // Parse IQ
        guard let iq = StanzaParser.parseIQ(from: stanza.rawXML) else {
            return
        }
        
        // Check if this is a response to our bind request
        if let pendingBindIQ = pendingBindIQ, iq.id == pendingBindIQ {
            handleBindResponse(iq)
            return
        }
        
        // Check if this is a response to our session request
        if let pendingSessionIQ = pendingSessionIQ, iq.id == pendingSessionIQ {
            handleSessionResponse(iq)
            return
        }
        
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
        
        // Forward to MUC session if available
        mucSession?.onIQ?(iq)
    }
    
    private func handleBindResponse(_ iq: IQ) {
        pendingBindIQ = nil
        
        if iq.type == .result {
            // Bind successful, start session
            startSession()
        } else if iq.type == .error {
            let error = NSError(domain: "XMPP", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Bind failed"
            ])
            state = .failed(error)
            emitEvent(.connectionStateChanged(.failed(error)))
        }
    }
    
    private func handleSessionResponse(_ iq: IQ) {
        pendingSessionIQ = nil
        
        if iq.type == .result {
            // Session established, we're fully connected
            state = .connected
            emitEvent(.connectionStateChanged(.connected))
            
            // Discover TURN servers
            discoverTURN()
            
            // If we have a pending room join, do it now
            if let room = currentRoom, let nick = currentNick {
                join(room: room, nick: nick)
            }
        } else if iq.type == .error {
            let error = NSError(domain: "XMPP", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Session establishment failed"
            ])
            state = .failed(error)
            emitEvent(.connectionStateChanged(.failed(error)))
        }
    }
    
    private func handleDiscoResponse(_ iq: IQ) {
        if let discoInfo = DiscoInfoParser.parse(from: iq.toXML()) {
            self.discoInfo = discoInfo
            self.backendCapabilities = BackendCapabilities.from(discoInfo: discoInfo)
            emitEvent(.backendCapabilitiesUpdated(backendCapabilities))
        }
    }
    
    private func handleJingleIQ(_ iq: IQ) {
        // Parse Jingle session
        if let jingleSession = JingleParser.parseSession(from: iq.toXML()) {
            updateSessionDescription(with: jingleSession)
        }
    }
    
    private func handleColibriIQ(_ iq: IQ) {
        // Parse Colibri content
        if let colibriContent = ColibriParser.parseContent(from: iq.toXML()) {
            updateSessionDescription(with: colibriContent)
        }
    }
    
    private func updateSessionDescription(with jingleSession: JingleSession) {
        if var existing = sessionDescription {
            existing.jingleSession = jingleSession
            self.sessionDescription = existing
        } else {
            sessionDescription = SessionDescription(
                jingleSession: jingleSession,
                colibriContent: nil
            )
        }
        
        emitEvent(.sessionDescriptionReceived(sessionDescription!))
    }
    
    private func updateSessionDescription(with colibriContent: ColibriContent) {
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
    
    private func handlePresenceStanza(_ stanza: XMPPStanza) {
        // Forward to MUC session if available
        mucSession?.onStanza?(stanza)
    }
    
    private func handleMessageStanza(_ stanza: XMPPStanza) {
        // Parse message
        guard let message = StanzaParser.parseMessage(from: stanza.rawXML) else {
            return
        }
        
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
        
        // Forward to MUC session if available
        mucSession?.onMessage?(message)
    }
    
    private func handleMUCMessage(_ message: Message) {
        emitEvent(.messageReceived(message))
    }
    
    private func handleMUCIQ(_ iq: IQ) {
        // Forward to main IQ handler
        handleIQStanza(XMPPStanza(rawXML: iq.toXML(), type: .iq))
    }
    
    private func parseSourceAdd(from message: Message) -> SourceAdd? {
        // Check if this is a source-add message
        let xml = message.toXML()
        return ColibriParser.parseSourceAdd(from: xml)
    }
    
    private func parseSourceRemove(from message: Message) -> SourceRemove? {
        // Check if this is a source-remove message
        let xml = message.toXML()
        return ColibriParser.parseSourceRemove(from: xml)
    }
    
    // MARK: - Participant Handling
    
    private func handleParticipantJoined(_ participant: MUCParticipant) {
        participants[participant.nick] = participant
        emitEvent(.participantJoined(participant))
        
        // If this is the first participant after joining, update state
        if participants.count == 1 && state == .connected {
            if let room = currentRoom, let nick = currentNick {
                state = .joined(room: room, nick: nick)
                emitEvent(.connectionStateChanged(.joined(room: room, nick: nick)))
            }
        }
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
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
    
    // MARK: - Public Getters
    
    public func getBackendCapabilities() -> BackendCapabilities {
        return backendCapabilities
    }
    
    public func getDiscoInfo() -> DiscoInfo? {
        return discoInfo
    }
    
    public func getCurrentRoom() -> (room: String, nick: String)? {
        guard let room = currentRoom, let nick = currentNick else {
            return nil
        }
        return (room, nick)
    }
}
