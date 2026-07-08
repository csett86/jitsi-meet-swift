//
//  XMPPWebSocketConnection.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation
import Combine

/// Connection state for XMPP over WebSocket
public enum XMPPConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case authenticated
    case failed(Error)
}

/// Low-level WebSocket connection for XMPP
public class XMPPWebSocketConnection: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let url: URL
    private let parser = XMPPStanzaParser()
    
    @Published public private(set) var state: XMPPConnectionState = .disconnected
    
    public var onStanza: ((XMPPStanza) -> Void)?
    public var onStreamOpen: (() -> Void)?
    public var onStreamClose: (() -> Void)?
    
    // MARK: - Initialization
    
    public init(websocketURL: URL) {
        self.url = websocketURL
        super.init()
        
        setupParser()
    }
    
    // MARK: - Setup
    
    private func setupParser() {
        parser.onStanza = { [weak self] stanza in
            self?.handleStanza(stanza)
        }
        
        parser.onStreamOpen = { [weak self] in
            self?.state = .connected
            self?.onStreamOpen?()
        }
        
        parser.onStreamClose = { [weak self] in
            self?.state = .disconnected
            self?.onStreamClose?()
        }
    }
    
    // MARK: - Connection Management
    
    public func connect() {
        guard state == .disconnected || state == .failed(_) else {
            return
        }
        
        state = .connecting
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        urlSession = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        startListening()
    }
    
    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        state = .disconnected
    }
    
    // MARK: - Message Sending
    
    public func send(_ text: String) {
        guard state == .connected || state == .authenticated else {
            return
        }
        
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    public func send(data: Data) {
        guard state == .connected || state == .authenticated else {
            return
        }
        
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    // MARK: - Message Receiving
    
    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.startListening()
            case .failure(let error):
                self.state = .failed(error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8) {
                parser.parse(data: data)
            }
        case .data(let data):
            parser.parse(data: data)
        @unknown default:
            break
        }
    }
    
    // MARK: - Stanza Handling
    
    private func handleStanza(_ stanza: XMPPStanza) {
        onStanza?(stanza)
    }
    
    // MARK: - Stream Management
    
    public func restartStream() {
        // Send stream restart after SASL authentication
        let streamOpen = """
        <stream:stream to='\(url.host ?? "")' 
                       xmlns='jabber:client' 
                       xmlns:stream='http://etherx.jabber.org/streams' 
                       version='1.0'>
        """
        send(streamOpen)
    }
}

// MARK: - Stanza Parser

public enum StanzaType {
    case streamOpen
    case streamClose
    case presence
    case iq
    case message
    case unknown
}

public struct XMPPStanza {
    public let rawXML: String
    public let type: StanzaType
    public let timestamp: Date
    
    public init(rawXML: String, type: StanzaType) {
        self.rawXML = rawXML
        self.type = type
        self.timestamp = Date()
    }
}

public class XMPPStanzaParser: NSObject, XMLParserDelegate {
    
    public var onStanza: ((XMPPStanza) -> Void)?
    public var onStreamOpen: (() -> Void)?
    public var onStreamClose: (() -> Void)?
    
    private var buffer = ""
    private var depth = 0
    private var inStanza = false
    private var stanzaStartIndex: String.Index?
    
    public func parse(data: Data) {
        if let string = String(data: data, encoding: .utf8) {
            parse(string: string)
        }
    }
    
    public func parse(string: String) {
        var remaining = string
        
        while !remaining.isEmpty {
            if let stanza = extractNextStanza(from: remaining) {
                processStanza(stanza)
                
                // Remove processed stanza from remaining
                if let range = remaining.range(of: stanza) {
                    remaining.removeSubrange(range)
                } else {
                    remaining = ""
                }
            } else {
                // No complete stanza, might be partial data
                break
            }
        }
    }
    
    private func extractNextStanza(from string: String) -> String? {
        // Look for opening tags
        let openingTags = [
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
        
        for tag in openingTags {
            if let range = string.range(of: tag) {
                let startIndex = range.lowerBound
                let substring = String(string[startIndex...])
                
                if let endIndex = findEndTag(for: substring, openingTag: tag) {
                    let endRange = string.index(startIndex, offsetBy: endIndex.utf16Offset(from: substring.startIndex), limitedBy: string.endIndex)
                    if let endRange = endRange {
                        return String(string[startIndex..<endRange])
                    }
                }
            }
        }
        
        return nil
    }
    
    private func findEndTag(for substring: String, openingTag: String) -> String.Index? {
        // Check for self-closing
        if let range = substring.range(of: "/>") {
            return range.upperBound
        }
        
        // Extract tag name
        let tagName: String
        if openingTag == "<stream:" {
            tagName = "stream:stream"
        } else {
            tagName = String(openingTag.dropFirst(1))
        }
        
        // Look for closing tag
        let closingTag = "</\(tagName)>"
        if let range = substring.range(of: closingTag) {
            return range.upperBound
        }
        
        return nil
    }
    
    private func processStanza(_ xml: String) {
        let type = classifyStanza(xml)
        
        switch type {
        case .streamOpen:
            onStreamOpen?()
        case .streamClose:
            onStreamClose?()
        default:
            break
        }
        
        let stanza = XMPPStanza(rawXML: xml, type: type)
        onStanza?(stanza)
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
        }
        return .unknown
    }
}
