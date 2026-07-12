# Test Environment

## Primary Target

**URL:** `https://alpha.jitsi.net`  
**Last verified:** 2026-07-12  
**Deployment type:** Anonymous (no JWT, no lobby, no authentication required)

## Connection Parameters Derived from URL

Given a conference URL `https://alpha.jitsi.net/<RoomName>`, the following
are derived by `BackendConfig`:

| Field | Value |
|---|---|
| XMPP WebSocket | `wss://alpha.jitsi.net/xmpp-websocket` |
| XMPP Domain | `alpha.jitsi.net` |
| MUC Domain | `conference.alpha.jitsi.net` |
| Auth Domain | `auth.alpha.jitsi.net` |
| Focus JID | `focus@auth.alpha.jitsi.net` |
| Conference JID | `<room_lowercase>@conference.alpha.jitsi.net` |

## Notes on `alpha.jitsi.net`

`alpha.jitsi.net` is Jitsi's own staging/bleeding-edge deployment, running
ahead of the stable `meet.jit.si` production build. Useful properties:

- Surfaces newer server-side behavior early (e.g. Colibri2 rollout,
  new XMPP features).
- Documented by the Jitsi community as prone to **unannounced breaking
  changes** and configuration inconsistencies.

**Treat any behavior captured against this endpoint as time-sensitive.**
If something stops working mid-project, re-probe the endpoint before
assuming a client-side bug. Update the "Last verified" date above whenever
you re-verify connection parameters.

## How to Refresh This File

1. Connect a browser to `https://alpha.jitsi.net/TestRoom` with DevTools open.
2. Inspect the WebSocket frames on the `xmpp-websocket` connection.
3. Confirm the XMPP domain, MUC domain, and Focus JID match the table above.
4. Update the "Last verified" date.
5. If anything differs, update the table **and** create an entry in
   `docs/findings.md`.
