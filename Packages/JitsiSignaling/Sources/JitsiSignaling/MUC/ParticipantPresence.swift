// MARK: - Participant presence (rich model for Jitsi-specific extensions)

/// The full presence record for one participant in a Jitsi conference room.
///
/// Synthesised from a ``PresenceStanza`` and enriched with Jitsi-specific
/// extensions (`stats-id`, `videotype`, `region`, capability features).
public struct ParticipantPresence: Sendable, Identifiable {
    // MARK: - XMPP identity

    /// Occupant JID inside the MUC, e.g. `room@conference.domain/nick`.
    public let occupantJID: String
    /// Bare real JID if disclosed by the server, e.g. `uuid@domain`.
    public let realJID: String?
    /// MUC affiliation: `"owner"`, `"admin"`, `"member"`, `"none"`.
    public let affiliation: String?
    /// MUC role: `"moderator"`, `"participant"`, `"visitor"`.
    public let role: String?

    // MARK: - Display info

    /// Displayed name (XEP-0172 nick element).
    public let nick: String?

    // MARK: - Jitsi-specific extensions

    /// Opaque statistics identifier for this participant/device (`stats-id` element).
    public let statsID: String?
    /// Video type: `"camera"` or `"desktop"` (`videotype` element).
    public let videoType: VideoType?
    /// Deployment region reported by the client (`region` element).
    public let region: String?
    /// WebRTC capability feature URIs advertised by this client.
    public let capabilities: [String]

    // MARK: - Identifiable

    /// Stable identity — the occupant JID.
    public var id: String { occupantJID }

    // MARK: - Derived flags

    public var isFocus: Bool { nick?.lowercased() == "focus" || role == "moderator" && affiliation == "owner" }
    public var isMe: Bool { false } // set by MUCSession once we know our own JID

    // MARK: - Init

    init(from stanza: PresenceStanza) {
        occupantJID = stanza.from ?? ""
        realJID = stanza.mucUser?.items.first?.jid
        affiliation = stanza.mucUser?.items.first?.affiliation
        role = stanza.mucUser?.items.first?.role
        nick = stanza.nick
        statsID = stanza.statsID
        videoType = stanza.videoType.flatMap { VideoType(rawValue: $0) }
        region = stanza.region
        capabilities = stanza.features
    }
}

// MARK: - VideoType

public enum VideoType: String, Sendable, CaseIterable {
    case camera  = "camera"
    case desktop = "desktop"
}
