# Findings — observed protocol reality of `jitsi.luki.org`

Everything here was captured by this project's own headless client (see
`Tools/LiveCapture` and the committed `docs/fixtures/*.json`), considerately:
single/two clients, dedicated one-off rooms, sessions under ~30s. When this file
and a fresh capture disagree, trust the capture and `lib-jitsi-meet`.

_Last capture: 2026-07-18._

## Access & auth model — **anonymous access is permitted** ✅

The Phase 0 gating question was "does the server even allow anonymous joins?"
Answer: **yes.**

- Stream features (pre-auth) advertise exactly one SASL mechanism: `ANONYMOUS`.
- `<auth mechanism="ANONYMOUS"/>` succeeds; resource bind yields an anonymous
  JID `<random>@jitsi.luki.org/<resource>`.
- Jicofo's conference response carries `authentication='false'` — no JWT, no
  login, no forced lobby for room creation was encountered in the dedicated test
  rooms.
- `visitors-supported='false'`.

If this ever changes (auth/JWT/lobby enforced), Phase 0/1 assumptions change and
the auth model must be revisited — do not paper over it in code.

## Deployment topology (subdomain convention **confirmed**)

The standard Jitsi subdomain layout that `ConferenceURLParser` assumes matches
this deployment:

| Purpose            | Value                                   |
| ------------------ | --------------------------------------- |
| XMPP WebSocket     | `wss://jitsi.luki.org/xmpp-websocket`   |
| MUC domain         | `conference.jitsi.luki.org`             |
| Focus (Jicofo) JID | `focus.jitsi.luki.org`                  |
| Focus internal JID | `focus@auth.jitsi.luki.org`             |
| TURN/STUN host     | `turn.jitsi.luki.org`                   |

Server: **Prosody**. Jicofo focus component version: **1.0.1180**.

## Transport

- XMPP-over-WebSocket per **RFC 7395**, WebSocket subprotocol `xmpp`.
- Stream limits: `max-bytes` 10000 (pre-auth) / 262144 (post-auth),
  `idle-seconds` 840. Post-auth features include stream management
  (`urn:xmpp:sm:3`), CSI, roster versioning; bind required, session optional.
- Each frame is one complete stanza — `StanzaParser` parses frame-at-a-time.

## Server capabilities (disco#info on the domain)

Advertised components (so these features exist on the deployment): breakout
rooms (`breakout.`), **lobby** (`lobby.`), conference duration, end conference,
**speaker stats**, **polls**, **room metadata** (`metadata.`), **av moderation**
(`avmoderation.`). Features include `urn:xmpp:extdisco:1`/`:2`, ping, carbons,
vcard-temp, etc. These map to `BackendCapabilities` in Phase 1.

## TURN / STUN discovery (XEP-0215)

Both `urn:xmpp:extdisco:1` and `urn:xmpp:extdisco:2` are answered:

- STUN: `turn.jitsi.luki.org:3478`.
- TURN: `turn.jitsi.luki.org` over udp:3478, tcp:3478, tcp:443, `restricted='1'`
  with time-limited HMAC `username`/`password` credentials.
- The same service list is also pushed over a `room_metadata` `<json-message>`
  after join.

> The credential `password` values are **redacted** in the committed fixtures
> (they are HMAC-derived from the server's static TURN secret and expire
> quickly). Only the structure matters for the parser tests.

## Conference request flow (Jicofo)

1. After bind, the client sends a `conference` IQ to `focus.jitsi.luki.org`
   (`<conference xmlns='http://jitsi.org/protocol/focus' room='…' machine-uid='…'/>`).
2. Jicofo replies `ready='true'` with `focusjid='focus@auth.jitsi.luki.org'` and
   properties `authentication='false'`, `visitors-supported='false'`.
3. The client joins the MUC (presence with `stats-id`, `nick`, audio/video mute
   flags). `occupant-id` (`urn:xmpp:occupant-id:0`) is present on all presences.

## Signaling shape — **classic Jingle (XEP-0166), NOT Colibri2** ⭐

`session-initiate` arrives as a standard
`<jingle xmlns='urn:xmpp:jingle:1' action='session-initiate'>`:

- Separate `audio` and `video` `<content>` elements (bundle + `rtcp-mux`,
  `extmap-allow-mixed`).
- **Audio** codecs: opus (pt 111, 48000/2, transport-cc, fec), telephone-event
  (126). Header exts: ssrc-audio-level, sdes:mid, transport-wide-cc.
- **Video** codecs offered: **AV1 (41), VP8 (100), H264 (107, `42e01f`,
  packetization-mode=1), VP9 (101)**, all with ccm/fir, nack, nack/pli,
  transport-cc feedback. Header exts: AV1 dependency-descriptor, sdes:mid,
  abs-send-time, transport-wide-cc.
- **Transport**: `urn:xmpp:jingle:transports:ice-udp:1` with ICE ufrag/pwd, host
  candidates (private + public IPv4/IPv6, port 10000), DTLS fingerprint
  (`sha-256`, `setup='actpass'`, `cryptex='false'`), and a colibri bridge
  WebSocket URL (`<web-socket url='wss://…/colibri-ws/…'/>`).
- The JVB's own "mixed" sources appear as `name='jvb-a0'` / `jvb-v0` with
  `<ssrc-info owner='jvb'/>`.

**Implication:** the signaling core normalizes classic Jingle into
`ParsedSessionDescription`; there is no Colibri2 path to implement for this
deployment.

## Nuances that shape later phases

- **Jicofo probes the client's disco#info before inviting it.** A joining client
  receives a `disco#info` `get` from `…/focus` and must answer advertising Jingle
  / RTP features (`urn:xmpp:jingle:1`, `…apps:rtp:1`, audio/video, ice-udp,
  dtls:0, rtcp-mux/bundle, tcc). Only then is it considered a media endpoint.
- **A solo participant is NOT sent `session-initiate`.** This Jicofo defers the
  offer until at least a second real participant is present. Capturing
  `session-initiate` required a two-client join (hence `lukijitsi-join.json` is a
  two-party capture).
- **`source-add` / `source-remove` for another participant's media cannot be
  captured headlessly.** They are only emitted once a participant actually
  publishes media SSRCs (real SDP answer + ICE + DTLS), which needs WebRTC — not
  available on Linux. Phase 3 multi-party source fixtures therefore require a
  `[MAC]` media-capable client or a private instance; the XMPP-path pieces
  (presence, endpoint messages that traverse XMPP) remain capturable.
- **Dominant speaker path** was not observed over XMPP in these short captures;
  in newer deployments it travels over the WebRTC bridge data channel. Confirm
  the path on `jitsi.luki.org` when media is wired (`[MAC]`).

## Transport: Linux `URLSessionWebSocketTask` cannot do `wss://` (Phase 1)

The shipping transport is `URLSessionStanzaTransport` (over
`URLSessionWebSocketTask`). Empirically, on Linux (swift-corelibs Foundation,
Swift 6.0.3) a `wss://` WebSocket fails immediately with
`NSURLErrorUnsupportedURL (-1002)`. Apple's Foundation supports it, so:

- The Swift live transport is validated live on **macOS** (`[MAC]` — the Phase 1
  URLSession confirmation).
- On **Linux**, the live Swift tests (`JitsiLiveTests`) **skip** rather than
  fail, and live protocol/server behavior is validated instead via the Python
  capture + drift check (`Tools/LiveCapture/python`), which use a real WebSocket
  library and work on Linux.

This is why the deterministic core is driven by `FakeTransport` replaying
committed fixtures: it needs no working Linux WebSocket, and CI stays green
offline.

## The "call dies after 60–95s" drop — root cause (2026-07-26)

A live call reached ICE `connected`, then went `disconnected`/`failed` at 60–95s
every time, seemingly with no signaling to explain it. It is **not** a network,
ICE consent-freshness or macOS power-management problem. The macOS-CI
sustained-call diagnostic (`LiveSustainedCallTests`) produced this timeline:

```
[  6.4s] ICE connected
[ 65.6s] XMPP <- presence type=unavailable     <- the other participant is dropped
[ 85.7s] BRIDGE CLOSED code=1001
[ 85.7s] XMPP <- iq action=session-terminate   <- Jicofo ends our session
[ 91.1s] ICE disconnected                       <- merely the consequence
```

The chain:

1. A client that sends nothing is dropped by the server after ~60s idle. Our
   client had **no XEP-0199 keepalive at all** (`lib-jitsi-meet` pings every 10s).
2. That left the conference with a single participant, so it no longer needed a
   bridge session — **Jicofo correctly sent `session-terminate`**.
3. Our client ACKed the terminate and otherwise **ignored it**, leaving a live
   `RTCPeerConnection`. Its ICE then failed on its own ~5s later, which is the
   "mysterious" drop that was actually our own unhandled teardown.

**Fix:** XEP-0199 keepalive (10s, 3 missed = dead) + real `session-terminate`
handling that tears the media session down and clears session state so a later
re-invite starts clean.

**Verified live on macOS CI**, the same test run both ways while the keepalive
was still switchable (the switch has since been removed — keepalive is mandatory,
see ``KeepAlivePolicy``):

| | keepalive off (pre-fix) | keepalive on (shipped) |
| --- | --- | --- |
| peer at ~65s | `presence type=unavailable` | stays |
| `session-terminate` | at 85.7s | never |
| ICE after 150s | `disconnected` | **`connected`** |

### Hypotheses eliminated first (both by live probe)

- **An idle XMPP WebSocket is reaped by nginx at 60s** — no: an idle, joined
  connection survived 150s+ untouched.
- **An idle colibri bridge WebSocket is reaped at 60s** — no: it survived 170s+,
  closing only at teardown (code 1001).

### The bridge channel talks, and we were not listening

The JVB sends real diagnostics over the colibri channel that the client used to
discard (only dominant-speaker was parsed): `ServerHello` (JVB version),
`ForwardedSources`, `SenderSourceConstraints`, and
`EndpointConnectivityStatusChangeEvent` — the bridge's own view of whether an
endpoint's media is arriving. These are now surfaced (`onBridgeMessage`).
Observed JVB version: **2.3.291-gb4b5ccc8c**.

## Committed fixtures

| File                            | What it is                                             |
| ------------------------------- | ------------------------------------------------------ |
| `lukijitsi-access-probe.json`   | Minimal `open` → `stream:features` (proves ANONYMOUS). |
| `lukijitsi-join.json`           | Two-party join: features, bind, disco#info, TURN extdisco, conference-ready, MUC presences, **Jingle `session-initiate`**. |
| `multiparty-sources.json`       | **Synthetic** `source-add` / `source-remove` for two endpoints + an XMPP dominant-speaker message. Constructed from the real source format (owner, msid, SIM group) because headless clients can't publish media to generate real ones — see the Phase 3 nuance above. |

## Real media: what it takes for RTP to actually flow (2026-07-26)

Signaling completeness, ICE `connected` and DTLS `connected` are **not** enough:
a call can be fully "up" with zero media in either direction. Three separate
things had to be right, each found by running the app against
`jitsi.luki.org/swiftest` with a browser participant and reading the bridge's own
messages. (Endpoint ids below are from those runs.)

### 1. One receive-only m-section per remote source (client-side renegotiation)

The JVB offers exactly **two** m-sections — our audio and our video — and then
announces everyone else's media with Jingle `source-add`, never a new offer.
Unified Plan needs one m-section per received track, so the client synthesizes
them itself, sets the rebuilt offer on its own peer connection and answers it
locally. Nothing goes back to Jicofo for this (see ``RemoteSDPSession``). mids
are never renumbered — a removed source leaves an `a=inactive` tombstone — and
the mid is what maps a received track back to a participant.

### 2. Receiver constraints must be keyed by **source name**, not endpoint id

The bridge forwards *no* video until the client asks for some. With the legacy
endpoint-keyed message the bridge kept answering:

```json
{"colibriClass":"ForwardedSources","forwardedSources":[]}
```

Switching to the source-name form (`selectedSources` / `onStageSources`, and
`constraints` keyed by `<endpoint>-v0`) flipped it immediately to
`forwardedSources:["7014e00d-v0"]`, and remote video started arriving.

### 3. Our own sources need `<SourceInfo>` in presence

Other clients decide whether to *request* our camera from the bridge by reading
per-source state from our MUC presence:

```xml
<SourceInfo>{"swift-ab12-a0":{"muted":false},"swift-ab12-v0":{"muted":false,"videoType":"camera"}}</SourceInfo>
```

Without it we were a participant with an avatar and no video: the browser
received our **audio** fine, never subscribed to our video, and the bridge
reported `SenderSourceConstraints … "maxHeight":0` for our source the whole time.
Adding it produced `"maxHeight":720` within a second and the browser rendered our
camera at 960x540.

### The codec order in the offer is the deployment's preference — follow it

WebRTC encodes with the **first payload type** of the m-section, so whatever the
`session-initiate` lists first is what we send. On jitsi.luki.org that is
**AV1 (pt 41)**, and it works: a browser participant decodes our AV1 at
`1280x720 @30fps` (its own connection panel reports `Codecs (A/V): opus, AV1`).
`SDPBuilder` therefore keeps the offered order untouched; the `sendVideoCodec`
parameter exists only for pinning a codec while debugging interop.

> _Corrected._ An earlier run in this same session concluded that AV1 was
> undecodable by the browser — it showed our RTP arriving with **no resolved
> codec and 0 frames decoded**. That was a misreading: at the time the browser
> had never subscribed to our video at all (the `<SourceInfo>` presence above was
> missing), and the packet counter was a leftover from a previous app instance.
> Fixing the presence fixed the black tile; the codec was never the problem.

### What the bridge tells you (worth reading during any media debugging)

`SenderSourceConstraints` (is anyone asking for my video, and at what height),
`ForwardedSources` (what I am being sent), `EndpointStats` (every endpoint's
up/download bitrate and `maxEnabledResolution`), `ServerHello`, `ConnectionStats`.
Between those and WebRTC's own `inbound-rtp` / `outbound-rtp` / `transport`
counters, every failure above was diagnosable without guessing.
