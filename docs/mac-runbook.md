# macOS runbook — build & verify the Apple-only pieces

The cloud/Linux agent writes `[MAC]` code but **cannot verify it**. This runbook
is the human's checklist. Record outcomes in `docs/mac-signoff.md` — mark items
"verified" only after they pass on real Apple hardware.

## Toolchain

- macOS 13+ and Xcode (with command-line tools).
- The Apple-only targets (`JitsiMedia`, `JitsiApp`) and the `stasel/WebRTC`
  dependency are only declared when `Package.swift` is evaluated on macOS. On
  Linux they do not exist, which is why Linux CI stays clean.

## Build

```sh
# Pure core (also what Linux CI gates on):
swift build --target JitsiCore
swift test  --filter JitsiCoreTests

# Apple-only media library (macOS only — pulls stasel/WebRTC):
swift build            # macOS: builds JitsiCore + JitsiMedia
# The SwiftUI app (JitsiApp) is built from Xcode; see Phase 4.
```

## Cross-checks the agent could not do

### Phase 0 — capture cross-check (optional)
Open `https://jitsi.luki.org/<dedicated-room>` in a browser, capture the
XMPP-WebSocket frames in DevTools, and confirm they match the agent's headless
`docs/fixtures/*.json` (in particular that no stanza the web client sends is
missing). Courtesy rules in `docs/live-testing.md` still apply.

### Phase 1 — macOS URLSession confirmation
`URLSessionWebSocketTask` differs between Apple Foundation and swift-corelibs
(Linux). After `URLSessionStanzaTransport` lands, confirm on macOS that it
connects to `wss://jitsi.luki.org/xmpp-websocket`, completes SASL ANONYMOUS +
bind + MUC join, and reaches `session-initiate` — matching the Linux
`[CLOUD-LIVE]` run.

### Phase 2 — media smoke test
Two-participant call (this app vs. a browser tab in the same dedicated room):
audio + video both directions. Watch `SessionDescriptionMapper` closely — it is
the riskiest integration point.

### Phase 3 — multi-party stability
4–5 participants; verify SSRC↔participant mapping, lastN/quality decisions, and
dominant-speaker highlight. Use a **private instance** for sustained load.

### Phase 4 — app loop
Launch → paste conference URL → join → participant grid → mute/camera → leave,
plus the malformed-URL inline error.
