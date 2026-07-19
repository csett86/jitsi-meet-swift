import Foundation

/// A conference participant, as seen through MUC presence.
public struct Participant: Equatable, Sendable {
    /// The MUC nickname (the resource of the occupant JID `room/<nick>`).
    public var nick: String
    /// Stable per-occupant id (`urn:xmpp:occupant-id:0`), when advertised.
    public var occupantID: String?
    /// The real JID from `muc#user`, when the room is not anonymous.
    public var realJID: String?
    public var role: String?
    public var affiliation: String?
    public var audioMuted: Bool?
    public var videoMuted: Bool?
    /// True for the local user (MUC self-presence, status code 110).
    public var isSelf: Bool

    public init(nick: String, occupantID: String? = nil, realJID: String? = nil,
                role: String? = nil, affiliation: String? = nil,
                audioMuted: Bool? = nil, videoMuted: Bool? = nil, isSelf: Bool = false) {
        self.nick = nick; self.occupantID = occupantID; self.realJID = realJID
        self.role = role; self.affiliation = affiliation
        self.audioMuted = audioMuted; self.videoMuted = videoMuted; self.isSelf = isSelf
    }
}

/// A change to the roster, emitted as presence is processed.
public enum RosterChange: Equatable, Sendable {
    case joined(Participant)
    case updated(Participant)
    case left(Participant)
}
