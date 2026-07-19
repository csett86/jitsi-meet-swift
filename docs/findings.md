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

## Committed fixtures

| File                            | What it is                                             |
| ------------------------------- | ------------------------------------------------------ |
| `lukijitsi-access-probe.json`   | Minimal `open` → `stream:features` (proves ANONYMOUS). |
| `lukijitsi-join.json`           | Two-party join: features, bind, disco#info, TURN extdisco, conference-ready, MUC presences, **Jingle `session-initiate`**. |
