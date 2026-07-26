# macOS sign-off record

Human verification of `[MAC]` items on real Apple hardware. Each row stays
**pending** until a human confirms it. The agent must never mark these verified.

| Phase | Item                                            | Status  | Verified by | Date | Notes |
| ----- | ----------------------------------------------- | ------- | ----------- | ---- | ----- |
| 0     | Browser DevTools capture matches headless fixtures (optional cross-check) | pending | — | — | Optional; not a blocker. |
| 1/2   | macOS build links stasel/WebRTC; JitsiCore tests pass on Apple Foundation | ✅ CI | `ci-macos.yml` run #2 | 2026-07-19 | Swift 6.3.2. WebRTC 125.0.0 resolved + XCFramework linked; JitsiMedia compiles. Automated, not live-hardware. |
| 1     | `URLSessionStanzaTransport` on macOS reaches `session-initiate` (live) | ✅ verified | Christoph Settgast | 2026-07-19 | macOS 26.5.2 / Xcode 26.6 / Swift 6.3.3. `JITSI_LIVE_TESTS=1 swift test --filter JitsiLiveTests` → 3/3 passed (not skipped): Apple `URLSession` opened `wss://jitsi.luki.org/xmpp-websocket`, SASL ANONYMOUS + bind + MUC join + caps + TURN/STUN ICE; two clients reached `session-initiate`. |
| 2     | `SDPBuilder.offer` accepted by real `RTCPeerConnection.setRemoteDescription` | ✅ verified | Christoph Settgast | 2026-07-19 | macOS 26.5.2 / Xcode 26.6 / Swift 6.3.3. New `JitsiMediaTests` (`swift test --filter JitsiMediaTests`): a real `RTCPeerConnection` accepts the offer built from the `lukijitsi-join` `session-initiate`; mids + fmtp survive. Automated on real WebRTC/Apple hardware, **offline** (no live JVB). |
| 2     | `session-accept` from local answer accepted by the JVB | ✅ verified | Christoph Settgast | 2026-07-19 | Live 2-party call on jitsi.luki.org (`JITSI_LIVE_TESTS=1 swift test --filter testLiveTwoPartyMediaConnects`, via the new `ConferenceCall` glue). Jicofo accepted our `session-accept` + trickle `transport-info`; ICE reached `connected`. A logging-transport diagnostic first caught Jicofo rejecting every Jingle IQ with `bad-request: Missing required 'id' attribute` — fixed by adding IQ `id`s in `JingleBuilder`. |
| 2     | Two-party audio+video smoke test                | ✅ verified | Christoph Settgast | 2026-07-26 | Transport was verified headlessly on 2026-07-19 (primary `RTCPeerConnection` + signaling-only secondary → ICE `connected`). Completed on 2026-07-26 with the Phase 4 app in a live call on jitsi.luki.org: **camera and mic RTP in both directions, remote video on screen and remote audio audible** — confirmed by a human at the machine. |
| 3     | `BridgeChannel` connects to the colibri `<web-socket>`; dominant speaker surfaces | ✅ verified | Christoph Settgast | 2026-07-19 | Live call on jitsi.luki.org (`JITSI_LIVE_TESTS=1 swift test --filter testLiveBridgeChannelConnects`). `onBridgeOpen` fired — Apple `URLSession` completed the colibri wss handshake (Linux can't) — and a `DominantSpeakerEndpointChangeEvent` arrived and parsed (endpoint `swiftbridge-a`), so the inbound endpoint-message path works end to end. (Dominant-speaker delivery needs audio present, so the test asserts the wss open and only logs the speaker event.) |
| 3     | `MediaSession.setReceiverConstraints` accepted by the bridge (lastN/resolution take effect) | ◑ partial | Christoph Settgast | 2026-07-19 | Send path exercised over the live bridge (`ReceiverVideoConstraints` pushed after `onBridgeOpen`, no socket error). **Not verified:** that the constraints *actually change* which/what-resolution videos arrive — needs multiple media senders + on-screen rendering (Phase 4 app). |
| 3     | 4–5 participant stability                        | pending | — | — | Use a private instance for load. |
| 2/3   | ICE connection stays up for a sustained real call | ✅ fixed (CI) | `live-integration.yml` runs 30209824066 / 30210156713 | 2026-07-26 | **Root-caused and fixed.** The new `LiveSustainedCallTests` diagnostic (one timestamped XMPP+bridge+ICE timeline) showed the drop was never a network/ICE fault: with no keepalive the other participant is dropped at ~65s, Jicofo then correctly sends `session-terminate` (85.7s) because the conference no longer needs a bridge, and our client ACKed but **ignored** it — the lingering `RTCPeerConnection` failed on its own at 91.1s. Fix = XEP-0199 keepalive + real `session-terminate` teardown. Same test on macOS CI, keepalive **on**: 15/15 pings answered, no peer loss, no terminate, ICE **still `connected` after 150s**, test passed (157s). Keepalive **off** reproduced the failure exactly — that switch has since been removed, so the client can no longer run without a keepalive. _Automated on a GitHub macOS runner against the live JVB — which also rules out the earlier App-Nap / local-router theories, since it reproduces on a different machine and network._ |
| 2/3   | _(historical)_ the same item before the fix | ❌ was | Christoph Settgast | 2026-07-19 | Reproduced twice in live 2-party calls: ICE reached `connected` (host↔host, ~26ms RTT, bytes both ways) then dropped at 60–95s. At the time this looked like a network/ICE fault with no signaling to explain it; the CI timeline above later showed the real chain (peer dropped → Jicofo `session-terminate` → our unhandled teardown). Kept for provenance. |
| 3     | Remote participants each get their own receive m-section (client-side renegotiation) | ✅ automated | `swift test --filter SDPAcceptanceTests` | 2026-07-26 | Offline on real WebRTC: after replaying the multi-party `source-add` fixture, a real `RTCPeerConnection` accepts the rebuilt offer mid-session and creates one receiver per remote track, each on the mid we allocated (so tracks map back to participants exactly). |
| 3     | **Outbound** media decoded by another client (camera + mic) | ✅ verified | Christoph Settgast | 2026-07-26 | Live in `jitsi.luki.org/swiftest` with a browser participant. The browser's own `getStats()`: our video `video/AV1/pt41, 1280x720 @30fps, 435 frames decoded` on its `largeVideo` element (its connection panel: `Auflösung 1280x720, 30 fps, Codecs (A/V): opus, AV1`); our audio `opus, 1390 packets`. We send whatever codec the JVB lists first — AV1 here — and it decodes fine. The one fix needed to get here was `<SourceInfo>` presence: without it nobody ever requests our video (docs/findings.md). |
| 3     | **Inbound** video: received, decoded and rendered on screen | ✅ verified | Christoph Settgast | 2026-07-26 | Counters from the run: `↓ a/v 32157/6835529B (3395 frames, 2 streams, VP8)`, renderer frame counter `rendered 3395 frames of 7014e00d video at 360x640`, no gaps — the counter is attached to the same `RTCVideoTrack` the tile draws. **Human confirmed the remote video rendered correctly in the app window.** |
| 3     | **Inbound audio** RTP | ✅ verified | Christoph Settgast | 2026-07-26 | Zero in the first runs only because every other participant was muted; once a peer unmuted, `↓ a 32157 B` of opus arrived and kept climbing — and a **human confirmed the audio was audible**. Our *outbound* audio is confirmed separately (decoded by the browser; the bridge also picks us as dominant speaker, so it decodes our audio levels). |
| 3     | Receiver constraints actually change what the bridge sends | ✅ observed live | — | 2026-07-26 | The bridge answered `ForwardedSources: []` until the constraints were sent **keyed by source name**, then `["7014e00d-v0"]` and video began arriving. Supersedes the "◑ partial" row above. |
| 4     | Full app loop (join → grid → controls → leave)  | ◑ mostly verified | Christoph Settgast | 2026-07-26 | `open -n build/JitsiMeetSwift.app --args https://jitsi.luki.org/swiftest --autojoin --leave-after 25`: joined, camera + mic granted, ICE `connected`, 4 MB of video sent and 337 remote frames rendered, then left — the browser's roster no longer listed the participant and the process exited. A human confirmed the grid renders remote video and audio is audible. **Not yet clicked by a human:** the mic/camera toolbar buttons and the malformed-URL inline error (both unit-level only). |

> **Rooms used.** The 2026-07-26 media runs were made in
> `jitsi.luki.org/swiftest` at the maintainer's direction (his own room, with him
> in it), not in a `jitsimeetswiftfixturecapture…` one-off room. Sessions were
> seconds to ~2 minutes, 2–3 concurrent clients. Everything else in
> docs/live-testing.md still applies.

**As of 2026-07-26 the client carries a real call**: camera and microphone RTP
in both directions between this app and a browser participant on
jitsi.luki.org, with remote video rendered on screen and remote audio audible,
confirmed by a human at the machine. What made the media actually flow (and what
"ICE connected" hides) is written up in docs/findings.md.

_macOS compile/link is green in CI (`ci-macos.yml`). Verified live on Apple
hardware: the Phase 1 URLSession transport (`wss://` connect → join → two-party
`session-initiate`); a real `RTCPeerConnection` accepting the generated offer SDP
(offline); a full signaling↔media handshake where Jicofo accepts our
`session-accept` + trickle and ICE reaches `connected` against the real JVB; and
the Phase 3 colibri bridge channel opening over wss with a dominant-speaker event
surfacing. Still unverified by a human (all await the Phase 4 app + real
multi-party media): camera/mic RTP flowing both directions, receiver constraints
actually changing the received video, 4–5 participant stability, and on-screen
rendering. **The former "ICE drops at 60–95s" known issue is fixed** — root cause
was a missing XMPP keepalive plus an ignored `session-terminate`, confirmed by an
A/B on macOS CI (see the Phase 2/3 row and docs/findings.md)._
