import Foundation

/// What a deployment supports, derived from its `disco#info`. Populated from what
/// the server actually advertised — which can differ from a default upstream
/// deployment. On `jitsi.luki.org` these come from component identities (lobby,
/// breakout, polls, av-moderation); `visitors` is signaled separately via the
/// Jicofo conference response, so it is left off the disco-derived value here
/// and set from `ConferenceResponse.visitorsSupported` on the conference.
public struct BackendCapabilities: Equatable, Sendable {
    public var supportsLobby: Bool
    public var supportsBreakoutRooms: Bool
    public var supportsPolls: Bool
    public var supportsAVModeration: Bool
    public var supportsSpeakerStats: Bool
    public var supportsE2EE: Bool
    public var supportsVisitors: Bool

    public init(supportsLobby: Bool = false, supportsBreakoutRooms: Bool = false,
                supportsPolls: Bool = false, supportsAVModeration: Bool = false,
                supportsSpeakerStats: Bool = false, supportsE2EE: Bool = false,
                supportsVisitors: Bool = false) {
        self.supportsLobby = supportsLobby
        self.supportsBreakoutRooms = supportsBreakoutRooms
        self.supportsPolls = supportsPolls
        self.supportsAVModeration = supportsAVModeration
        self.supportsSpeakerStats = supportsSpeakerStats
        self.supportsE2EE = supportsE2EE
        self.supportsVisitors = supportsVisitors
    }

    /// Derive capabilities from a domain `disco#info` response.
    public init(disco: DiscoInfo) {
        func hasComponent(_ type: String) -> Bool {
            disco.identities.contains { $0.type == type }
        }
        self.init(
            supportsLobby: hasComponent("lobbyrooms"),
            supportsBreakoutRooms: hasComponent("breakout_rooms"),
            supportsPolls: hasComponent("polls"),
            supportsAVModeration: hasComponent("av_moderation"),
            supportsSpeakerStats: hasComponent("speakerstats"),
            // No dedicated e2ee identity/feature is advertised; endpoints negotiate
            // E2EE out of band. Leave false unless a future capture proves otherwise.
            supportsE2EE: disco.hasFeature("https://jitsi.org/meet/e2ee"),
            supportsVisitors: false
        )
    }
}
