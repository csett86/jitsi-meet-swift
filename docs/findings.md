# Findings

This file records protocol behaviors, server-side quirks, or assumption
violations discovered during development and testing against
`alpha.jitsi.net` (or any other endpoint).

Add an entry whenever a live observation **contradicts an assumption** in
the plan document or in this codebase. Keep entries in reverse-chronological
order (newest first).

---

## 2026-07-14 — Live spike comparison: alpha join diverges at MUC presence

**Endpoint:** alpha.jitsi.net  
**Phase:** Phase 0

**Observed:** The signaling spike successfully connected, negotiated SASL ANONYMOUS, and bound a resource, but the live `testroom@conference.alpha.jitsi.net` join returned a `presence type='error'` instead of progressing into the fixture's self-presence and `session-initiate` flow. The server also advertised extra features in `stream:features` beyond the synthetic fixture's minimal ANONYMOUS-only shape.

**Assumed:** The synthetic fixture represented the live happy path to session-initiate.

**Impact:** The synthetic fixture has been replaced with the live browser capture from `TestRoom`, and the spike now has an optional `--json` mode for repeatable transcript capture. The parser also accepts the live alpha grouping namespace observed in session-initiate.

**Status:** Resolved

---

## Template

```
### YYYY-MM-DD — <Short title>

**Endpoint:** alpha.jitsi.net (or other)  
**Phase:** Phase N  
**Observation:** What was actually observed.  
**Assumed behavior:** What the plan assumed.  
**Impact:** How this changes the implementation.  
**Status:** Open / Resolved (link to commit or PR if resolved)
```

---

### 2026-07-12 — Phase 0 Signaling Spike: Synthetic fixture analysis

**Endpoint:** alpha.jitsi.net (live capture was not possible in the sandboxed CI build environment)  
**Phase:** Phase 0

#### Authentication mechanism

**Observed:** SASL ANONYMOUS (RFC 4505) with an empty initial response (`<auth mechanism="ANONYMOUS"/>`, no `=` base64 padding).  
**Assumed:** SASL ANONYMOUS.  
**Impact:** None — assumption confirmed. No credentials required. `SASLAuthenticator` in `Transport/SASLAuthenticator.swift` is correct as implemented.

#### Session-initiate shape: classic Jingle, not Colibri2

**Observed:** The session-initiate arrives as a classic Jingle IQ (XEP-0166 + XEP-0167 + XEP-0261):
- `<iq type="set">` containing `<jingle xmlns="urn:xmpp:jingle:1" action="session-initiate">`
- Two contents: `audio` and `video`, each with `<description>` (RTP+SSMA) and `<transport>` (ICE-UDP + DTLS-SRTP fingerprint)
- A `<group semantics="BUNDLE">` child for BUNDLE negotiation (RFC 5888)
- No Colibri2 (`urn:ietf:params:xml:ns:xmpp-colibri2`) envelope observed at session-initiate time

**Assumed:** Possibly Colibri2 or a JSON channel, given alpha.jitsi.net's bleeding-edge status.  
**Impact:** `JingleContent.swift` is built around the correct wire format. No Colibri2 parsing needed for the session-initiate path. Colibri2 _may_ appear later in bridge-side channel management (Phase 2), but the client-facing handshake remains classic Jingle.

⚠️ **Alpha-specific flag:** Colibri2 channel management (for bridge communication) is used internally by Jicofo; if a future alpha version exposes this at the MUC client layer it would be a breaking change. Re-verify on alpha after each major Jitsi release.

#### ICE/DTLS transport structure

**Observed:**
- Single ICE-UDP transport per content with `ufrag` + `pwd` attributes on the `<transport>` element
- DTLS fingerprint inline: `<fingerprint hash="sha-256" setup="actpass">`
- One candidate in the fixture (`type="host"`, from JVB's IP); real deployments send relay candidates too
- No ICE-lite flag observed (JVB does support ICE-lite in some configurations — re-verify live)

**Impact:** `ICEUDPTransport`, `DTLSFingerprint`, and `ICECandidate` types in `JingleContent.swift` match the observed shape.

#### Disco feature flags (alpha.jitsi.net)

**Observed** (synthetic, derived from lib-jitsi-meet behaviour):
- Server domain: `urn:xmpp:extdisco:2`, `urn:ietf:rfc:5389`
- Conference component: `http://jitsi.org/lobby`, `http://jitsi.org/visitors`
- **Not yet observed live:** `urn:xmpp:jingle:apps:rtp:ssma:0` (SSMA) as a server feature var; it appears in stanza payloads, not in disco

**Impact:** `BackendCapabilities.supportsLobby` and `supportsVisitors` are correctly populated. E2EE flag (`http://jitsi.org/e2ee`) was NOT observed in the fixture — treat `supportsE2EE` as `false` until confirmed live.

⚠️ **Alpha-specific flag:** Alpha is ahead of stable and may advertise experimental features not yet in production. Run `DiscoInfo` queries and dump the full feature list on first connection to avoid stale hardcoded assumptions.

#### Jitsi presence extensions

**Observed:**
- `<stats-id xmlns="http://jitsi.org/jitmeet">` — opaque device identifier
- `<videotype xmlns="http://jitsi.org/jitmeet/video">camera|desktop</videotype>`
- `<region xmlns="http://jitsi.org/jitmeet">` — geographic region string
- `<features xmlns="http://jitsi.org/jitmeet">` — list of `<feature var="..."/>` capability URIs

**Impact:** All four are parsed in `ParticipantPresence.swift`. The `dominant-speaker` extension (`<speakerstats>`) was not observed in the fixture — its namespace (`http://jitsi.org/jitmeet`) matches; add parsing when confirmed live.

#### XEP-0215 external services

**Observed:** Three services in fixture:
1. STUN (UDP 3478)
2. TURN TCP 443 (`username` + `password` credentials)
3. TURNS TCP 443 (same)

**Impact:** `TURNDiscovery.swift` parses all three service types correctly. Real deployments may return UDP TURN too — the parser handles any `type` value.

#### Stanza shapes flagged as potentially unstable

| Stanza / Feature | Risk | Notes |
|---|---|---|
| `<group semantics="BUNDLE">` inside Jingle | Medium | BUNDLE group namespace is `urn:ietf:rfc:5888`; alpha may switch to RFC 8829 SDP semantics |
| `<extmap-allow-mixed>` in RTP description | Low | RFC 8285 extension; parseable but currently ignored |
| `<ssrc-group semantics="FID">` | Low | RTX grouping; present in video, ignore if absent |
| Colibri2 channel management post-join | High | Alpha known to use Colibri2 for bridge channels after session-initiate; verify Phase 2 IQs |
| `speakerstats` / dominant speaker | Medium | Namespace known but not confirmed in fixture |

#### SYNTHETIC fixture disclaimer

The fixture at `docs/fixtures/alphajitsi-join.json` is **synthetic** — it was constructed from protocol specs and lib-jitsi-meet source analysis because direct live capture was not possible in the sandboxed build environment.

**Action required before Phase 2:** Run `Tools/SignalingSpike` against `alpha.jitsi.net` with a real second-tab participant and diff the resulting console output against the fixture. Update `StanzaParserTests` with any discrepancies before writing WebRTC media code.

---

<!-- Add new entries above this line -->
