# LiveCapture — Python capture scripts ([CLOUD-LIVE])

Throwaway plumbing for capturing signaling fixtures from a live Jitsi
deployment. The plan explicitly allows a small Python/Node WebSocket script for
capture — Linux `URLSessionWebSocketTask` is uneven, and the *shipping* transport
is the Swift `URLSessionStanzaTransport`; these scripts only need to reliably
produce fixtures.

**Read `docs/live-testing.md` first.** `jitsi.luki.org` is a volunteer-run
production server: on-demand only, dedicated rooms, minimal footprint, never
scheduled.

## Scripts

| Script              | What it does                                                              |
| ------------------- | ------------------------------------------------------------------------ |
| `access_probe.py`   | ONE short connection: `open` → `stream:features`. Proves SASL ANONYMOUS. No room join. |
| `capture_join.py`   | Two-client join in a dedicated room; records client A's frames including the Jingle `session-initiate`. ~22s. |
| `make_fixtures.py`  | Redacts ephemeral TURN credentials from a raw capture into a committed fixture. |

## Reproduce the committed fixtures

```sh
pip install websockets

# Access probe -> committed fixture
python3 access_probe.py raw-probe.json
python3 make_fixtures.py raw-probe.json docs/fixtures/lukijitsi-access-probe.json

# Two-party join -> committed fixture
python3 capture_join.py raw-join.json
python3 make_fixtures.py raw-join.json docs/fixtures/lukijitsi-join.json
```

The room name uses the dedicated prefix `jitsimeetswiftfixturecapture` + random
suffix (see `docs/live-testing.md`). Each run creates a fresh one-off room.

> Fixtures are captured **once** and committed. Do not re-run against
> `jitsi.luki.org` just to refresh — only when the drift check (Phase 1) flags a
> real change, or on a private instance.
