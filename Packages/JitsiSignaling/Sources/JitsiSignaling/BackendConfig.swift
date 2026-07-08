//
//  BackendConfig.swift
//  JitsiSignaling
//
//  Created for Jitsi Native macOS Client
//

import Foundation

/// Configuration for connecting to a Jitsi backend
public struct BackendConfig {
    public let displayName: String
    public let xmppWebSocketURL: URL
    public let mucDomain: String
    public let focusJID: String
    public let anonymousDomain: String?
    public let jwtToken: String?

    public init(
        displayName: String,
        xmppWebSocketURL: URL,
        mucDomain: String,
        focusJID: String,
        anonymousDomain: String? = nil,
        jwtToken: String? = nil
    ) {
        self.displayName = displayName
        self.xmppWebSocketURL = xmppWebSocketURL
        self.mucDomain = mucDomain
        self.focusJID = focusJID
        self.anonymousDomain = anonymousDomain
        self.jwtToken = jwtToken
    }
}

public extension BackendConfig {
    static let alpha = BackendConfig(
        displayName: "alpha.jitsi.net",
        xmppWebSocketURL: URL(string: "wss://alpha.jitsi.net/xmpp-websocket")!,
        mucDomain: "conference.alpha.jitsi.net",
        focusJID: "focus.alpha.jitsi.net",
        anonymousDomain: nil,
        jwtToken: nil
    )
}
