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
2. `createAnswer` → the Jingle `session-accept` is **accepted by the JVB**.
   **✅ verified live** — `ConferenceCall` (the `JitsiConference`↔`MediaSession`
   glue) sends the `session-accept` back with correct addressing (reply IQ → the
   focus *occupant* JID, with a required IQ `id`) and trickles `transport-info`.
   Run:
   ```sh
   JITSI_LIVE_TESTS=1 swift test --filter testLiveTwoPartyMediaConnects
   ```
   A primary (real `RTCPeerConnection`) plus a signaling-only secondary; ICE must
   reach `connected` — proof Jicofo accepted our answer and the JVB transport
   came up. (Regression history: Jicofo first rejected our IQs with
   `bad-request: Missing required 'id' attribute`; the fix was IQ `id`s in
   `JingleBuilder`.)
3. Two-participant call with **real media rendering** (this app vs. a browser tab
   in the same dedicated room): camera/mic RTP both directions, remote video on
   screen. _Mostly done — see docs/mac-signoff.md for the evidence from the
   2026-07-26 run: our camera decoded at 1280x720 by a browser participant, a
   remote camera decoded and rendered here, and opus arriving once a peer
   unmuted. What still needs a human is eyeballing the app's own window and
   hearing the audio._
4. **✅ Fixed — the call now survives a sustained hold.** The former "ICE dies at
   60–95s" issue was **not** a network/ICE fault. Root cause: the client sent no
   XMPP keepalive, so an idle participant was dropped at ~60s; the conference then
   had one participant left, so Jicofo correctly sent `session-terminate`; and the
   client ACKed but ignored it, leaving a peer connection that failed on its own
   ~5s later. Fixed by XEP-0199 keepalive + real `session-terminate` teardown.
   Regression test (also the diagnostic — it prints one timestamped
   XMPP/bridge/ICE timeline):
   ```sh
   JITSI_LIVE_TESTS=1 JITSI_CALL_SECONDS=150 \
     swift test --filter testLiveSustainedCallSurvives
   ```
   Verified on macOS CI both ways (see docs/mac-signoff.md). Note this is still
   about *connection* survival — real camera/mic RTP and rendering remain item 3.

### Phase 3 — multi-party stability
The multi-party logic is pure and unit-tested on Linux (`SourceManager`,
`QualityController`, `DominantSpeakerTracker`, wired into `JitsiConference`). What
a human must verify on macOS:

1. `JitsiMedia/BridgeChannel` connects to the colibri `<web-socket>` URL from the
   `session-initiate` (Apple `URLSession` wss — Linux can't), and inbound
   endpoint messages surface the dominant speaker. **✅ verified live** — run:
   ```sh
   JITSI_LIVE_TESTS=1 swift test --filter testLiveBridgeChannelConnects
   ```
   Asserts `ConferenceCall.onBridgeOpen` fires (the wss handshake completed via a
   `URLSessionWebSocketDelegate`); the run also observed a
   `DominantSpeakerEndpointChangeEvent` (logged, not asserted — it needs audio
   present, so it can be absent on a silent call).
2. `MediaSession.setReceiverConstraints(_:)` (from `QualityController`) is
   accepted by the bridge and actually changes which/what resolution videos
   arrive. **✅ observed with the Phase 4 app** — the bridge answers
   `ForwardedSources` with the requested source and starts sending it. Note the
   message must be **source-name keyed**; the earlier endpoint-keyed form was
   silently ignored and no video was ever forwarded (docs/findings.md).
3. 4–5 participant call: SSRC↔participant mapping is correct, lastN/quality
   decisions behave, dominant-speaker highlight tracks. Use a **private
   instance** for sustained load (do not strain jitsi.luki.org). _Still pending._

### Phase 4 — app loop

Build the bundle (Info.plist with the camera/mic usage descriptions, embedded
WebRTC framework, ad-hoc signature) and run it:

```sh
./Tools/mac-app/make-app.sh          # -> build/JitsiMeetSwift.app
open build/JitsiMeetSwift.app
```

Manual pass: launch → paste conference URL → join → participant grid →
mute/camera → leave, plus the malformed-URL inline error.

Unattended pass (what the live checks use — keeps the session short, as
docs/live-testing.md requires):

```sh
open -n build/JitsiMeetSwift.app --args \
  https://jitsi.luki.org/<room> --autojoin --leave-after 25 --log /tmp/jitsi-a.log
```

`--snapshot <path> [--snapshot-after <seconds>]` writes a PNG of the app's own
window. Metal-rendered video is invisible to AppKit's view-drawing APIs, so this
is the only way to check *rendering* (is the video there, is the self-view
mirrored, is the right tile highlighted) without a human at the screen — and
capturing our own window needs no screen-recording permission.

The app logs to `~/Library/Logs/JitsiMeetSwift.log` (or `--log <path>`). What to
look for, in order:

| Line | Means |
| --- | --- |
| `device access: camera=true microphone=true` | TCC granted — the bundle's Info.plist is being seen. |
| `negotiated: audio/a/sendrecv video/v/sendrecv audio-r1/a/recvonly …` | Receive sections were built, one per remote track. |
| `bridge <- {"colibriClass":"ForwardedSources","forwardedSources":["<ep>-v0"]}` | The bridge accepted our receiver constraints and is sending video. |
| `bridge <- {"colibriClass":"SenderSourceConstraints", …, "maxHeight":720}` | Someone is requesting **our** camera (needs `<SourceInfo>` presence). |
| `media ↑ a/v …B (N frames, AV1) · ↓ a/v …B (N frames, 2 streams, VP8)` | Real RTP in both directions, from WebRTC's own counters, with the codecs actually in use (we send whatever the JVB lists first). |
| `rendered N frame(s) of <ep> video at 960x540` | Decoded frames reaching the renderer the tile draws. |

To check the *other* side of the call, open the same room in a browser and read
its stats from the JS console — `inbound-rtp` for our SSRC should show a resolved
codec and a rising `framesDecoded`. Packets arriving with **no** resolved codec
and zero frames usually means nobody actually subscribed to us (check
`SenderSourceConstraints` on our side), not that the codec is wrong — see the
correction in docs/findings.md.
