//
//  main.swift
//  SignalingSpike
//
//  Phase 0: Signaling Feasibility Spike
//  Objective: Connect to alpha.jitsi.net and capture XMPP/Jingle traffic
//

import Foundation

// MARK: - Backend Configuration

struct BackendConfig {
    let displayName: String
    let xmppWebSocketURL: URL
    let mucDomain: String
    let focusJID: String
    let anonymousDomain: String?
    let jwtToken: String?

    static let alpha = BackendConfig(
        displayName: "alpha.jitsi.net",
        xmppWebSocketURL: URL(string: "wss://alpha.jitsi.net/xmpp-websocket")!,
        mucDomain: "conference.alpha.jitsi.net",
        focusJID: "focus.alpha.jitsi.net",
        anonymousDomain: nil,
        jwtToken: nil
    )
}

// MARK: - Configuration for the spike

struct SpikeConfig {
    let roomName: String
    let nick: String
    let backendConfig: BackendConfig
    
    static let alphaTest = SpikeConfig(
        roomName: "testroom123",
        nick: "SwiftSpike",
        backendConfig: .alpha
    )
}

// MARK: - XMPP Stanza Types

enum StanzaType: String {
    case streamOpen = "stream-open"
    case streamClose = "stream-close"
    case authChallenge = "auth-challenge"
    case authSuccess = "auth-success"
    case presence = "presence"
    case iq = "iq"
    case message = "message"
    case unknown = "unknown"
}

struct XMPPStanza {
    let rawXML: String
    let type: StanzaType
    let timestamp: Date
    let direction: Direction
    
    enum Direction {
        case received
        case sent
    }
}

// MARK: - XML Stream Parser

class XMPPStreamParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentDepth = 0
    private var stanzaBuffer = ""
    private var inStanza = false
    private var stanzaDepth = 0
    private var stanzaStartTag: String?
    
    var onStanza: ((XMPPStanza) -> Void)?
    var onStreamOpen: (() -> Void)?
    var onStreamClose: (() -> Void)?
    
    func parse(data: Data, direction: XMPPStanza.Direction = .received) {
        // For simplicity, we'll use a string-based approach
        // since XMPP over WebSocket sends complete stanzas
        if let xmlString = String(data: data, encoding: .utf8) {
            parse(string: xmlString, direction: direction)
        }
    }
    
    func parse(string: String, direction: XMPPStanza.Direction = .received) {
        // Simple parsing: look for complete stanzas
        // XMPP stanzas are typically: <presence>, <iq>, <message>
        // Stream elements: <stream:stream>, </stream:stream>
        
        var remaining = string
        
        while !remaining.isEmpty {
            if let stanza = extractNextStanza(from: remaining) {
                let stanzaType = classifyStanza(stanza)
                let xmppStanza = XMPPStanza(
                    rawXML: stanza,
                    type: stanzaType,
                    timestamp: Date(),
                    direction: direction
                )
                
                // Handle stream events
                if stanzaType == .streamOpen {
                    onStreamOpen?()
                } else if stanzaType == .streamClose {
                    onStreamClose?()
                }
                
                onStanza?(xmppStanza)
                
                // Remove the parsed stanza from remaining
                if let range = remaining.range(of: stanza) {
                    remaining.removeSubrange(range)
                } else {
                    remaining = ""
                }
            } else {
                // No complete stanza found, might be partial
                break
            }
        }
    }
    
    private func extractNextStanza(from string: String) -> String? {
        // Look for opening tags
        let patterns = [
            "<stream:",
            "<presence",
            "<iq",
            "<message",
            "<challenge",
            "<success",
            "<failure",
            "<features",
            "<bind",
            "<auth"
        ]
        
        for pattern in patterns {
            if let startRange = string.range(of: pattern) {
                let startIndex = startRange.lowerBound
                let substring = String(string[startIndex...])
                
                // Find the matching closing tag
                if let endTag = findMatchingCloseTag(for: substring) {
                    let endRange = string.range(of: endTag, range: startIndex...)
                    if let endRange = endRange {
                        let fullStanza = String(string[startIndex..<endRange.upperBound])
                        return fullStanza
                    }
                }
            }
        }
        
        return nil
    }
    
    private func findMatchingCloseTag(for substring: String) -> String? {
        // Simple approach: look for self-closing or matching closing tag
        if substring.contains("/>") {
            if let range = substring.range(of: "/>") {
                return String(substring[...range.upperBound])
            }
        }
        
        // Look for closing tags
        let openingPatterns = [
            "<stream:",
            "<presence",
            "<iq",
            "<message",
            "<challenge",
            "<success",
            "<failure",
            "<features",
            "<bind",
            "<auth"
        ]
        
        for pattern in openingPatterns {
            if substring.hasPrefix(pattern) {
                let tagName: String
                if pattern == "<stream:" {
                    tagName = "stream:stream"
                } else {
                    tagName = String(pattern.dropFirst(1))
                }
                
                let closeTag = "</\(tagName)>"
                if substring.contains(closeTag) {
                    return closeTag
                }
                
                // Check for self-closing
                if substring.contains("/>") {
                    return "/>"
                }
            }
        }
        
        return nil
    }
    
    private func classifyStanza(_ xml: String) -> StanzaType {
        if xml.contains("<stream:") {
            if xml.contains("</stream:") {
                return .streamClose
            }
            return .streamOpen
        } else if xml.contains("<presence") {
            return .presence
        } else if xml.contains("<iq") {
            return .iq
        } else if xml.contains("<message") {
            return .message
        } else if xml.contains("<challenge") {
            return .authChallenge
        } else if xml.contains("<success") {
            return .authSuccess
        }
        return .unknown
    }
}

// MARK: - WebSocket Connection

class XMPPWebSocketConnection: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let parser = XMPPStreamParser()
    private let config: SpikeConfig
    
    var state: XMPPStreamState = .disconnected
    var onStateChange: ((XMPPStreamState) -> Void)?
    var onStanza: ((XMPPStanza) -> Void)?
    
    enum XMPPStreamState {
        case disconnected
        case connecting
        case streamOpened
        case authenticated
        case inMUC
    }
    
    init(config: SpikeConfig) {
        self.config = config
        super.init()
        
        parser.onStreamOpen = { [weak self] in
            self?.state = .streamOpened
            self?.onStateChange?(.streamOpened)
        }
        
        parser.onStreamClose = { [weak self] in
            self?.state = .disconnected
            self?.onStateChange?(.disconnected)
        }
        
        parser.onStanza = { [weak self] stanza in
            self?.onStanza?(stanza)
        }
    }
    
    func connect() {
        state = .connecting
        onStateChange?(.connecting)
        
        let url = config.backendConfig.xmppWebSocketURL
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        // Create URLSession with delegate for WebSocket
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        urlSession = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        listenForMessages()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        state = .disconnected
        onStateChange?(.disconnected)
    }
    
    func send(text: String) {
        print("SENDING: \(text.prefix(200))...")
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("RECEIVED: \(text.prefix(200))...")
                    if let data = text.data(using: .utf8) {
                        self.parser.parse(data: data, direction: .received)
                    }
                case .data(let data):
                    self.parser.parse(data: data, direction: .received)
                @unknown default:
                    break
                }
                self.listenForMessages()
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self.state = .disconnected
                self.onStateChange?(.disconnected)
            }
        }
    }
}

// MARK: - XMPP Session Manager

class XMPPSessionManager {
    private let connection: XMPPWebSocketConnection
    private let config: SpikeConfig
    private var streamId: String?
    private var sessionId: String?
    private var isAuthenticated = false
    private var isStreamRestarted = false
    
    var onStanza: ((XMPPStanza) -> Void)?
    var onStateChange: ((XMPPWebSocketConnection.XMPPStreamState) -> Void)?
    
    init(config: SpikeConfig) {
        self.config = config
        self.connection = XMPPWebSocketConnection(config: config)
        
        connection.onStateChange = { [weak self] state in
            self?.onStateChange?(state)
        }
        
        connection.onStanza = { [weak self] stanza in
            self?.handleStanza(stanza)
            self?.onStanza?(stanza)
        }
    }
    
    func connect() {
        connection.connect()
    }
    
    func disconnect() {
        connection.disconnect()
    }
    
    private func handleStanza(_ stanza: XMPPStanza) {
        print("\n=== \(stanza.direction == .received ? "RECEIVED" : "SENT") ===")
        print("Type: \(stanza.type.rawValue)")
        print("XML: \(stanza.rawXML)")
        print("===================\n")
        
        // Handle different stanza types
        switch stanza.type {
        case .streamOpen:
            handleStreamOpen(stanza)
        case .streamClose:
            handleStreamClose(stanza)
        case .authChallenge:
            handleAuthChallenge(stanza)
        case .authSuccess:
            handleAuthSuccess(stanza)
        case .presence:
            handlePresence(stanza)
        case .iq:
            handleIQ(stanza)
        case .message:
            handleMessage(stanza)
        case .unknown:
            break
        }
    }
    
    private func handleStreamOpen(_ stanza: XMPPStanza) {
        print("Stream opened")
        
        // After stream opens, we should get features
        // Then we can start authentication
        if !isAuthenticated && !isStreamRestarted {
            // Send stream features request or wait for it
        }
    }
    
    private func handleStreamClose(_ stanza: XMPPStanza) {
        print("Stream closed")
    }
    
    private func handleAuthChallenge(_ stanza: XMPPStanza) {
        print("Auth challenge received")
        
        // For ANONYMOUS auth, send empty response
        let response = """
        <response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>
        """
        connection.send(text: response)
    }
    
    private func handleAuthSuccess(_ stanza: XMPPStanza) {
        print("Auth success!")
        isAuthenticated = true
        
        // Restart the stream after successful authentication
        let restart = """
        <stream:stream to='\(config.backendConfig.xmppWebSocketURL.host!)' 
                       xmlns='jabber:client' 
                       xmlns:stream='http://etherx.jabber.org/streams' 
                       version='1.0'>
        """
        connection.send(text: restart)
        isStreamRestarted = true
    }
    
    private func handlePresence(_ stanza: XMPPStanza) {
        print("Presence stanza received")
        
        // Check if this is from the focus
        if stanza.rawXML.contains("focus") {
            print("!!! FOCUS PRESENCE DETECTED !!!")
        }
    }
    
    private func handleIQ(_ stanza: XMPPStanza) {
        print("IQ stanza received")
        
        // Check for session-initiate (Jingle)
        if stanza.rawXML.contains("session-initiate") {
            print("!!! SESSION-INITIATE (JINGLE) DETECTED !!!")
        }
        
        // Check for Colibri2
        if stanza.rawXML.contains("colibri") || stanza.rawXML.contains("Colibri") {
            print("!!! COLIBRI REFERENCE DETECTED !!!")
        }
        
        // Check for stream features
        if stanza.rawXML.contains("stream:features") {
            handleStreamFeatures(stanza.rawXML)
        }
        
        // Check for bind response
        if stanza.rawXML.contains("<bind") || stanza.rawXML.contains("<jid>") {
            handleBindResponse(stanza.rawXML)
        }
    }
    
    private func handleMessage(_ stanza: XMPPStanza) {
        print("Message stanza received")
    }
    
    private func handleStreamFeatures(_ xml: String) {
        print("Stream features received")
        
        // Check for SASL mechanisms
        if xml.contains("xmlns='urn:ietf:params:xml:ns:xmpp-sasl'") {
            print("SASL features available")
            
            // Start SASL ANONYMOUS authentication
            let authRequest = """
            <auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='ANONYMOUS'/>
            """
            connection.send(text: authRequest)
        }
        
        // Check for bind
        if xml.contains("xmlns='urn:ietf:params:xml:ns:xmpp-bind'") {
            print("Bind features available")
            
            // Send bind request
            let iqId = UUID().uuidString
            let bindRequest = """
            <iq type='set' id='\(iqId)'>
              <bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'>
                <resource>\(config.nick)</resource>
              </bind>
            </iq>
            """
            connection.send(text: bindRequest)
        }
        
        // Check for session
        if xml.contains("xmlns='urn:ietf:params:xml:ns:xmpp-session'") {
            print("Session features available")
            
            // Start session
            let iqId = UUID().uuidString
            let sessionRequest = """
            <iq type='set' id='\(iqId)'>
              <session xmlns='urn:ietf:params:xml:ns:xmpp-session'/>
            </iq>
            """
            connection.send(text: sessionRequest)
        }
    }
    
    private func handleBindResponse(_ xml: String) {
        print("Bind response received")
        
        // Extract JID if available
        if let jidRange = xml.range(of: "<jid>(.*?)</jid>", options: .regularExpression) {
            let jidString = String(xml[jidRange])
            print("Bound JID: \(jidString)")
        }
        
        // After bind, we can join MUC
        joinMUC()
    }
    
    func joinMUC() {
        let roomJID = "\(config.roomName)@\(config.backendConfig.mucDomain)"
        let presence = """
        <presence to='\(roomJID)/\(config.nick)'>
          <x xmlns='http://jabber.org/protocol/muc'/>
        </presence>
        """
        print("Joining MUC: \(roomJID)")
        connection.send(text: presence)
    }
}

// MARK: - Main Execution

print("=== Jitsi Signaling Spike Tool ===")
print("This tool connects to alpha.jitsi.net and captures XMPP/Jingle traffic")
print("Press Ctrl+C to exit\n")

let config = SpikeConfig.alphaTest
let session = XMPPSessionManager(config: config)

session.onStateChange = { state in
    print("State changed: \(state)")
}

// Start connection
session.connect()

// Keep the program running
print("Connecting... Press Ctrl+C to exit")

// Use a run loop to keep the program alive
let runLoop = RunLoop.current
while true {
    runLoop.run(mode: .default, before: .distantFuture)
}
