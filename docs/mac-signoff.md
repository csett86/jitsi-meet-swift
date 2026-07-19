# macOS sign-off record

Human verification of `[MAC]` items on real Apple hardware. Each row stays
**pending** until a human confirms it. The agent must never mark these verified.

| Phase | Item                                            | Status  | Verified by | Date | Notes |
| ----- | ----------------------------------------------- | ------- | ----------- | ---- | ----- |
| 0     | Browser DevTools capture matches headless fixtures (optional cross-check) | pending | — | — | Optional; not a blocker. |
| 1/2   | macOS build links stasel/WebRTC; JitsiCore tests pass on Apple Foundation | ✅ CI | `ci-macos.yml` run #2 | 2026-07-19 | Swift 6.3.2. WebRTC 125.0.0 resolved + XCFramework linked; JitsiMedia compiles. Automated, not live-hardware. |
| 1     | `URLSessionStanzaTransport` on macOS reaches `session-initiate` (live) | ✅ verified | Christoph Settgast | 2026-07-19 | macOS 26.5.2 / Xcode 26.6 / Swift 6.3.3. `JITSI_LIVE_TESTS=1 swift test --filter JitsiLiveTests` → 3/3 passed (not skipped): Apple `URLSession` opened `wss://jitsi.luki.org/xmpp-websocket`, SASL ANONYMOUS + bind + MUC join + caps + TURN/STUN ICE; two clients reached `session-initiate`. |
| 2     | `SDPBuilder.offer` accepted by real `RTCPeerConnection.setRemoteDescription` | ✅ verified | Christoph Settgast | 2026-07-19 | macOS 26.5.2 / Xcode 26.6 / Swift 6.3.3. New `JitsiMediaTests` (`swift test --filter JitsiMediaTests`): a real `RTCPeerConnection` accepts the offer built from the `lukijitsi-join` `session-initiate`; mids + fmtp survive. Automated on real WebRTC/Apple hardware, **offline** (no live JVB). |
| 2     | `session-accept` from local answer accepted by the JVB | pending | — | — | Local half done: `JitsiMediaTests` drives the shipping `MediaSession.accept()` (createAnswer → session-accept) and the emitted Jingle round-trips (audio+video). **JVB acceptance still needs a live call.** |
| 2     | Two-party audio+video smoke test                | pending | — | — | app vs. browser tab, both directions, ICE connects. |
| 3     | 4–5 participant stability                        | pending | — | — | Use a private instance for load. |
| 4     | Full app loop (join → grid → controls → leave)  | pending | — | — | Awaits Phase 4. |

_macOS compile/link is green in CI (`ci-macos.yml`). The Phase 1 URLSession
transport is verified live on Apple hardware (`wss://` connect → join →
two-party `session-initiate`), and a real `RTCPeerConnection` accepts the
generated offer SDP (`JitsiMediaTests`, offline). Still unverified by a human:
JVB acceptance of our `session-accept`, and the full media plane — camera/mic
capture, ICE connectivity, and real two-party audio+video rendering._
