//
//  ColibriContent.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation

// MARK: - Colibri Namespace

public enum ColibriNamespace: String {
    case colibri = "http://jitsi.org/protocol/colibri"
}

// MARK: - Colibri Conference Type

public enum ColibriConferenceType: String {
    case audio = "audio"
    case video = "video"
}

// MARK: - Colibri Channel

public struct ColibriChannel {
    public let id: String
    public let endpoint: String
    public let initFlag: Bool
    public let lastN: Int
    public let maxN: Int
    public let expire: Int
    public let ssrc: UInt32?
    
    public init(
        id: String,
        endpoint: String,
        initFlag: Bool = false,
        lastN: Int = 1,
        maxN: Int = 1,
        expire: Int = 60,
        ssrc: UInt32? = nil
    ) {
        self.id = id
        self.endpoint = endpoint
        self.initFlag = initFlag
        self.lastN = lastN
        self.maxN = maxN
        self.expire = expire
        self.ssrc = ssrc
    }
}

// MARK: - Colibri Conference

public struct ColibriConference {
    public let id: String
    public let type: ColibriConferenceType
    public let channels: [ColibriChannel]
    
    public init(
        id: String,
        type: ColibriConferenceType,
        channels: [ColibriChannel] = []
    ) {
        self.id = id
        self.type = type
        self.channels = channels
    }
}

// MARK: - Colibri Content

public struct ColibriContent {
    public let from: String
    public let conferences: [ColibriConference]
    
    public init(
        from: String,
        conferences: [ColibriConference] = []
    ) {
        self.from = from
        self.conferences = conferences
    }
}

// MARK: - Source Add/Remove

public struct SourceAdd {
    public let conference: String
    public let ssrc: UInt32
    public let endpoint: String
    
    public init(conference: String, ssrc: UInt32, endpoint: String) {
        self.conference = conference
        self.ssrc = ssrc
        self.endpoint = endpoint
    }
}

public struct SourceRemove {
    public let conference: String
    public let ssrc: UInt32
    public let endpoint: String
    
    public init(conference: String, ssrc: UInt32, endpoint: String) {
        self.conference = conference
        self.ssrc = ssrc
        self.endpoint = endpoint
    }
}

// MARK: - Colibri Parser

public class ColibriParser {
    
    public static func parseContent(from xml: String) -> ColibriContent? {
        var from: String?
        var conferences: [ColibriConference] = []
        
        // Extract from
        if let range = xml.range(of: "from='([^']*)'", options: .regularExpression) {
            from = String(xml[range])
        }
        
        guard let from = from else {
            return nil
        }
        
        // Parse conferences
        let conferencePattern = "<conference[^>]*>.*?</conference>"
        let regex = try? NSRegularExpression(pattern: conferencePattern, options: [.dotMatchesLineSeparators])
        if let regex = regex {
            let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                let range = Range(match.range, in: xml)
                let conferenceXML = String(xml[range])
                if let conference = parseConference(from: conferenceXML) {
                    conferences.append(conference)
                }
            }
        }
        
        return ColibriContent(from: from, conferences: conferences)
    }
    
    private static func parseConference(from xml: String) -> ColibriConference? {
        var id: String?
        var type: ColibriConferenceType?
        var channels: [ColibriChannel] = []
        
        // Extract id
        if let range = xml.range(of: "id='([^']*)'", options: .regularExpression) {
            id = String(xml[range])
        }
        
        // Extract type
        if let range = xml.range(of: "type='([^']*)'", options: .regularExpression) {
            let typeString = String(xml[range])
            type = ColibriConferenceType(rawValue: typeString)
        }
        
        guard let id = id, let type = type else {
            return nil
        }
        
        // Parse channels
        let channelPattern = "<channel[^>]*>"
        let regex = try? NSRegularExpression(pattern: channelPattern, options: [])
        if let regex = regex {
            let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                let range = Range(match.range, in: xml)
                let channelXML = String(xml[range])
                if let channel = parseChannel(from: channelXML) {
                    channels.append(channel)
                }
            }
        }
        
        return ColibriConference(id: id, type: type, channels: channels)
    }
    
    private static func parseChannel(from xml: String) -> ColibriChannel? {
        var id: String?
        var endpoint: String?
        var initFlag = false
        var lastN = 1
        var maxN = 1
        var expire = 60
        var ssrc: UInt32?
        
        // Extract id
        if let range = xml.range(of: "id='([^']*)'", options: .regularExpression) {
            id = String(xml[range])
        }
        
        // Extract endpoint
        if let range = xml.range(of: "endpoint='([^']*)'", options: .regularExpression) {
            endpoint = String(xml[range])
        }
        
        // Extract init
        if let range = xml.range(of: "init='([^']*)'", options: .regularExpression) {
            let initString = String(xml[range])
            initFlag = initString == "true"
        }
        
        // Extract last-n
        if let range = xml.range(of: "last-n='([^']*)'", options: .regularExpression) {
            let lastNString = String(xml[range])
            lastN = Int(lastNString) ?? 1
        }
        
        // Extract max-n
        if let range = xml.range(of: "max-n='([^']*)'", options: .regularExpression) {
            let maxNString = String(xml[range])
            maxN = Int(maxNString) ?? 1
        }
        
        // Extract expire
        if let range = xml.range(of: "expire='([^']*)'", options: .regularExpression) {
            let expireString = String(xml[range])
            expire = Int(expireString) ?? 60
        }
        
        // Extract ssrc
        if let range = xml.range(of: "ssrc='([^']*)'", options: .regularExpression) {
            let ssrcString = String(xml[range])
            ssrc = UInt32(ssrcString)
        }
        
        guard let id = id, let endpoint = endpoint else {
            return nil
        }
        
        return ColibriChannel(
            id: id,
            endpoint: endpoint,
            initFlag: initFlag,
            lastN: lastN,
            maxN: maxN,
            expire: expire,
            ssrc: ssrc
        )
    }
    
    public static func parseSourceAdd(from xml: String) -> SourceAdd? {
        var conference: String?
        var ssrc: UInt32?
        var endpoint: String?
        
        // Extract conference
        if let range = xml.range(of: "conference='([^']*)'", options: .regularExpression) {
            conference = String(xml[range])
        }
        
        // Extract ssrc
        if let range = xml.range(of: "ssrc='([^']*)'", options: .regularExpression) {
            let ssrcString = String(xml[range])
            ssrc = UInt32(ssrcString)
        }
        
        // Extract endpoint
        if let range = xml.range(of: "endpoint='([^']*)'", options: .regularExpression) {
            endpoint = String(xml[range])
        }
        
        guard let conference = conference, let ssrc = ssrc, let endpoint = endpoint else {
            return nil
        }
        
        return SourceAdd(conference: conference, ssrc: ssrc, endpoint: endpoint)
    }
    
    public static func parseSourceRemove(from xml: String) -> SourceRemove? {
        var conference: String?
        var ssrc: UInt32?
        var endpoint: String?
        
        // Extract conference
        if let range = xml.range(of: "conference='([^']*)'", options: .regularExpression) {
            conference = String(xml[range])
        }
        
        // Extract ssrc
        if let range = xml.range(of: "ssrc='([^']*)'", options: .regularExpression) {
            let ssrcString = String(xml[range])
            ssrc = UInt32(ssrcString)
        }
        
        // Extract endpoint
        if let range = xml.range(of: "endpoint='([^']*)'", options: .regularExpression) {
            endpoint = String(xml[range])
        }
        
        guard let conference = conference, let ssrc = ssrc, let endpoint = endpoint else {
            return nil
        }
        
        return SourceRemove(conference: conference, ssrc: ssrc, endpoint: endpoint)
    }
}
