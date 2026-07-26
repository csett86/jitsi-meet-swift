import Foundation

/// Available downlink budget, coarsely tiered.
public enum BandwidthTier: Sendable, Equatable {
    case low
    case medium
    case high
}

/// Receiver-side constraints to signal to the bridge: how many remote videos to
/// receive (`lastN`), which sources are prioritized, and the max resolution for
/// on-stage vs. thumbnail tiles. Mirrors `lib-jitsi-meet`'s
/// `ReceiveVideoController` intent.
///
/// Everything here is keyed by **source name** (`<endpoint>-v0`), not endpoint
/// id. This deployment signals sources by name (docs/findings.md), and its JVB
/// ignores the legacy endpoint-keyed message — which means it forwards *no*
/// video at all until it gets a message in this shape. Observed live: with the
/// endpoint-keyed form the bridge kept answering `ForwardedSources: []`.
public struct ReceiverConstraints: Equatable, Sendable {
    /// Max simultaneously-received remote videos. `-1` means no limit.
    public var lastN: Int
    /// Prioritized (pinned / on-stage) source names.
    public var selectedSources: [String]
    /// Default max receive height (px) for a thumbnail tile.
    public var defaultMaxHeight: Int
    /// Max receive height (px) for a selected / on-stage tile.
    public var onStageMaxHeight: Int
    /// Explicit per-source overrides (selected sources get `onStageMaxHeight`).
    public var perSourceMaxHeight: [String: Int]

    public init(lastN: Int, selectedSources: [String], defaultMaxHeight: Int,
                onStageMaxHeight: Int, perSourceMaxHeight: [String: Int]) {
        self.lastN = lastN; self.selectedSources = selectedSources
        self.defaultMaxHeight = defaultMaxHeight; self.onStageMaxHeight = onStageMaxHeight
        self.perSourceMaxHeight = perSourceMaxHeight
    }
}

public extension ReceiverConstraints {
    /// The colibri `ReceiverVideoConstraints` message the bridge expects over the
    /// data channel. Pure JSON building, so it is testable; the `[MAC]` layer just
    /// sends the string. Keys mirror `lib-jitsi-meet`'s source-name signaling
    /// (`selectedSources` / `onStageSources`, `constraints` keyed by source name).
    func colibriMessageJSON() -> String {
        var payload: [String: Any] = [
            "colibriClass": "ReceiverVideoConstraints",
            "lastN": lastN,
            "selectedSources": selectedSources,
            "onStageSources": selectedSources,
            "defaultConstraints": ["maxHeight": defaultMaxHeight],
        ]
        if !perSourceMaxHeight.isEmpty {
            payload["constraints"] = perSourceMaxHeight.mapValues { ["maxHeight": $0] }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}

/// Computes receiver constraints as a deterministic function of what's visible,
/// what's selected, and the bandwidth tier. Pure — unit-tested offline; the
/// Apple layer turns the result into bridge signaling / simulcast requests.
public enum QualityController {

    /// `visibleSources` / `selectedSources` are Jitsi **source names**
    /// (``RemoteTrack/name``) — what the bridge constrains video by.
    public static func constraints(visibleSources: [String],
                                   selectedSources: [String] = [],
                                   bandwidth: BandwidthTier) -> ReceiverConstraints {
        let cap: Int, thumbHeight: Int, stageHeight: Int
        switch bandwidth {
        case .low:    cap = 4;  thumbHeight = 180; stageHeight = 360
        case .medium: cap = 9;  thumbHeight = 360; stageHeight = 540
        case .high:   cap = 20; thumbHeight = 360; stageHeight = 720
        }

        // Selected sources are always received; count them toward lastN and
        // ensure they fit even if more than `cap` tiles are visible.
        let selectedSet = Set(selectedSources)
        let visibleSet = Set(visibleSources)
        let receivable = visibleSet.union(selectedSet)
        let lastN = min(receivable.count, max(cap, selectedSet.count))

        var perSource: [String: Int] = [:]
        for source in selectedSources {
            perSource[source] = stageHeight
        }

        return ReceiverConstraints(
            lastN: lastN,
            selectedSources: selectedSources,
            defaultMaxHeight: thumbHeight,
            onStageMaxHeight: stageHeight,
            perSourceMaxHeight: perSource
        )
    }
}
