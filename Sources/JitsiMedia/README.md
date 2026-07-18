# JitsiMedia (Apple-only — [MAC])

WebRTC media integration. Depends on `JitsiCore` and the
[`stasel/WebRTC`](https://github.com/stasel/WebRTC) XCFramework.

**This target does not build on Linux and is intentionally excluded from Linux
CI.** It is only declared when `Package.swift` is evaluated on macOS (see the
`#if os(macOS)` block there). Import AVFoundation/VideoToolbox/WebRTC here — never
in `JitsiCore`.

Planned contents (Phase 2+):

- `PeerConnectionFactory.swift` — wraps `RTCPeerConnectionFactory`
- `SessionDescriptionMapper.swift` — `ParsedSessionDescription` → `RTCSessionDescription` + ICE
- `LocalMediaSource.swift` — AVFoundation camera/mic → WebRTC sources
- `MediaSession.swift` — ties `JitsiConference` events to an `RTCPeerConnection`

Pure mapping logic (SDP string munging, ICE candidate formatting) that needs no
WebRTC types belongs in `JitsiCore` so it can be unit-tested offline.
