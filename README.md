# jitsi-meet-swift

A native macOS Jitsi Meet client (SwiftUI/AppKit) — proof of concept.

> **⚠️ WARNING:** This is a rough draft, implemented heavily by @claude

WebRTC media via [`stasel/WebRTC`](https://github.com/stasel/WebRTC); custom
signaling against Jitsi's XMPP / Jingle / Colibri stack. The single user-facing
input is a full conference URL (default host `jitsi.luki.org`), from which every
connection detail is derived.

## Architecture — a hard Linux/Apple split

The load-bearing invariant: all difficult logic lives in a **pure-Swift core**
that builds and tests on Linux, so it can be developed and verified in CI (and in
the cloud sandbox) without Apple hardware. Apple frameworks are isolated behind
protocol boundaries.

```
Sources/
  JitsiCore/     PURE Swift — no AppKit/AVFoundation/WebRTC/Combine. Builds on Linux.
  JitsiMedia/    Apple-only — stasel/WebRTC + AVFoundation. macOS only. [MAC]
  JitsiApp/      macOS SwiftUI/AppKit app. Built in Xcode. [MAC]
Tools/
  LiveCapture/   Headless XMPP capture client for live fixture capture. [CLOUD-LIVE]
Tests/
  JitsiCoreTests/  Deterministic, offline — the CI gate. [CLOUD]
  JitsiLiveTests/  Live signaling tests — non-gating, opt-in. [CLOUD-LIVE]
docs/
  fixtures/      Committed captured traffic (single source of truth for tests)
  findings.md    Observed protocol reality of jitsi.luki.org
  live-testing.md  Courtesy rules for the volunteer-run server
  mac-runbook.md / mac-signoff.md  Human build/verify steps and sign-off
```

`JitsiMedia`/`JitsiApp` and the `stasel/WebRTC` dependency are only declared when
`Package.swift` is evaluated on macOS (`#if os(macOS)`), so Linux never sees them.

## Build & test

```sh
# The Linux CI gate — pure core, offline, deterministic:
swift build --target JitsiCore
swift test  --filter JitsiCoreTests

# On macOS, `swift build` additionally builds JitsiMedia (pulls stasel/WebRTC).
```

## Live testing

`jitsi.luki.org` is a **volunteer-run production** instance, not test
infrastructure. Live checks (`[CLOUD-LIVE]`) are on-demand, minimal-footprint,
and never scheduled. Read **`docs/live-testing.md`** before running anything live.

## Status

**Phase 0 & 1 complete on the cloud side.**

- Phase 0: repository/CI scaffolding, the URL parser, the stanza parser, and real
  committed fixtures from jitsi.luki.org (access model verified: **SASL
  ANONYMOUS**; signaling confirmed **classic Jingle / XEP-0166**).
- Phase 1: the signaling library — `StanzaTransport` protocol, `FakeTransport`
  (fixture replay), `URLSessionStanzaTransport` (live socket), `MUCSession`
  roster, `BackendCapabilities`/`TURNDiscovery`, and `JitsiConference`, which
  drives the full join → focus-invite flow and emits a normalized
  `ParsedSessionDescription`. Fully unit-tested offline over `FakeTransport`.
  The live Swift transport is `[MAC]` (Linux `URLSession` has no `wss` support);
  live behavior on Linux is validated via the Python drift check.
- Phase 2 (in progress): the Jingle↔SDP mapping — `SDPBuilder` (offer),
  `SDPAnswerParser`, `SDPCandidate`, `JingleBuilder` (`session-accept`) — lives
  in `JitsiCore/SDP` and is **unit-tested on Linux** (52 core tests). The WebRTC
  media layer (`PeerConnectionFactory`, `SessionDescriptionMapper`,
  `LocalMediaSource`, `MediaSession`) is written in `JitsiMedia` and
  compile-checked by the macOS CI, awaiting human media verification.

See `docs/findings.md`. Media (WebRTC) and UI (SwiftUI) are `[MAC]` — written by
the agent, verified by a human (`docs/mac-signoff.md`).
