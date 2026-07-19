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

# Phase 2 media SDP check against a real RTCPeerConnection (macOS only, offline):
swift test --filter JitsiMediaTests
# The SwiftUI app (JitsiApp) is built from Xcode; see Phase 4.
```

## Cross-checks the agent could not do

### Phase 0 — capture cross-check (optional)
Open `https://jitsi.luki.org/<dedicated-room>` in a browser, capture the
XMPP-WebSocket frames in DevTools, and confirm they match the agent's headless
`docs/fixtures/*.json` (in particular that no stanza the web client sends is
missing). Courtesy rules in `docs/live-testing.md` still apply.

### Phase 1 — macOS URLSession confirmation
`URLSessionStanzaTransport` has landed. Confirmed on Linux: swift-corelibs
`URLSessionWebSocketTask` cannot open `wss://` (fails `-1002`
`NSURLErrorUnsupportedURL`), so the Swift live tests **skip** there and live
protocol validation runs via the Python drift check. **macOS is the primary
validation of the Swift transport.** Run:

```sh
JITSI_LIVE_TESTS=1 JITSI_TEST_URL="https://jitsi.luki.org/<dedicated-room>" \
  swift test --filter JitsiLiveTests
```

Confirm on macOS that `testLiveConnectAndJoin` connects to
`wss://jitsi.luki.org/xmpp-websocket`, completes SASL ANONYMOUS + bind + MUC
join (reaching `.joined`, with capabilities + ICE servers), and that
`testLiveReachesSessionInitiate` (two clients) reaches `session-initiate` — i.e.
Apple's `URLSession` behaves as the Python capture did on Linux.

### Phase 2 — media smoke test
The media layer is implemented (`PeerConnectionFactory`, `SessionDescriptionMapper`,
`LocalMediaSource`, `MediaSession`). The Jingle↔SDP mapping is unit-tested on
Linux in `JitsiCore/SDP`; what a human must verify on macOS:

1. The SDP that `SDPBuilder.offer` produces is **accepted** by a real
   `RTCPeerConnection.setRemoteDescription` (the riskiest point — the mid values
   and fmtp lines are the most likely to need adjustment). **✅ now covered by an
   automated offline test** — `swift test --filter JitsiMediaTests` feeds the
   fixture-derived offer to a real `RTCPeerConnection` on Apple hardware (no live
   server). That same target also drives the shipping `MediaSession.accept()`
   path and confirms the emitted `session-accept` round-trips.
2. `createAnswer` → `SessionDescriptionMapper.sessionAccept` produces a Jingle
   `session-accept` the JVB accepts (optionally check at the signaling layer
   first, `[CLOUD-LIVE]`, before full media). _Local half automated (see item 1);
   JVB acceptance still needs a live call._
3. Two-participant call (this app vs. a browser tab in the same dedicated room):
   audio + video both directions, ICE connects (watch `onIceStateChange`).

### Phase 3 — multi-party stability
4–5 participants; verify SSRC↔participant mapping, lastN/quality decisions, and
dominant-speaker highlight. Use a **private instance** for sustained load.

### Phase 4 — app loop
Launch → paste conference URL → join → participant grid → mute/camera → leave,
plus the malformed-URL inline error.
