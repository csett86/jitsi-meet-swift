//
//  DiscoInfo.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation

// MARK: - Service Discovery (XEP-0030)

public struct DiscoInfo {
    public let from: String
    public let node: String?
    public let identities: [DiscoIdentity]
    public let features: [String]
    public let extensions: [DiscoExtension]
    
    public init(
        from: String,
        node: String? = nil,
        identities: [DiscoIdentity] = [],
        features: [String] = [],
        extensions: [DiscoExtension] = []
    ) {
        self.from = from
        self.node = node
        self.identities = identities
        self.features = features
        self.extensions = extensions
    }
    
    /// Check if a specific feature is supported
    public func supports(feature: String) -> Bool {
        return features.contains(feature)
    }
}

public struct DiscoIdentity {
    public let category: String
    public let type: String
    public let name: String?
    public let lang: String?
    
    public init(category: String, type: String, name: String? = nil, lang: String? = nil) {
        self.category = category
        self.type = type
        self.name = name
        self.lang = lang
    }
}

public struct DiscoExtension {
    public let namespace: String
    public let data: String?
    
    public init(namespace: String, data: String? = nil) {
        self.namespace = namespace
        self.data = data
    }
}

// MARK: - Backend Capabilities

public struct BackendCapabilities {
    public let supportsLobby: Bool
    public let supportsE2EE: Bool
    public let supportsVisitors: Bool
    public let supportsRecording: Bool
    public let supportsLiveStreaming: Bool
    public let supportsSIP: Bool
    public let supportsPSTN: Bool
    public let supportsColibri2: Bool
    public let supportsJingle: Bool
    
    public init(
        supportsLobby: Bool = false,
        supportsE2EE: Bool = false,
        supportsVisitors: Bool = false,
        supportsRecording: Bool = false,
        supportsLiveStreaming: Bool = false,
        supportsSIP: Bool = false,
        supportsPSTN: Bool = false,
        supportsColibri2: Bool = false,
        supportsJingle: Bool = false
    ) {
        self.supportsLobby = supportsLobby
        self.supportsE2EE = supportsE2EE
        self.supportsVisitors = supportsVisitors
        self.supportsRecording = supportsRecording
        self.supportsLiveStreaming = supportsLiveStreaming
        self.supportsSIP = supportsSIP
        self.supportsPSTN = supportsPSTN
        self.supportsColibri2 = supportsColibri2
        self.supportsJingle = supportsJingle
    }
    
    public static func from(discoInfo: DiscoInfo) -> BackendCapabilities {
        var capabilities = BackendCapabilities()
        
        // Check for Jitsi-specific features
        for feature in discoInfo.features {
            switch feature {
            case "http://jitsi.org/protocol/lobby":
                capabilities.supportsLobby = true
            case "http://jitsi.org/protocol/e2ee":
                capabilities.supportsE2EE = true
            case "http://jitsi.org/protocol/visitors":
                capabilities.supportsVisitors = true
            case "http://jitsi.org/protocol/recording":
                capabilities.supportsRecording = true
            case "http://jitsi.org/protocol/livestreaming":
                capabilities.supportsLiveStreaming = true
            case "http://jitsi.org/protocol/sip":
                capabilities.supportsSIP = true
            case "http://jitsi.org/protocol/pstn":
                capabilities.supportsPSTN = true
            case "http://jitsi.org/protocol/colibri":
                capabilities.supportsColibri2 = true
            case "urn:xmpp:jingle:1":
                capabilities.supportsJingle = true
            default:
                break
            }
        }
        
        return capabilities
    }
}

// MARK: - DiscoInfo Parser

public class DiscoInfoParser {
    
    public static func parse(from xml: String) -> DiscoInfo? {
        var from: String?
        var node: String?
        var identities: [DiscoIdentity] = []
        var features: [String] = []
        var extensions: [DiscoExtension] = []
        
        // Extract from
        if let range = xml.range(of: "from='([^']*)'", options: .regularExpression) {
            from = String(xml[range])
        }
        
        // Extract node
        if let range = xml.range(of: "node='([^']*)'", options: .regularExpression) {
            node = String(xml[range])
        }
        
        guard let from = from else {
            return nil
        }
        
        // Parse identities
        let identityPattern = "<identity[^>]*>"
        let identityRegex = try? NSRegularExpression(pattern: identityPattern, options: [])
        if let identityRegex = identityRegex {
            let matches = identityRegex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                let range = Range(match.range, in: xml)
                let identityXML = String(xml[range])
                if let identity = parseIdentity(from: identityXML) {
                    identities.append(identity)
                }
            }
        }
        
        // Parse features
        let featurePattern = "<feature[^>]*>"
        let featureRegex = try? NSRegularExpression(pattern: featurePattern, options: [])
        if let featureRegex = featureRegex {
            let matches = featureRegex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                let range = Range(match.range, in: xml)
                let featureXML = String(xml[range])
                if let feature = parseFeature(from: featureXML) {
                    features.append(feature)
                }
            }
        }
        
        return DiscoInfo(
            from: from,
            node: node,
            identities: identities,
            features: features,
            extensions: extensions
        )
    }
    
    private static func parseIdentity(from xml: String) -> DiscoIdentity? {
        var category: String?
        var type: String?
        var name: String?
        var lang: String?
        
        // Extract category
        if let range = xml.range(of: "category='([^']*)'", options: .regularExpression) {
            category = String(xml[range])
        }
        
        // Extract type
        if let range = xml.range(of: "type='([^']*)'", options: .regularExpression) {
            type = String(xml[range])
        }
        
        // Extract name
        if let range = xml.range(of: "name='([^']*)'", options: .regularExpression) {
            name = String(xml[range])
        }
        
        // Extract lang
        if let range = xml.range(of: "xml:lang='([^']*)'", options: .regularExpression) {
            lang = String(xml[range])
        }
        
        guard let category = category, let type = type else {
            return nil
        }
        
        return DiscoIdentity(category: category, type: type, name: name, lang: lang)
    }
    
    private static func parseFeature(from xml: String) -> String? {
        // Extract var attribute
        if let range = xml.range(of: "var='([^']*)'", options: .regularExpression) {
            return String(xml[range])
        }
        
        return nil
    }
}
