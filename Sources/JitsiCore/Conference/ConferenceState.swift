import Foundation

/// The conference's high-level lifecycle, suitable for driving connection-state
/// UI. Distinct from ``ConnectionState`` (the raw socket) — this tracks join
/// progress (auth → join → joined).
public enum ConferenceState: Equatable, Sendable {
    case idle
    case connecting
    case authenticating
    case joining
    case joined
    case reconnecting
    case failed(String)
    case left
}

/// Everything the conference emits as it runs. Consumed as an `AsyncStream`.
public enum ConferenceEvent: Equatable, Sendable {
    case stateChanged(ConferenceState)
    case roster(RosterChange)
    case capabilities(BackendCapabilities)
    case iceServers([ICEServer])
    case conferenceReady(ConferenceResponse)
    case sessionDescription(ParsedSessionDescription)
}
