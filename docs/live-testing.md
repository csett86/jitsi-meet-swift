# Live testing against `jitsi.luki.org` — courtesy rules

`jitsi.luki.org` is **not** test infrastructure. It is a self-hosted,
volunteer-run **production** Jitsi instance operated by LUKi e.V. on a Hetzner
server, carrying real meetings for a real community under its own
[terms of use](https://jitsi.luki.org/terms.html) and a GDPR data-processing
agreement. Treat it as someone else's server that we are a guest on.

Every `[CLOUD-LIVE]` task references this file.

## Hard rules

1. **On-demand only. Never scheduled.** No cron, no nightly, no unattended
   loops. The live GitHub workflow is `workflow_dispatch`-only and non-gating.
2. **Minimal footprint.** Dedicated, clearly-named rooms; short sessions
   (seconds, not minutes); the fewest clients that answer the question.
3. **Concurrent-client cap: 3.** Phase 3 multi-party capture uses 2–3 headless
   signaling clients, briefly. Anything heavier or load-oriented must go to a
   throwaway private Jitsi instance — never point load at this community server.
4. **Fixtures are the source of truth for CI.** Live runs feed committed
   fixtures; the deterministic `[CLOUD]` tests replay those fixtures and gate the
   build. CI never depends on the server being up.
5. **Review the terms** at <https://jitsi.luki.org/terms.html> before automating.
6. **Get operator permission** before any *repeated* or *multi-client* testing
   beyond the one-off Phase 0 capture.

## Operator permission status

**Not yet obtained.** The Phase 0 access probe and the single two-party fixture
capture were kept to the minimal footprint these rules authorize (1–2 clients,
dedicated one-off rooms, sessions < ~30s, run once). **Before any repeated,
scheduled, heavier, or 3-client Phase 3 capture, obtain explicit permission from
the LUKi e.V. operators**, or switch to a private instance. Record the outcome
here when known.

## Dedicated test-room naming scheme

All live test rooms use the prefix **`jitsimeetswiftfixturecapture`** followed by
a short random suffix, e.g. `jitsimeetswiftfixturecapture4543a06c`. The prefix
makes our automated joins obvious to the operator and unlikely to collide with a
real meeting. One-off rooms — do not reuse a name.

## Max concurrent clients

**3.** (2 for the Phase 0 two-party join; up to 3 for Phase 3 multi-party
source traffic — and only after permission, or on a private instance.)

## How to run a live capture

```sh
# Access probe + two-party join capture (Phase 0), on demand:
#   see Tools/LiveCapture/python/ (access_probe.py, capture_join.py, make_fixtures.py)

# Live signaling integration tests (non-gating), opt-in:
JITSI_LIVE_TESTS=1 JITSI_TEST_URL="https://jitsi.luki.org/<dedicated-room>" \
  swift test --filter JitsiLiveTests
```
