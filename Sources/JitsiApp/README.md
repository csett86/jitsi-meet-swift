# JitsiApp (Apple-only — [MAC])

The native macOS SwiftUI/AppKit application shell. Built in Xcode, not in Linux
CI. Depends on `JitsiCore` (state, parsing, signaling) and `JitsiMedia` (WebRTC).

Because a signed, bundled macOS app is Xcode territory (Info.plist, entitlements,
`RTCMTLVideoView`), this target is not declared in the SwiftPM manifest that runs
in the cloud sandbox. The build/run steps live in `docs/mac-runbook.md`.

Planned contents (Phase 4):

- Single-field join screen calling `ConferenceURLParser.parse(_:)`
- Adaptive tile grid with dominant-speaker highlight
- `RTCVideoTileView` (`NSViewRepresentable` wrapping `RTCMTLVideoView`)
- Toolbar: mic mute, camera on/off, leave
- Connection-state UI driven by `JitsiCore`'s `AsyncStream`s
