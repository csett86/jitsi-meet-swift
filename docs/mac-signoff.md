# macOS sign-off record

Human verification of `[MAC]` items on real Apple hardware. Each row stays
**pending** until a human confirms it. The agent must never mark these verified.

| Phase | Item                                            | Status  | Verified by | Date | Notes |
| ----- | ----------------------------------------------- | ------- | ----------- | ---- | ----- |
| 0     | Browser DevTools capture matches headless fixtures (optional cross-check) | pending | — | — | Optional; not a blocker. |
| 1     | `URLSessionStanzaTransport` on macOS reaches `session-initiate` | pending | — | — | Awaits Phase 1 transport. |
| 2     | Two-party audio+video smoke test                | pending | — | — | Awaits Phase 2. |
| 3     | 4–5 participant stability                        | pending | — | — | Use a private instance for load. |
| 4     | Full app loop (join → grid → controls → leave)  | pending | — | — | Awaits Phase 4. |

_No items verified yet — nothing Apple-specific has been built._
