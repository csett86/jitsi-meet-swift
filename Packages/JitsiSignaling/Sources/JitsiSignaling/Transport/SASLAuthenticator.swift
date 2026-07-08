//
//  SASLAuthenticator.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation

/// SASL authentication mechanisms
public enum SASLMechanism: String {
    case anonymous = "ANONYMOUS"
    case plain = "PLAIN"
    case scramSHA1 = "SCRAM-SHA-1"
}

/// SASL authentication state
public enum SASLState {
    case initial
    case challengeReceived(Data?)
    case responseSent
    case success
    case failure(Error)
}

/// Handles SASL authentication for XMPP
public class SASLAuthenticator {
    
    private let connection: XMPPWebSocketConnection
    private let mechanism: SASLMechanism
    private var state: SASLState = .initial
    private var challenge: Data?
    
    public var onSuccess: (() -> Void)?
    public var onFailure: ((Error) -> Void)?
    public var onChallenge: ((Data?) -> Void)?
    
    public init(connection: XMPPWebSocketConnection, mechanism: SASLMechanism = .anonymous) {
        self.connection = connection
        self.mechanism = mechanism
        
        setupHandlers()
    }
    
    private func setupHandlers() {
        connection.onStanza = { [weak self] stanza in
            self?.handleStanza(stanza)
        }
    }
    
    public func start() {
        guard case .connected = connection.state else {
            onFailure?(NSError(domain: "XMPP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
            return
        }
        
        state = .initial
        
        // Send auth request
        let authRequest = """
        <auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='\(mechanism.rawValue)'/>
        """
        connection.send(authRequest)
        state = .responseSent
    }
    
    private func handleStanza(_ stanza: XMPPStanza) {
        switch stanza.type {
        case .streamClose:
            break
        
        case .iq, .presence, .message, .unknown:
            // Not SASL-related
            break
            
        default:
            // Check for SASL-specific elements
            if stanza.rawXML.contains("<challenge") {
                handleChallenge(stanza.rawXML)
            } else if stanza.rawXML.contains("<success") {
                handleSuccess()
            } else if stanza.rawXML.contains("<failure") {
                handleFailure(stanza.rawXML)
            }
        }
    }
    
    private func handleChallenge(_ xml: String) {
        // Extract challenge data if present
        var challengeData: Data?
        
        if let range = xml.range(of: ">(.*?)</challenge", options: .regularExpression) {
            let content = String(xml[range])
            challengeData = Data(content.utf8)
        }
        
        state = .challengeReceived(challengeData)
        challenge = challengeData
        onChallenge?(challengeData)
        
        // For ANONYMOUS, send empty response
        if mechanism == .anonymous {
            let response = """
            <response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>
            """
            connection.send(response)
            state = .responseSent
        }
    }
    
    private func handleSuccess() {
        state = .success
        onSuccess?()
    }
    
    private func handleFailure(_ xml: String) {
        let error = NSError(domain: "SASL", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "SASL authentication failed",
            NSLocalizedFailureReasonErrorKey: xml
        ])
        state = .failure(error)
        onFailure?(error)
    }
    
    /// Send response to challenge (for non-ANONYMOUS mechanisms)
    public func sendResponse(_ response: String) {
        let responseXML = """
        <response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>\(response)</response>
        """
        connection.send(responseXML)
        state = .responseSent
    }
    
    /// Abort SASL authentication
    public func abort() {
        let abortXML = """
        <abort xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>
        """
        connection.send(abortXML)
        state = .initial
    }
}
