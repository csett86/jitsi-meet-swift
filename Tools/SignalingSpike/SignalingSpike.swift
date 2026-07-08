//
//  SignalingSpike.swift
//  Phase 0: Signaling Feasibility Spike
//
//  Objective: Prove the real shape of XMPP/Jingle handshake against alpha.jitsi.net
//  This is a throwaway CLI tool for capturing and understanding the signaling protocol.
//

import Foundation
import XMLParsing

// MARK: - Configuration

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

// MARK: - XMPP Stream State

enum XMPPStreamState {
    case disconnected
    case connecting
    case streamOpened
    case authenticated
    case inMUC
}

// MARK: - XMPP Stanza Types

struct XMPPStanza {
    let rawXML: String
    let type: StanzaType
    
    enum StanzaType {
        case streamOpen
        case streamClose
        case authChallenge
        case authSuccess
        case presence
        case iq
        case message
        case unknown
    }
}

// MARK: - XML Stream Parser

class XMPPStreamParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentDepth = 0
    private var buffer = ""
    private var stanzaBuffer = ""
    private var inStanza = false
    private var stanzaDepth = 0
    
    var onStanza: ((XMPPStanza) -> Void)?
    var onStreamOpen: (() -> Void)?
    var onStreamClose: (() -> Void)?
    
    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentDepth += 1
        currentElement = elementName
        
        // Check if this is the start of a stanza
        if currentDepth == 1 && (elementName == "stream" || elementName == "presence" || elementName == "iq" || elementName == "message") {
            inStanza = true
            stanzaDepth = 1
            stanzaBuffer = "<" + elementName
            for (key, value) in attributeDict {
                stanzaBuffer += " \(key)=\"\(value)\""
            }
            stanzaBuffer += ">"
        } else if inStanza {
            stanzaDepth += 1
            stanzaBuffer += "<" + elementName
            for (key, value) in attributeDict {
                stanzaBuffer += " \(key)=\"\(value)\""
            }
            stanzaBuffer += ">"
        }
        
        // Handle stream open
        if elementName == "stream" && currentDepth == 1 && namespaceURI == nil {
            onStreamOpen?()
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inStanza {
            stanzaBuffer += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if inStanza {
            stanzaBuffer += "</" + elementName + ">"
            stanzaDepth -= 1
            
            if stanzaDepth == 0 {
                // Complete stanza
                let stanza = XMPPStanza(rawXML: stanzaBuffer, type: classifyStanza(stanzaBuffer))
                onStanza?(stanza)
                inStanza = false
                stanzaBuffer = ""
            }
        }
        
        // Handle stream close
        if elementName == "stream" && currentDepth == 1 {
            onStreamClose?()
        }
        
        currentDepth -= 1
    }
    
    private func classifyStanza(_ xml: String) -> XMPPStanza.StanzaType {
        if xml.contains("<stream") {
            return .streamOpen
        } else if xml.contains("</stream>") {
            return .streamClose
        } else if xml.contains("<presence") {
            return .presence
        } else if xml.contains("<iq") {
            return .iq
        } else if xml.contains("<message") {
            return .message
        } else if xml.contains("<challenge") || xml.contains("<response") || xml.contains("<success") {
            return .authChallenge
        }
        return .unknown
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("XML Parse Error: \(parseError)")
    }
}

// MARK: - WebSocket Connection

class XMPPWebSocketConnection: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var parser = XMPPStreamParser()
    private var streamId: String?
    private var config: SpikeConfig
    
    var state: XMPPStreamState = .disconnected
    var onStateChange: ((XMPPStreamState) -> Void)?
    var onStanza: ((XMPPStanza) -> Void)?
    
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
        
        urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
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
                    if let data = text.data(using: .utf8) {
                        self.parser.parse(data: data)
                    }
                case .data(let data):
                    self.parser.parse(data: data)
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
    
    var onStanza: ((XMPPStanza) -> Void)?
    var onStateChange: ((XMPPStreamState) -> Void)?
    
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
        print("Received stanza: \(stanza.rawXML.prefix(200))...")
        
        // Handle stream features
        if stanza.rawXML.contains("<stream:features") {
            handleStreamFeatures(stanza.rawXML)
        }
        
        // Handle SASL authentication
        if stanza.rawXML.contains("<challenge") {
            handleAuthChallenge(stanza.rawXML)
        }
        
        // Handle auth success
        if stanza.rawXML.contains("<success") {
            handleAuthSuccess()
        }
        
        // Handle stream restart after auth
        if stanza.rawXML.contains("<stream:stream") && connection.state == .streamOpened {
            // This is a stream restart after authentication
            restartStreamAfterAuth()
        }
    }
    
    private func handleStreamFeatures(_ xml: String) {
        // Check for SASL mechanisms
        if xml.contains("xmlns='urn:ietf:params:xml:ns:xmpp-sasl'") {
            // Start SASL ANONYMOUS authentication
            let authRequest = """
            <auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='ANONYMOUS'/>
            """
            connection.send(text: authRequest)
        }
    }
    
    private func handleAuthChallenge(_ xml: String) {
        // For ANONYMOUS auth, just send empty response
        let response = """
        <response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>
        """
        connection.send(text: response)
    }
    
    private func handleAuthSuccess() {
        // Restart the stream
        let restart = """
        <stream:stream to='\(config.backendConfig.xmppWebSocketURL.host!)' 
                       xmlns='jabber:client' 
                       xmlns:stream='http://etherx.jabber.org/streams' 
                       version='1.0'>
        """
        connection.send(text: restart)
    }
    
    private func restartStreamAfterAuth() {
        // After stream restart, we need to bind the resource
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
    
    func joinMUC() {
        let roomJID = "\(config.roomName)@\(config.backendConfig.mucDomain)"
        let presence = """
        <presence to='\(roomJID)/\(config.nick)'>
          <x xmlns='http://jabber.org/protocol/muc'/>
        </presence>
        """
        connection.send(text: presence)
    }
}

// MARK: - Main

print("=== Jitsi Signaling Spike Tool ===")
print("Connecting to alpha.jitsi.net...")

let config = SpikeConfig.alphaTest
let session = XMPPSessionManager(config: config)

session.onStateChange = { state in
    print("State changed: \(state)")
    
    if state == .streamOpened {
        // After stream is opened, we should get features
        // Then auth will happen automatically
    } else if state == .authenticated {
        // Join MUC after auth
        session.joinMUC()
    }
}

session.onStanza = { stanza in
    print("\n--- Stanza Received ---")
    print("Type: \(stanza.type)")
    print("XML: \(stanza.rawXML)")
    print("---\n")
    
    // Look for specific patterns
    if stanza.rawXML.contains("session-initiate") {
        print("!!! FOUND SESSION-INITIATE !!!")
    }
    
    if stanza.rawXML.contains("focus") {
        print("!!! FOUND FOCUS PRESENCE !!!")
    }
    
    if stanza.rawXML.contains("jingle") {
        print("!!! FOUND JINGLE STANZA !!!")
    }
    
    if stanza.rawXML.contains("colibri") || stanza.rawXML.contains("Colibri") {
        print("!!! FOUND COLIBRI REFERENCE !!!")
    }
}

session.connect()

// Keep the program running
RunLoop.main.run()
