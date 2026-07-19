# macOS sign-off record

Human verification of `[MAC]` items on real Apple hardware. Each row stays
**pending** until a human confirms it. The agent must never mark these verified.

| Phase | Item                                            | Status  | Verified by | Date | Notes |
| ----- | ----------------------------------------------- | ------- | ----------- | ---- | ----- |
| 0     | Browser DevTools capture matches headless fixtures (optional cross-check) | pending | — | — | Optional; not a blocker. |
| 1/2   | macOS build links stasel/WebRTC; JitsiCore tests pass on Apple Foundation | ✅ CI | `ci-macos.yml` run #2 | 2026-07-19 | Swift 6.3.2. WebRTC 125.0.0 resolved + XCFramework linked; JitsiMedia compiles. Automated, not live-hardware. |
| 1     | `URLSessionStanzaTransport` on macOS reaches `session-initiate` (live) | pending | — | — | Needs a person + live server (`JITSI_LIVE_TESTS=1`). Not run by CI. |
| 2     | `SDPBuilder.offer` accepted by real `RTCPeerConnection.setRemoteDescription` | pending | — | — | Riskiest point; mids/fmtp most likely to need tuning. |
| 2     | `session-accept` from local answer accepted by the JVB | pending | — | — | Optionally check at signaling layer first (`[CLOUD-LIVE]`). |
| 2     | Two-party audio+video smoke test                | pending | — | — | app vs. browser tab, both directions, ICE connects. |
| 3     | 4–5 participant stability                        | pending | — | — | Use a private instance for load. |
| 4     | Full app loop (join → grid → controls → leave)  | pending | — | — | Awaits Phase 4. |

_macOS compile/link is green in CI (`ci-macos.yml`). Live-hardware behavior
(URLSession over wss, camera/mic, rendering) is still unverified by a human._
