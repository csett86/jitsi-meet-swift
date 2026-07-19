import Foundation

/// Tracks the current dominant speaker and a short history. Pure reducer, so the
/// selection logic is unit-tested offline; wiring the source of the events is
/// done elsewhere (see the transport note below).
public struct DominantSpeakerTracker: Equatable, Sendable {
    public private(set) var current: String?
    /// Most-recent-first history of previous dominant speakers, capped.
    public private(set) var history: [String] = []
    private let historyLimit: Int

    public init(historyLimit: Int = 8) {
        self.historyLimit = historyLimit
    }

    /// Update to a new dominant speaker. Returns `true` if it changed.
    @discardableResult
    public mutating func update(to endpoint: String) -> Bool {
        guard endpoint != current else { return false }
        if let previous = current {
            history.insert(previous, at: 0)
            if history.count > historyLimit { history.removeLast() }
        }
        current = endpoint
        return true
    }
}

/// Parses Jitsi endpoint messages. On modern deployments dominant-speaker events
/// travel over the WebRTC bridge **data channel** as JSON (colibri class), not
/// XMPP — so capturing them is `[MAC]` (no WebRTC on Linux). This parser is pure
/// and testable; the Apple layer feeds it the data-channel payloads.
public enum EndpointMessage {

    /// Extract the dominant-speaker endpoint id from a colibri
    /// `DominantSpeakerEndpointChangeEvent` JSON message, if that's what it is.
    public static func dominantSpeaker(fromJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard object["colibriClass"] as? String == "DominantSpeakerEndpointChangeEvent" else {
            return nil
        }
        // Newer deployments use "dominantSpeakerEndpoint"; some use "endpoint".
        return (object["dominantSpeakerEndpoint"] as? String)
            ?? (object["endpoint"] as? String)
    }
}
