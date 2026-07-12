// MARK: - Conference connection state

public enum ConferenceConnectionState: Sendable {
    case disconnected
    case connecting
    case authenticating
    case discoveringFeatures
    case joiningRoom
    case joined(capabilities: BackendCapabilities)
    case error(any Error & Sendable)
}

// MARK: - Conference events

/// Events emitted by ``JitsiConference`` during a session.
public enum ConferenceEvent: Sendable {
    /// The connection state changed (connecting → authenticated → joined, etc.).
    case connectionStateChanged(ConferenceConnectionState)
    /// A new participant joined the room.
    case participantJoined(ParticipantPresence)
    /// An existing participant updated their presence (video type, region, etc.).
    case participantUpdated(ParticipantPresence)
    /// A participant left the room.
    case participantLeft(occupantJID: String)
    /// Focus (Jicofo) joined — a media session will follow.
    case focusJoined(ParticipantPresence)
    /// Focus sent a Jingle session-initiate — the caller should build a WebRTC
    /// answer and send `session-accept` to start media.
    case sessionDescriptionReceived(JingleSession)
    /// A non-fatal warning (unknown stanza type, unexpected server behaviour).
    case warning(String)
}

// MARK: - Conference state snapshot

/// Snapshot of the mutable portions of a running conference.
/// Updated atomically by ``JitsiConference`` on each state change.
public struct ConferenceState: Sendable {
    public let connectionState: ConferenceConnectionState
    public let capabilities: BackendCapabilities?
    public let participants: [String: ParticipantPresence]
    public let jingleSession: JingleSession?
    public let turnServices: [ExternalService]
    public let myFullJID: String?

    static let initial = ConferenceState(
        connectionState: .disconnected,
        capabilities: nil,
        participants: [:],
        jingleSession: nil,
        turnServices: [],
        myFullJID: nil
    )
}
