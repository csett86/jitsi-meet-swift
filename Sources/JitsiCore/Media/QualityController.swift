import Foundation

/// Available downlink budget, coarsely tiered.
public enum BandwidthTier: Sendable, Equatable {
    case low
    case medium
    case high
}

/// Receiver-side constraints to signal to the bridge: how many remote videos to
/// receive (`lastN`), which endpoints are prioritized, and the max resolution
/// for on-stage vs. thumbnail tiles. Mirrors `lib-jitsi-meet`'s
/// `ReceiveVideoController` intent.
public struct ReceiverConstraints: Equatable, Sendable {
    /// Max simultaneously-received remote videos. `-1` means no limit.
    public var lastN: Int
    /// Prioritized (pinned / on-stage) endpoints.
    public var selectedEndpoints: [String]
    /// Default max receive height (px) for a thumbnail tile.
    public var defaultMaxHeight: Int
    /// Max receive height (px) for a selected / on-stage tile.
    public var onStageMaxHeight: Int
    /// Explicit per-endpoint overrides (selected endpoints get `onStageMaxHeight`).
    public var perEndpointMaxHeight: [String: Int]

    public init(lastN: Int, selectedEndpoints: [String], defaultMaxHeight: Int,
                onStageMaxHeight: Int, perEndpointMaxHeight: [String: Int]) {
        self.lastN = lastN; self.selectedEndpoints = selectedEndpoints
        self.defaultMaxHeight = defaultMaxHeight; self.onStageMaxHeight = onStageMaxHeight
        self.perEndpointMaxHeight = perEndpointMaxHeight
    }
}

public extension ReceiverConstraints {
    /// The colibri `ReceiverVideoConstraints` message the bridge expects over the
    /// data channel. Pure JSON building, so it is testable; the `[MAC]` layer just
    /// sends the string. Keys mirror `lib-jitsi-meet`.
    func colibriMessageJSON() -> String {
        var payload: [String: Any] = [
            "colibriClass": "ReceiverVideoConstraints",
            "lastN": lastN,
            "selectedEndpoints": selectedEndpoints,
            "defaultConstraints": ["maxHeight": defaultMaxHeight],
        ]
        if !perEndpointMaxHeight.isEmpty {
            payload["constraints"] = perEndpointMaxHeight.mapValues { ["maxHeight": $0] }
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

    public static func constraints(visibleEndpoints: [String],
                                   selectedEndpoints: [String] = [],
                                   bandwidth: BandwidthTier) -> ReceiverConstraints {
        let cap: Int, thumbHeight: Int, stageHeight: Int
        switch bandwidth {
        case .low:    cap = 4;  thumbHeight = 180; stageHeight = 360
        case .medium: cap = 9;  thumbHeight = 360; stageHeight = 540
        case .high:   cap = 20; thumbHeight = 360; stageHeight = 720
        }

        // Selected endpoints are always received; count them toward lastN and
        // ensure they fit even if more than `cap` tiles are visible.
        let selectedSet = Set(selectedEndpoints)
        let visibleSet = Set(visibleEndpoints)
        let receivable = visibleSet.union(selectedSet)
        let lastN = min(receivable.count, max(cap, selectedSet.count))

        var perEndpoint: [String: Int] = [:]
        for endpoint in selectedEndpoints {
            perEndpoint[endpoint] = stageHeight
        }

        return ReceiverConstraints(
            lastN: lastN,
            selectedEndpoints: selectedEndpoints,
            defaultMaxHeight: thumbHeight,
            onStageMaxHeight: stageHeight,
            perEndpointMaxHeight: perEndpoint
        )
    }
}
