//
//  Stanza.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation

// MARK: - Base Stanza Protocol

public protocol XMPPStanzaProtocol {
    var elementName: String { get }
    var namespace: String { get }
    var attributes: [String: String] { get }
    var children: [XMPPStanzaProtocol] { get }
    
    func toXML() -> String
}

// MARK: - Presence Stanza

public enum PresenceType: String {
    case available = "available"
    case unavailable = "unavailable"
    case subscribe = "subscribe"
    case subscribed = "subscribed"
    case unsubscribe = "unsubscribe"
    case unsubscribed = "unsubscribed"
    case probe = "probe"
    case error = "error"
}

public enum PresenceShow: String {
    case away = "away"
    case chat = "chat"
    case dnd = "dnd"  // Do Not Disturb
    case xa = "xa"    // Extended Away
}

public struct Presence: XMPPStanzaProtocol {
    public let type: PresenceType?
    public let show: PresenceShow?
    public let status: String?
    public let to: String?
    public let from: String?
    public let elementName: String = "presence"
    public let namespace: String = "jabber:client"
    public let attributes: [String: String]
    public let children: [XMPPStanzaProtocol]
    
    // Jitsi-specific extensions
    public let videoType: String?
    public let region: String?
    public let statsId: String?
    public let isDominantSpeaker: Bool
    
    public init(
        type: PresenceType? = nil,
        show: PresenceShow? = nil,
        status: String? = nil,
        to: String? = nil,
        from: String? = nil,
        attributes: [String: String] = [:],
        children: [XMPPStanzaProtocol] = [],
        videoType: String? = nil,
        region: String? = nil,
        statsId: String? = nil,
        isDominantSpeaker: Bool = false
    ) {
        self.type = type
        self.show = show
        self.status = status
        self.to = to
        self.from = from
        self.attributes = attributes
        self.children = children
        self.videoType = videoType
        self.region = region
        self.statsId = statsId
        self.isDominantSpeaker = isDominantSpeaker
    }
    
    public func toXML() -> String {
        var xml = "<presence"
        
        if let type = type {
            xml += " type='\(type.rawValue)'"
        }
        
        if let to = to {
            xml += " to='\(to)'"
        }
        
        if let from = from {
            xml += " from='\(from)'"
        }
        
        for (key, value) in attributes {
            xml += " \(key)='\(value)'"
        }
        
        xml += ">"
        
        if let show = show {
            xml += "<show>\(show.rawValue)</show>"
        }
        
        if let status = status {
            xml += "<status>\(status)</status>"
        }
        
        for child in children {
            xml += child.toXML()
        }
        
        // Jitsi-specific extensions
        if let videoType = videoType {
            xml += "<video-type xmlns='http://jitsi.org/protocol/videotype'>\(videoType)</video-type>"
        }
        
        if let region = region {
            xml += "<region xmlns='http://jitsi.org/protocol/region'>\(region)</region>"
        }
        
        if let statsId = statsId {
            xml += "<stats-id xmlns='http://jitsi.org/protocol/stats'>\(statsId)</stats-id>"
        }
        
        if isDominantSpeaker {
            xml += "<dominant-speaker xmlns='http://jitsi.org/protocol/dominantspeaker'/>"
        }
        
        xml += "</presence>"
        return xml
    }
}

// MARK: - IQ Stanza

public enum IQType: String {
    case get = "get"
    case set = "set"
    case result = "result"
    case error = "error"
}

public struct IQ: XMPPStanzaProtocol {
    public let type: IQType
    public let id: String
    public let to: String?
    public let from: String?
    public let elementName: String = "iq"
    public let namespace: String = "jabber:client"
    public let attributes: [String: String]
    public let children: [XMPPStanzaProtocol]
    
    public init(
        type: IQType,
        id: String,
        to: String? = nil,
        from: String? = nil,
        attributes: [String: String] = [:],
        children: [XMPPStanzaProtocol] = []
    ) {
        self.type = type
        self.id = id
        self.to = to
        self.from = from
        self.attributes = attributes
        self.children = children
    }
    
    public func toXML() -> String {
        var xml = "<iq type='\(type.rawValue)' id='\(id)'"
        
        if let to = to {
            xml += " to='\(to)'"
        }
        
        if let from = from {
            xml += " from='\(from)'"
        }
        
        for (key, value) in attributes {
            xml += " \(key)='\(value)'"
        }
        
        xml += ">"
        
        for child in children {
            xml += child.toXML()
        }
        
        xml += "</iq>"
        return xml
    }
}

// MARK: - Message Stanza

public enum MessageType: String {
    case normal = "normal"
    case chat = "chat"
    case groupchat = "groupchat"
    case headline = "headline"
    case error = "error"
}

public struct Message: XMPPStanzaProtocol {
    public let type: MessageType?
    public let to: String?
    public let from: String?
    public let body: String?
    public let subject: String?
    public let elementName: String = "message"
    public let namespace: String = "jabber:client"
    public let attributes: [String: String]
    public let children: [XMPPStanzaProtocol]
    
    public init(
        type: MessageType? = nil,
        to: String? = nil,
        from: String? = nil,
        body: String? = nil,
        subject: String? = nil,
        attributes: [String: String] = [:],
        children: [XMPPStanzaProtocol] = []
    ) {
        self.type = type
        self.to = to
        self.from = from
        self.body = body
        self.subject = subject
        self.attributes = attributes
        self.children = children
    }
    
    public func toXML() -> String {
        var xml = "<message"
        
        if let type = type {
            xml += " type='\(type.rawValue)'"
        }
        
        if let to = to {
            xml += " to='\(to)'"
        }
        
        if let from = from {
            xml += " from='\(from)'"
        }
        
        for (key, value) in attributes {
            xml += " \(key)='\(value)'"
        }
        
        xml += ">"
        
        if let subject = subject {
            xml += "<subject>\(subject)</subject>"
        }
        
        if let body = body {
            xml += "<body>\(body)</body>"
        }
        
        for child in children {
            xml += child.toXML()
        }
        
        xml += "</message>"
        return xml
    }
}

// MARK: - Stanza Parser

public class StanzaParser {
    
    public static func parsePresence(from xml: String) -> Presence? {
        // Parse presence stanza
        // This is a simplified parser - in production, use XMLParser
        
        var type: PresenceType?
        var show: PresenceShow?
        var status: String?
        var to: String?
        var from: String?
        var videoType: String?
        var region: String?
        var statsId: String?
        var isDominantSpeaker = false
        
        // Extract attributes from opening tag
        if let range = xml.range(of: "<presence([^>]*)>", options: .regularExpression) {
            let attrs = String(xml[range])
            // Parse attributes
        }
        
        // Extract type
        if let range = xml.range(of: "type='([^']*)'", options: .regularExpression) {
            let typeString = String(xml[range])
            type = PresenceType(rawValue: typeString)
        }
        
        // Extract show
        if xml.contains("<show>away</show>") {
            show = .away
        } else if xml.contains("<show>chat</show>") {
            show = .chat
        } else if xml.contains("<show>dnd</show>") {
            show = .dnd
        } else if xml.contains("<show>xa</show>") {
            show = .xa
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
        
        return Presence(
            type: type,
            show: show,
            status: status,
            to: to,
            from: from,
            videoType: videoType,
            region: region,
            statsId: statsId,
            isDominantSpeaker: isDominantSpeaker
        )
    }
    
    public static func parseIQ(from xml: String) -> IQ? {
        // Parse IQ stanza
        var type: IQType = .get
        var id = ""
        var to: String?
        var from: String?
        
        // Extract type
        if let range = xml.range(of: "type='([^']*)'", options: .regularExpression) {
            let typeString = String(xml[range])
            if let iqType = IQType(rawValue: typeString) {
                type = iqType
            }
        }
        
        // Extract id
        if let range = xml.range(of: "id='([^']*)'", options: .regularExpression) {
            id = String(xml[range])
        }
        
        // Extract to
        if let range = xml.range(of: "to='([^']*)'", options: .regularExpression) {
            to = String(xml[range])
        }
        
        // Extract from
        if let range = xml.range(of: "from='([^']*)'", options: .regularExpression) {
            from = String(xml[range])
        }
        
        return IQ(type: type, id: id, to: to, from: from)
    }
    
    public static func parseMessage(from xml: String) -> Message? {
        // Parse message stanza
        var type: MessageType?
        var to: String?
        var from: String?
        var body: String?
        var subject: String?
        
        // Extract type
        if let range = xml.range(of: "type='([^']*)'", options: .regularExpression) {
            let typeString = String(xml[range])
            type = MessageType(rawValue: typeString)
        }
        
        // Extract to
        if let range = xml.range(of: "to='([^']*)'", options: .regularExpression) {
            to = String(xml[range])
        }
        
        // Extract from
        if let range = xml.range(of: "from='([^']*)'", options: .regularExpression) {
            from = String(xml[range])
        }
        
        // Extract body
        if let range = xml.range(of: "<body>(.*?)</body>", options: .regularExpression) {
            body = String(xml[range])
        }
        
        // Extract subject
        if let range = xml.range(of: "<subject>(.*?)</subject>", options: .regularExpression) {
            subject = String(xml[range])
        }
        
        return Message(type: type, to: to, from: from, body: body, subject: subject)
    }
}
