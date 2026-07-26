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
  macOS Metal renderer), with the dominant-speaker highlight and the mirrored
  self-view. The flip is re-applied in `layout()`: AppKit owns a layer-backed
  view's transform and resets it, and its layer is anchored at the corner, so a
  plain `scaleX: -1` set once does nothing visible (and, once it sticks, mirrors
  the picture off the left edge unless translated by the width).
- `FrameCounter.swift` / `Log.swift` / `WindowSnapshot.swift` — evidence for the
  `[MAC]` checks: frames actually delivered to the renderer, a log file a live
  run can be judged from afterwards, and a PNG of our own window (Metal content
  never appears in AppKit's view-drawing APIs).

Flags used by the live checks (docs/mac-runbook.md): `--autojoin`,
`--leave-after <seconds>`, `--log <path>`, `--snapshot <path>`
/ `--snapshot-after <seconds>`, and a bare conference URL.
