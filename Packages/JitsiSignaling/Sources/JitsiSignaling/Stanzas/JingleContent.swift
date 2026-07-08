//
//  JingleContent.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation

// MARK: - Jingle Namespace

public enum JingleNamespace: String {
    case jingle1 = "urn:xmpp:jingle:1"
    case jingleAppsRTP = "urn:xmpp:jingle:apps:rtp:1"
    case jingleTransportsICEUDP = "urn:xmpp:jingle:transports:ice-udp:1"
    case jingleTransportsRawUDP = "urn:xmpp:jingle:transports:raw-udp:1"
    case jingleDTLS = "urn:xmpp:jingle:apps:dtls:0"
}

// MARK: - Jingle Action

public enum JingleAction: String {
    case sessionInitiate = "session-initiate"
    case sessionAccept = "session-accept"
    case sessionTerminate = "session-terminate"
    case sessionInfo = "session-info"
    case contentAdd = "content-add"
    case contentAccept = "content-accept"
    case contentReject = "content-reject"
    case contentRemove = "content-remove"
    case contentModify = "content-modify"
}

// MARK: - Jingle Sender

public enum JingleSender: String {
    case both
    case initiator
    case responder
    case none
}

// MARK: - ICE Candidate

public struct ICECandidate {
    public let component: Int
    public let foundation: String
    public let generation: Int
    public let id: String
    public let ip: String
    public let network: Int
    public let port: Int
    public let priority: Int
    public let protocolType: String
    public let type: String  // host, srflx, relay, prflx
    
    public init(
        component: Int,
        foundation: String,
        generation: Int,
        id: String,
        ip: String,
        network: Int,
        port: Int,
        priority: Int,
        protocolType: String,
        type: String
    ) {
        self.component = component
        self.foundation = foundation
        self.generation = generation
        self.id = id
        self.ip = ip
        self.network = network
        self.port = port
        self.priority = priority
        self.protocolType = protocolType
        self.type = type
    }
    
    public func toSDP() -> String {
        return "\(foundation) \(component) \(protocolType) \(priority) \(ip) \(port) typ \(type) generation \(generation) network-id \(network) network-cost 50"
    }
}

// MARK: - ICE Transport

public struct ICETransport {
    public let ufrag: String
    public let pwd: String
    public let fingerprint: String
    public let fingerprintAlgorithm: String
    public let candidates: [ICECandidate]
    
    public init(
        ufrag: String,
        pwd: String,
        fingerprint: String,
        fingerprintAlgorithm: String,
        candidates: [ICECandidate] = []
    ) {
        self.ufrag = ufrag
        self.pwd = pwd
        self.fingerprint = fingerprint
        self.fingerprintAlgorithm = fingerprintAlgorithm
        self.candidates = candidates
    }
}

// MARK: - RTP Description

public struct RTPDescription {
    public let media: String  // audio or video
    public let ssrc: UInt32?
    public let payloadTypes: [PayloadType]
    public let rtcpMux: Bool
    public let rtcpRtcp: Bool
    
    public init(
        media: String,
        ssrc: UInt32? = nil,
        payloadTypes: [PayloadType] = [],
        rtcpMux: Bool = true,
        rtcpRtcp: Bool = false
    ) {
        self.media = media
        self.ssrc = ssrc
        self.payloadTypes = payloadTypes
        self.rtcpMux = rtcpMux
        self.rtcpRtcp = rtcpRtcp
    }
}

// MARK: - Payload Type

public struct PayloadType {
    public let id: Int
    public let name: String
    public let clockrate: Int
    public let channels: Int?
    public let parameters: [String: String]
    
    public init(
        id: Int,
        name: String,
        clockrate: Int,
        channels: Int? = nil,
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.clockrate = clockrate
        self.channels = channels
        self.parameters = parameters
    }
}

// MARK: - Jingle Content

public struct JingleContent {
    public let creator: String  // initiator or responder
    public let name: String
    public let senders: JingleSender
    public let description: RTPDescription?
    public let transport: ICETransport?
    
    public init(
        creator: String,
        name: String,
        senders: JingleSender,
        description: RTPDescription? = nil,
        transport: ICETransport? = nil
    ) {
        self.creator = creator
        self.name = name
        self.senders = senders
        self.description = description
        self.transport = transport
    }
}

// MARK: - Jingle Session

public struct JingleSession {
    public let action: JingleAction
    public let initiator: String
    public let responder: String?
    public let sid: String
    public let contents: [JingleContent]
    
    public init(
        action: JingleAction,
        initiator: String,
        responder: String? = nil,
        sid: String,
        contents: [JingleContent] = []
    ) {
        self.action = action
        self.initiator = initiator
        self.responder = responder
        self.sid = sid
        self.contents = contents
    }
}

// MARK: - Jingle Parser

public class JingleParser {
    
    public static func parseSession(from xml: String) -> JingleSession? {
        var action: JingleAction?
        var initiator: String?
        var responder: String?
        var sid: String?
        var contents: [JingleContent] = []
        
        // Extract action
        if let range = xml.range(of: "action='([^']*)'", options: .regularExpression) {
            let actionString = String(xml[range])
            action = JingleAction(rawValue: actionString)
        }
        
        // Extract initiator
        if let range = xml.range(of: "initiator='([^']*)'", options: .regularExpression) {
            initiator = String(xml[range])
        }
        
        // Extract responder
        if let range = xml.range(of: "responder='([^']*)'", options: .regularExpression) {
            responder = String(xml[range])
        }
        
        // Extract sid
        if let range = xml.range(of: "sid='([^']*)'", options: .regularExpression) {
            sid = String(xml[range])
        }
        
        guard let action = action, let initiator = initiator, let sid = sid else {
            return nil
        }
        
        // Parse contents
        if let range = xml.range(of: "<content[^>]*>.*?</content>", options: [.regularExpression, .dotMatchesLineSeparators]) {
            let contentXML = String(xml[range])
            if let content = parseContent(from: contentXML) {
                contents.append(content)
            }
        }
        
        // Parse all contents (there might be multiple)
        let contentPattern = "<content([^>]*)>.*?</content>"
        let regex = try? NSRegularExpression(pattern: contentPattern, options: [.dotMatchesLineSeparators])
        if let regex = regex {
            let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                let range = Range(match.range, in: xml)
                let contentXML = String(xml[range])
                if let content = parseContent(from: contentXML) {
                    contents.append(content)
                }
            }
        }
        
        return JingleSession(
            action: action,
            initiator: initiator,
            responder: responder,
            sid: sid,
            contents: contents
        )
    }
    
    private static func parseContent(from xml: String) -> JingleContent? {
        var creator: String?
        var name: String?
        var senders: JingleSender?
        var description: RTPDescription?
        var transport: ICETransport?
        
        // Extract creator
        if let range = xml.range(of: "creator='([^']*)'", options: .regularExpression) {
            creator = String(xml[range])
        }
        
        // Extract name
        if let range = xml.range(of: "name='([^']*)'", options: .regularExpression) {
            name = String(xml[range])
        }
        
        // Extract senders
        if let range = xml.range(of: "senders='([^']*)'", options: .regularExpression) {
            let sendersString = String(xml[range])
            senders = JingleSender(rawValue: sendersString)
        }
        
        guard let creator = creator, let name = name, let senders = senders else {
            return nil
        }
        
        // Parse description
        if let descRange = xml.range(of: "<description[^>]*>.*?</description>", options: [.regularExpression, .dotMatchesLineSeparators]) {
            let descXML = String(xml[descRange])
            description = parseDescription(from: descXML)
        }
        
        // Parse transport
        if let transRange = xml.range(of: "<transport[^>]*>.*?</transport>", options: [.regularExpression, .dotMatchesLineSeparators]) {
            let transXML = String(xml[transRange])
            transport = parseTransport(from: transXML)
        }
        
        return JingleContent(
            creator: creator,
            name: name,
            senders: senders,
            description: description,
            transport: transport
        )
    }
    
    private static func parseDescription(from xml: String) -> RTPDescription? {
        var media: String?
        var ssrc: UInt32?
        var payloadTypes: [PayloadType] = []
        var rtcpMux = true
        var rtcpRtcp = false
        
        // Extract media
        if let range = xml.range(of: "media='([^']*)'", options: .regularExpression) {
            media = String(xml[range])
        }
        
        // Extract SSRC
        if let range = xml.range(of: "ssrc='([^']*)'", options: .regularExpression) {
            let ssrcString = String(xml[range])
            ssrc = UInt32(ssrcString)
        }
        
        // Check for rtcp-mux
        if xml.contains("rtcp-mux") {
            rtcpMux = true
        }
        
        guard let media = media else {
            return nil
        }
        
        return RTPDescription(
            media: media,
            ssrc: ssrc,
            payloadTypes: payloadTypes,
            rtcpMux: rtcpMux,
            rtcpRtcp: rtcpRtcp
        )
    }
    
    private static func parseTransport(from xml: String) -> ICETransport? {
        var ufrag: String?
        var pwd: String?
        var fingerprint: String?
        var fingerprintAlgorithm: String?
        var candidates: [ICECandidate] = []
        
        // Extract ufrag
        if let range = xml.range(of: "ufrag='([^']*)'", options: .regularExpression) {
            ufrag = String(xml[range])
        }
        
        // Extract pwd
        if let range = xml.range(of: "pwd='([^']*)'", options: .regularExpression) {
            pwd = String(xml[range])
        }
        
        // Extract fingerprint
        if let range = xml.range(of: "fingerprint='([^']*)'", options: .regularExpression) {
            fingerprint = String(xml[range])
        }
        
        // Extract fingerprint algorithm
        if let range = xml.range(of: "fingerprint-algorithm='([^']*)'", options: .regularExpression) {
            fingerprintAlgorithm = String(xml[range])
        }
        
        guard let ufrag = ufrag, let pwd = pwd, let fingerprint = fingerprint, let fingerprintAlgorithm = fingerprintAlgorithm else {
            return nil
        }
        
        // Parse candidates
        let candidatePattern = "<candidate([^>]*)/>"
        let regex = try? NSRegularExpression(pattern: candidatePattern, options: [])
        if let regex = regex {
            let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                let range = Range(match.range, in: xml)
                let candidateXML = String(xml[range])
                if let candidate = parseCandidate(from: candidateXML) {
                    candidates.append(candidate)
                }
            }
        }
        
        return ICETransport(
            ufrag: ufrag,
            pwd: pwd,
            fingerprint: fingerprint,
            fingerprintAlgorithm: fingerprintAlgorithm,
            candidates: candidates
        )
    }
    
    private static func parseCandidate(from xml: String) -> ICECandidate? {
        var component: Int?
        var foundation: String?
        var generation: Int?
        var id: String?
        var ip: String?
        var network: Int?
        var port: Int?
        var priority: Int?
        var protocolType: String?
        var type: String?
        
        // Extract component
        if let range = xml.range(of: "component='([^']*)'", options: .regularExpression) {
            let compString = String(xml[range])
            component = Int(compString)
        }
        
        // Extract foundation
        if let range = xml.range(of: "foundation='([^']*)'", options: .regularExpression) {
            foundation = String(xml[range])
        }
        
        // Extract generation
        if let range = xml.range(of: "generation='([^']*)'", options: .regularExpression) {
            let genString = String(xml[range])
            generation = Int(genString)
        }
        
        // Extract id
        if let range = xml.range(of: "id='([^']*)'", options: .regularExpression) {
            id = String(xml[range])
        }
        
        // Extract ip
        if let range = xml.range(of: "ip='([^']*)'", options: .regularExpression) {
            ip = String(xml[range])
        }
        
        // Extract network
        if let range = xml.range(of: "network='([^']*)'", options: .regularExpression) {
            let netString = String(xml[range])
            network = Int(netString)
        }
        
        // Extract port
        if let range = xml.range(of: "port='([^']*)'", options: .regularExpression) {
            let portString = String(xml[range])
            port = Int(portString)
        }
        
        // Extract priority
        if let range = xml.range(of: "priority='([^']*)'", options: .regularExpression) {
            let prioString = String(xml[range])
            priority = Int(prioString)
        }
        
        // Extract protocol
        if let range = xml.range(of: "protocol='([^']*)'", options: .regularExpression) {
            protocolType = String(xml[range])
        }
        
        // Extract type
        if let range = xml.range(of: "type='([^']*)'", options: .regularExpression) {
            type = String(xml[range])
        }
        
        guard let component = component,
              let foundation = foundation,
              let generation = generation,
              let id = id,
              let ip = ip,
              let network = network,
              let port = port,
              let priority = priority,
              let protocolType = protocolType,
              let type = type else {
            return nil
        }
        
        return ICECandidate(
            component: component,
            foundation: foundation,
            generation: generation,
            id: id,
            ip: ip,
            network: network,
            port: port,
            priority: priority,
            protocolType: protocolType,
            type: type
        )
    }
}
