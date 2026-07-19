# JitsiMedia (Apple-only — [MAC])

WebRTC media integration. Depends on `JitsiCore` and the
[`stasel/WebRTC`](https://github.com/stasel/WebRTC) XCFramework.

**This target does not build on Linux and is intentionally excluded from Linux
CI.** It is only declared when `Package.swift` is evaluated on macOS (see the
`#if os(macOS)` block there). Import AVFoundation/VideoToolbox/WebRTC here — never
in `JitsiCore`.

Contents (Phase 2 — implemented, awaiting Mac verification):

- `PeerConnectionFactory.swift` — wraps `RTCPeerConnectionFactory`; maps
  `JitsiCore.ICEServer` → `RTCIceServer`.
- `SessionDescriptionMapper.swift` — thin adapter over the pure `JitsiCore` SDP
  helpers: `ParsedSessionDescription` → `RTCSessionDescription` offer, local
  answer → Jingle `session-accept`, and ICE candidate ↔ `RTCIceCandidate`.
- `LocalMediaSource.swift` — AVFoundation camera/mic → `RTCVideoTrack`/`RTCAudioTrack`.
- `MediaSession.swift` — ties a `ParsedSessionDescription` to a live
  `RTCPeerConnection` (set remote offer, add local media, create/send answer,
  trickle ICE), exposing outbound signaling via callbacks.
- `BridgeChannel.swift` (Phase 3) — the colibri `<web-socket>` from the
  `session-initiate`; sends `QualityController` receiver constraints and surfaces
  dominant-speaker events. Wired into `MediaSession`.

The heavy lifting (Jingle↔SDP, ICE line formatting) lives in
`JitsiCore/SDP/` — pure Swift, unit-tested on Linux. This target is only the
Apple-side adapter. `SessionDescriptionMapper`/`MediaSession` are the riskiest
pieces: only a real `RTCPeerConnection` confirms WebRTC accepts the SDP.

The app's Info.plist must declare `NSCameraUsageDescription` and
`NSMicrophoneUsageDescription` (Phase 4).
