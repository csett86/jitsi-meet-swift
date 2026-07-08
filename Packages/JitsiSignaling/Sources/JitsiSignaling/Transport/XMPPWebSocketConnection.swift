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
    case reconnecting(timeout: TimeInterval, attempt: Int)
}

/// Configuration for XMPP WebSocket connection
public struct XMPPWebSocketConfiguration {
    public let websocketURL: URL
    public let reconnectEnabled: Bool
    public let maxReconnectAttempts: Int
    public let reconnectBaseTimeout: TimeInterval
    public let reconnectMaxTimeout: TimeInterval
    public let pingInterval: TimeInterval
    public let timeoutInterval: TimeInterval
    
    public init(
        websocketURL: URL,
        reconnectEnabled: Bool = true,
        maxReconnectAttempts: Int = 5,
        reconnectBaseTimeout: TimeInterval = 1.0,
        reconnectMaxTimeout: TimeInterval = 30.0,
        pingInterval: TimeInterval = 30.0,
        timeoutInterval: TimeInterval = 30.0
    ) {
        self.websocketURL = websocketURL
        self.reconnectEnabled = reconnectEnabled
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectBaseTimeout = reconnectBaseTimeout
        self.reconnectMaxTimeout = reconnectMaxTimeout
        self.pingInterval = pingInterval
        self.timeoutInterval = timeoutInterval
    }
}

/// Low-level WebSocket connection for XMPP
public class XMPPWebSocketConnection: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let config: XMPPWebSocketConfiguration
    private let parser = XMPPStanzaParser()
    
    private var reconnectAttempt: Int = 0
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var lastPingTime: Date?
    private var lastPongTime: Date?
    
    @Published public private(set) var state: XMPPConnectionState = .disconnected
    
    public var onStanza: ((XMPPStanza) -> Void)?
    public var onStreamOpen: (() -> Void)?
    public var onStreamClose: (() -> Void)?
    public var onConnectionError: ((Error) -> Void)?
    
    // MARK: - Initialization
    
    public init(config: XMPPWebSocketConfiguration) {
        self.config = config
        super.init()
        
        setupParser()
    }
    
    public convenience init(websocketURL: URL) {
        let config = XMPPWebSocketConfiguration(websocketURL: websocketURL)
        self.init(config: config)
    }
    
    deinit {
        disconnect()
        reconnectTimer?.invalidate()
        pingTimer?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setupParser() {
        parser.onStanza = { [weak self] stanza in
            self?.handleStanza(stanza)
        }
        
        parser.onStreamOpen = { [weak self] in
            self?.handleStreamOpen()
        }
        
        parser.onStreamClose = { [weak self] in
            self?.handleStreamClose()
        }
    }
    
    // MARK: - Connection Management
    
    public func connect() {
        guard state == .disconnected || state == .failed(_) || state == .left else {
            return
        }
        
        state = .connecting
        reconnectAttempt = 0
        
        createConnection()
    }
    
    public func disconnect() {
        cancelReconnectTimer()
        cancelPingTimer()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        if case .reconnecting = state {
            // Don't transition to disconnected if we're intentionally disconnecting
        } else {
            state = .disconnected
        }
    }
    
    private func createConnection() {
        var request = URLRequest(url: config.websocketURL)
        request.timeoutInterval = config.timeoutInterval
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        sessionConfig.timeoutIntervalForRequest = config.timeoutInterval
        sessionConfig.timeoutIntervalForResource = config.timeoutInterval
        
        urlSession = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        startListening()
        startPingTimer()
    }
    
    // MARK: - Reconnection
    
    private func scheduleReconnect() {
        guard config.reconnectEnabled && reconnectAttempt < config.maxReconnectAttempts else {
            state = .failed(NSError(domain: "XMPP", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Max reconnection attempts reached"
            ]))
            return
        }
        
        reconnectAttempt += 1
        
        // Calculate exponential backoff
        let timeout = min(
            config.reconnectBaseTimeout * pow(2.0, Double(reconnectAttempt - 1)),
            config.reconnectMaxTimeout
        )
        
        state = .reconnecting(timeout: timeout, attempt: reconnectAttempt)
        
        // Schedule reconnect
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(
            withTimeInterval: timeout,
            repeats: false
        ) { [weak self] _ in
            self?.reconnect()
        }
    }
    
    private func reconnect() {
        cancelReconnectTimer()
        
        // Clean up old connection
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        // Reconnect
        state = .connecting
        createConnection()
    }
    
    private func cancelReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // MARK: - Ping/Pong
    
    private func startPingTimer() {
        cancelPingTimer()
        
        pingTimer = Timer.scheduledTimer(
            withTimeInterval: config.pingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func sendPing() {
        guard state == .connected || state == .authenticated else {
            return
        }
        
        lastPingTime = Date()
        
        // Send whitespace ping (XMPP keepalive)
        send(" ")
    }
    
    private func handlePong() {
        lastPongTime = Date()
    }
    
    private func cancelPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    // MARK: - Message Sending
    
    public func send(_ text: String) {
        guard state == .connected || state == .authenticated else {
            return
        }
        
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                print("WebSocket send error: \(error)")
                self?.onConnectionError?(error)
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
                self?.onConnectionError?(error)
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
                self.handleReceiveError(error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            // Check for pong (whitespace response)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handlePong()
                return
            }
            
            if let data = text.data(using: .utf8) {
                parser.parse(data: data)
            }
        case .data(let data):
            parser.parse(data: data)
        @unknown default:
            break
        }
    }
    
    private func handleReceiveError(_ error: Error) {
        onConnectionError?(error)
        
        // Check if we should reconnect
        if case .connected = state || case .authenticated = state {
            scheduleReconnect()
        } else {
            state = .failed(error)
        }
    }
    
    // MARK: - Stanza Handling
    
    private func handleStanza(_ stanza: XMPPStanza) {
        onStanza?(stanza)
    }
    
    private func handleStreamOpen() {
        // Reset reconnect attempt on successful connection
        reconnectAttempt = 0
        
        state = .connected
        onStreamOpen?()
    }
    
    private func handleStreamClose() {
        cancelPingTimer()
        
        // Check if this is an intentional disconnect
        if case .disconnected = state {
            return
        }
        
        onStreamClose?()
        
        // Attempt to reconnect
        scheduleReconnect()
    }
    
    // MARK: - Stream Management
    
    public func restartStream() {
        // Send stream restart after SASL authentication
        let streamOpen = """
        <stream:stream to='\(config.websocketURL.host ?? "")' 
                       xmlns='jabber:client' 
                       xmlns:stream='http://etherx.jabber.org/streams' 
                       version='1.0'>
        """
        send(streamOpen)
    }
    
    // MARK: - State Management
    
    public func setAuthenticated() {
        state = .authenticated
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
