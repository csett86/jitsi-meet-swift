import Foundation

/// A resolved ICE server, ready to hand to the WebRTC layer.
public struct ICEServer: Equatable, Sendable {
    /// One or more ICE URLs (`stun:`/`turn:`/`turns:`), e.g.
    /// `turn:turn.jitsi.luki.org:3478?transport=udp`.
    public var urls: [String]
    public var username: String?
    public var credential: String?
    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls; self.username = username; self.credential = credential
    }
}

/// Turns XEP-0215 external-service records into ICE servers. Pure logic, so it is
/// unit-tested offline and reused unchanged by the Apple media layer.
public enum TURNDiscovery {
    public static func iceServers(from services: [ExternalService]) -> [ICEServer] {
        services.compactMap { service in
            guard let url = url(for: service) else { return nil }
            switch service.type.lowercased() {
            case "stun", "stuns":
                // STUN has no credentials.
                return ICEServer(urls: [url])
            case "turn", "turns":
                return ICEServer(urls: [url], username: service.username, credential: service.password)
            default:
                return nil
            }
        }
    }

    private static func url(for service: ExternalService) -> String? {
        let scheme = service.type.lowercased()
        guard ["stun", "stuns", "turn", "turns"].contains(scheme) else { return nil }
        var url = "\(scheme):\(service.host)"
        if let port = service.port { url += ":\(port)" }
        // Transport only applies to TURN URLs.
        if scheme.hasPrefix("turn"), let transport = service.transport {
            url += "?transport=\(transport)"
        }
        return url
    }
}
