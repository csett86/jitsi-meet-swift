//
//  TURNDiscovery.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation

// MARK: - TURN Server Info

public struct TURNServer {
    public let hostname: String
    public let port: Int
    public let transport: String  // udp, tcp, tls
    public let username: String?
    public let credential: String?
    public let credentialType: String?  // password, token, oauth
    
    public init(
        hostname: String,
        port: Int,
        transport: String,
        username: String? = nil,
        credential: String? = nil,
        credentialType: String? = nil
    ) {
        self.hostname = hostname
        self.port = port
        self.transport = transport
        self.username = username
        self.credential = credential
        self.credentialType = credentialType
    }
    
    /// Convert to ICE server format for WebRTC
    public func toICEServer() -> [String: Any] {
        var server: [String: Any] = [
            "urls": "turn:\(hostname):\(port)?transport=\(transport)",
            "username": username ?? "",
            "credential": credential ?? ""
        ]
        
        if let credentialType = credentialType {
            server["credentialType"] = credentialType
        }
        
        return server
    }
}

// MARK: - External Service Discovery (XEP-0215)

public class TURNDiscovery {
    
    private let connection: XMPPWebSocketConnection
    private var pendingRequests: [String: (Result<[TURNServer], Error>) -> Void] = [:]
    private var discoveredServers: [TURNServer] = []
    
    public var onServersDiscovered: (([TURNServer]) -> Void)?
    
    public init(connection: XMPPWebSocketConnection) {
        self.connection = connection
    }
    
    /// Discover TURN servers from the XMPP server
    public func discover() async throws -> [TURNServer] {
        return try await withCheckedThrowingContinuation { continuation in
            let iqId = UUID().uuidString
            
            // Store the continuation
            pendingRequests[iqId] = { result in
                continuation.resume(with: result)
            }
            
            // Send disco#info request for external services
            let discoRequest = """
            <iq type='get' id='\(iqId)'>
              <query xmlns='http://jabber.org/protocol/disco#info' 
                     node='http://jabber.org/protocol/bytestreams'/
              >
            </iq>
            """
            connection.send(discoRequest)
        }
    }
    
    /// Query a specific TURN service
    public func queryService(jid: String) async throws -> [TURNServer] {
        return try await withCheckedThrowingContinuation { continuation in
            let iqId = UUID().uuidString
            
            pendingRequests[iqId] = { result in
                continuation.resume(with: result)
            }
            
            // Send disco#info request to the TURN service
            let discoRequest = """
            <iq type='get' id='\(iqId)' to='\(jid)'>
              <query xmlns='http://jabber.org/protocol/disco#info'/>
            </iq>
            """
            connection.send(discoRequest)
        }
    }
    
    /// Handle incoming IQ responses
    public func handleIQ(_ iq: IQ) {
        guard let iqId = pendingRequests.keys.first(where: { $0 == iq.id }) else {
            return
        }
        
        guard let continuation = pendingRequests.removeValue(forKey: iqId) else {
            return
        }
        
        if iq.type == .result {
            // Parse the response
            let servers = parseTURNResponse(iq)
            discoveredServers = servers
            continuation(.success(servers))
            onServersDiscovered?(servers)
        } else if iq.type == .error {
            let error = NSError(domain: "TURN", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to discover TURN servers"
            ])
            continuation(.failure(error))
        }
    }
    
    private func parseTURNResponse(_ iq: IQ) -> [TURNServer] {
        var servers: [TURNServer] = []
        
        // Parse the response for TURN service information
        // This is a simplified parser - in production, use proper XML parsing
        
        let xml = iq.toXML()
        
        // Look for service entries
        let servicePattern = "<service[^>]*>"
        let regex = try? NSRegularExpression(pattern: servicePattern, options: [])
        if let regex = regex {
            let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                let range = Range(match.range, in: xml)
                let serviceXML = String(xml[range])
                if let server = parseService(from: serviceXML) {
                    servers.append(server)
                }
            }
        }
        
        return servers
    }
    
    private func parseService(from xml: String) -> TURNServer? {
        var hostname: String?
        var port: Int?
        var transport: String?
        var username: String?
        var credential: String?
        var credentialType: String?
        
        // Extract hostname
        if let range = xml.range(of: "hostname='([^']*)'", options: .regularExpression) {
            hostname = String(xml[range])
        }
        
        // Extract port
        if let range = xml.range(of: "port='([^']*)'", options: .regularExpression) {
            let portString = String(xml[range])
            port = Int(portString)
        }
        
        // Extract transport
        if let range = xml.range(of: "transport='([^']*)'", options: .regularExpression) {
            transport = String(xml[range])
        }
        
        // Extract username
        if let range = xml.range(of: "username='([^']*)'", options: .regularExpression) {
            username = String(xml[range])
        }
        
        // Extract credential
        if let range = xml.range(of: "password='([^']*)'", options: .regularExpression) {
            credential = String(xml[range])
            credentialType = "password"
        }
        
        guard let hostname = hostname, let port = port, let transport = transport else {
            return nil
        }
        
        return TURNServer(
            hostname: hostname,
            port: port,
            transport: transport,
            username: username,
            credential: credential,
            credentialType: credentialType
        )
    }
    
    /// Get the discovered TURN servers
    public func getDiscoveredServers() -> [TURNServer] {
        return discoveredServers
    }
    
    /// Clear discovered servers
    public func clearDiscoveredServers() {
        discoveredServers.removeAll()
    }
}
