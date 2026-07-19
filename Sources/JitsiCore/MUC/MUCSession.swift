import Foundation

/// Maintains the MUC roster from presence stanzas. Pure value logic (no
/// transport, no I/O), so the join → roster flow is fully unit-testable offline.
///
/// The Jicofo focus occupant (`room/focus`) is not a human participant and is
/// excluded from the roster.
public struct MUCSession: Equatable, Sendable {
    /// Current participants, keyed by MUC nick.
    public private(set) var participants: [String: Participant] = [:]

    public init() {}

    /// The local user, if their self-presence has been seen.
    public var localParticipant: Participant? {
        participants.values.first { $0.isSelf }
    }

    /// Participants in a stable order (self first, then by nick).
    public var ordered: [Participant] {
        participants.values.sorted {
            if $0.isSelf != $1.isSelf { return $0.isSelf }
            return $0.nick < $1.nick
        }
    }

    /// Apply a presence stanza, returning the roster change it caused (if any).
    @discardableResult
    public mutating func apply(_ presence: Presence) -> RosterChange? {
        guard let from = presence.from, let nick = JID(from)?.resource else { return nil }
        // Jicofo's focus occupant is infrastructure, not a participant.
        guard !isFocus(nick: nick, item: presence.mucItem) else { return nil }

        if presence.type == "unavailable" {
            guard let gone = participants.removeValue(forKey: nick) else { return nil }
            return .left(gone)
        }

        let participant = Participant(
            nick: nick,
            occupantID: presence.occupantID,
            realJID: presence.mucItem?.jid,
            role: presence.mucItem?.role,
            affiliation: presence.mucItem?.affiliation,
            audioMuted: presence.audioMuted,
            videoMuted: presence.videoMuted,
            isSelf: presence.isSelfPresence
        )
        let existed = participants[nick] != nil
        participants[nick] = participant
        return existed ? .updated(participant) : .joined(participant)
    }

    private func isFocus(nick: String, item: MUCItem?) -> Bool {
        if nick == "focus" { return true }
        // Also catch the focus by its real JID (focus@auth.<domain>).
        if let jid = item?.jid, let local = JID(jid)?.local, local == "focus",
           JID(jid)?.domain.hasPrefix("auth.") == true {
            return true
        }
        return false
    }
}
