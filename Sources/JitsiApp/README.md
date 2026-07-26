# JitsiApp (Apple-only — [MAC])

The native macOS SwiftUI/AppKit application shell. Built in Xcode, not in Linux
CI. Depends on `JitsiCore` (state, parsing, signaling) and `JitsiMedia` (WebRTC).

It is a plain SwiftPM `executableTarget` (declared only on macOS), so the whole
client builds with `swift build`. What an Xcode project would otherwise
provide — Info.plist with the camera/microphone usage descriptions, the embedded
WebRTC framework, a signature — is assembled by `Tools/mac-app/make-app.sh`.
**Run it from the bundle**: an unbundled binary has no Info.plist, and macOS then
refuses capture.

```sh
./Tools/mac-app/make-app.sh && open build/JitsiMeetSwift.app
```

Contents:

- `ContentView.swift` — the join screen (one field, `ConferenceURLParser.parse`,
  inline error) and the call screen (adaptive tile grid, mic / camera / leave,
  connection state + live RTP counters).
- `CallModel.swift` — the only place the app touches `JitsiCore`/`JitsiMedia`.
  Owns one `JitsiConference` + `ConferenceCall`, turns their callbacks into
  `@Published` state on the main actor, and feeds `QualityController`'s receiver
  constraints back to the bridge as tiles and the dominant speaker change.
- `VideoTileView.swift` — `NSViewRepresentable` over `RTCMTLNSVideoView` (the
  macOS Metal renderer), with the dominant-speaker highlight.
- `FrameCounter.swift` / `Log.swift` — evidence for the `[MAC]` checks: frames
  actually delivered to the renderer, and a log file a live run can be judged
  from afterwards.

Flags used by the live checks (docs/mac-runbook.md): `--autojoin`,
`--leave-after <seconds>`, `--log <path>`, and a bare conference URL.
