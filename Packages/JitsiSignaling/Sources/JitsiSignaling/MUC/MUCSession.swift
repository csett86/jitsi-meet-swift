import Foundation

// MARK: - MUC session errors

public enum MUCError: Error, Sendable {
    case notConnected
    case joinFailed
    case alreadyJoined
}

// MARK: - MUCSession

/// Manages a single Multi-User Chat (XEP-0045) room on behalf of the client.
///
/// Responsibilities:
/// - Send the initial MUC join presence.
/// - Track the participant roster via incoming `<presence>` stanzas.
/// - Detect self-presence (status code 110) to confirm join.
/// - Detect focus presence (Jicofo).
///
/// Callers receive roster updates via the ``events`` async stream.
public actor MUCSession {
    // MARK: - Events

    public enum Event: Sendable {
        case joined(selfOccupantJID: String)
        case participantJoined(ParticipantPresence)
        case participantUpdated(ParticipantPresence)
        case participantLeft(occupantJID: String)
        case focusJoined(ParticipantPresence)
    }

    // MARK: - State

    /// Stable map from occupant JID → participant.
    public private(set) var participants: [String: ParticipantPresence] = [:]
    public private(set) var selfOccupantJID: String?
    public private(set) var isJoined = false

    private let conferenceJID: String
    private let nick: String
    private let myFullJID: String

    private var eventContinuation: AsyncStream<Event>.Continuation?
    public let events: AsyncStream<Event>

    // MARK: - Init

    /// - Parameters:
    ///   - conferenceJID: Full conference room JID, e.g. `room@conference.domain`.
    ///   - nick: Local nickname (resource part in the MUC).
    ///   - myFullJID: Our own full XMPP JID after resource bind.
    public init(conferenceJID: String, nick: String, myFullJID: String) {
        self.conferenceJID = conferenceJID
        self.nick = nick
        self.myFullJID = myFullJID

        let (stream, continuation) = AsyncStream<Event>.makeStream()
        events = stream
        eventContinuation = continuation
    }

    // MARK: - Join

    /// Sends the MUC join presence via the given connection.
    ///
    /// Jitsi-specific extensions are included: `nick`, `stats-id`, `videotype`,
    /// and the client feature set.
    public func join(
        via connection: XMPPWebSocketConnection,
        statsID: String = "SwiftClient",
        videoType: VideoType = .camera,
        capabilities: [String] = [
            "urn:ietf:rfc:5888",   // BUNDLE
            "urn:ietf:rfc:5761",   // RTCP-MUX
            "urn:ietf:rfc:4588",   // RTX
        ]
    ) async throws {
        guard !isJoined else { throw MUCError.alreadyJoined }

        let occupantJID = "\(conferenceJID)/\(nick)"
        let featureElements = capabilities.map { "<feature var=\"\($0)\"/>" }.joined()

        let payload = """
            <x xmlns="\(XMPPNS.muc)"/>
            <nick xmlns="\(XMPPNS.nick)">\(nick)</nick>
            <stats-id xmlns="\(XMPPNS.jitsiMeet)">\(statsID)</stats-id>
            <videotype xmlns="\(XMPPNS.jitsiVideo)">\(videoType.rawValue)</videotype>
            <features xmlns="\(XMPPNS.jitsiMeet)">\(featureElements)</features>
            """
        try await connection.sendPresence(to: occupantJID, payload: payload)
    }

    // MARK: - Stanza handling

    /// Process an incoming presence stanza from the server.
    /// Call this for every ``ReceivedStanza/presence(_:)`` received after joining.
    public func handle(presence stanza: PresenceStanza) {
        let occupantJID = stanza.from ?? ""
        guard occupantJID.hasPrefix(conferenceJID + "/") else { return }

        if stanza.type == .unavailable {
            participants.removeValue(forKey: occupantJID)
            eventContinuation?.yield(.participantLeft(occupantJID: occupantJID))
            return
        }

        let participant = ParticipantPresence(from: stanza)
        let isSelf = stanza.mucUser?.isSelfPresence == true
        let existed = participants[occupantJID] != nil

        participants[occupantJID] = participant

        if isSelf && !isJoined {
            isJoined = true
            selfOccupantJID = occupantJID
            eventContinuation?.yield(.joined(selfOccupantJID: occupantJID))
        } else if participant.isFocus {
            eventContinuation?.yield(.focusJoined(participant))
        } else if existed {
            eventContinuation?.yield(.participantUpdated(participant))
        } else {
            eventContinuation?.yield(.participantJoined(participant))
        }
    }

    // MARK: - Leave

    /// Sends an unavailable presence to leave the room.
    public func leave(via connection: XMPPWebSocketConnection) async throws {
        let occupantJID = "\(conferenceJID)/\(nick)"
        let xml = "<presence xmlns=\"jabber:client\" to=\"\(occupantJID)\" type=\"unavailable\"/>"
        try await connection.sendRaw(xml)
        isJoined = false
        eventContinuation?.finish()
        eventContinuation = nil
    }
}
