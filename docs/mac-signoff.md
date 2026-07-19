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
| 2     | Two-party audio+video smoke test                | ◑ partial | Christoph Settgast | 2026-07-19 | **Transport verified headlessly:** primary (real `RTCPeerConnection`) + a signaling-only secondary → ICE `connected` to the JVB (proves the session-accept/trickle path). **Not yet verified:** real camera/mic RTP in both directions and on-screen rendering — needs the Phase 4 app + a human with a browser tab. |
| 3     | `BridgeChannel` connects to the colibri `<web-socket>`; dominant speaker surfaces | ✅ verified | Christoph Settgast | 2026-07-19 | Live call on jitsi.luki.org (`JITSI_LIVE_TESTS=1 swift test --filter testLiveBridgeChannelConnects`). `onBridgeOpen` fired — Apple `URLSession` completed the colibri wss handshake (Linux can't) — and a `DominantSpeakerEndpointChangeEvent` arrived and parsed (endpoint `swiftbridge-a`), so the inbound endpoint-message path works end to end. (Dominant-speaker delivery needs audio present, so the test asserts the wss open and only logs the speaker event.) |
| 3     | `MediaSession.setReceiverConstraints` accepted by the bridge (lastN/resolution take effect) | ◑ partial | Christoph Settgast | 2026-07-19 | Send path exercised over the live bridge (`ReceiverVideoConstraints` pushed after `onBridgeOpen`, no socket error). **Not verified:** that the constraints *actually change* which/what-resolution videos arrive — needs multiple media senders + on-screen rendering (Phase 4 app). |
| 3     | 4–5 participant stability                        | pending | — | — | Use a private instance for load. |
| 4     | Full app loop (join → grid → controls → leave)  | pending | — | — | Awaits Phase 4. |

_macOS compile/link is green in CI (`ci-macos.yml`). Verified live on Apple
hardware: the Phase 1 URLSession transport (`wss://` connect → join → two-party
`session-initiate`); a real `RTCPeerConnection` accepting the generated offer SDP
(offline); a full signaling↔media handshake where Jicofo accepts our
`session-accept` + trickle and ICE reaches `connected` against the real JVB; and
the Phase 3 colibri bridge channel opening over wss with a dominant-speaker event
surfacing. Still unverified by a human (all await the Phase 4 app + real
multi-party media): camera/mic RTP flowing both directions, receiver constraints
actually changing the received video, 4–5 participant stability, and on-screen
rendering._
