#!/usr/bin/env python3
"""Minimal, single-connection XMPP-over-WebSocket access probe for jitsi.luki.org.

Courtesy: ONE short connection, no room join. We open the XMPP stream, read the
server's stream:features (which advertises the SASL mechanisms), and close.
This tells us the auth model (does SASL ANONYMOUS work?) without any footprint
on the conference side.
"""
import asyncio
import json
import sys
import time
import websockets

HOST = "jitsi.luki.org"
WS_URL = f"wss://{HOST}/xmpp-websocket"

OPEN = f'<open xmlns="urn:ietf:params:xml:ns:xmpp-framing" to="{HOST}" version="1.0"/>'

async def main():
    frames = []
    t0 = time.time()

    def rec(direction, payload):
        frames.append({"direction": direction, "timestamp": round(time.time() - t0, 4), "payload": payload})

    async with websockets.connect(WS_URL, subprotocols=["xmpp"], open_timeout=15) as ws:
        rec("out", OPEN)
        await ws.send(OPEN)
        # Read a bounded number of frames, short timeout — we just want features.
        for _ in range(6):
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=8)
            except asyncio.TimeoutError:
                break
            if isinstance(msg, bytes):
                msg = msg.decode("utf-8", "replace")
            rec("in", msg)
            if "</stream:features>" in msg or "<stream:features" in msg and "/>" in msg:
                # Got features; that's all we need for the probe.
                break

    out = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdout"
    with open(out, "w") as f:
        json.dump(frames, f, indent=2)
    for fr in frames:
        print(f"[{fr['direction']}] {fr['payload'][:2000]}")
    print(f"\n--- {len(frames)} frames captured ---", file=sys.stderr)

asyncio.run(main())
