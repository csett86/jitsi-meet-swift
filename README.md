# JitsiNativeMac

A fully native macOS Jitsi Meet client built in Swift — proof of concept.

**Status:** Phase 0 scaffolding complete. No media or signaling yet.

## Architecture

```
JitsiNativeMac.xcodeproj   ← macOS SwiftUI app (deployment target: macOS 13+)
JitsiNativeMac/            ← App source (SwiftUI views, BackendConfig)
Packages/
  JitsiSignaling/          ← XMPP transport, stanza parsing, MUC, Jingle, disco
  JitsiMedia/              ← WebRTC wrapper (stasel/WebRTC), Jingle↔RTC mapping
docs/
  test-environment.md      ← Target endpoint details (alpha.jitsi.net)
  findings.md              ← Protocol discoveries / assumption violations
```

## Requirements

| Tool | Version |
|------|---------|
| Xcode | 16.0+ |
| macOS SDK | 13.0+ |
| Swift | 6.0+ |

## Getting Started

1. Open `JitsiNativeMac.xcodeproj` in Xcode 16+.
2. Xcode will automatically resolve the local SPM packages under `Packages/`
   and fetch `stasel/WebRTC@150.0.0` from GitHub.
3. Set your development team in the target's Signing & Capabilities tab.
4. Build & Run (⌘R).

## Test Endpoint

`https://alpha.jitsi.net` — anonymous, no JWT, no lobby.  
See [`docs/test-environment.md`](docs/test-environment.md) for details.

## Key Types

### `BackendConfig`

The single source of connection details. **Never** construct one by hand —
always use the URL-based initialiser:

```swift
let config = try BackendConfig(conferenceURL: "https://alpha.jitsi.net/MyRoom")
// config.xmppWebSocketURL → wss://alpha.jitsi.net/xmpp-websocket
// config.conferenceJID    → myroom@conference.alpha.jitsi.net
```
