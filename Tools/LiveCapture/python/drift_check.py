#!/usr/bin/env python3
"""Minimal-footprint drift check against a live Jitsi deployment.

A SINGLE short client join (no session-initiate, which would need a 2nd client)
that extracts structural markers of the signaling handshake and compares them to
what the committed fixture recorded. Exits non-zero (and prints a diff) when the
server's behavior has drifted, so fixtures can be refreshed deliberately.

Courtesy (docs/live-testing.md): one client, dedicated room, ~10s, on-demand.

Usage:
    drift_check.py [conference-url] [--fixture docs/fixtures/lukijitsi-join.json]
"""
import asyncio
import json
import re
import sys
import uuid

import websockets


def markers_from_frames(frames):
    """Reduce a list of {direction,payload} frames to structural markers."""
    incoming = [f["payload"] for f in frames if f["direction"] == "in"]
    blob = "\n".join(incoming)
    mechanisms = sorted(set(re.findall(r"<mechanism>([^<]+)</mechanism>", blob)))
    disco_types = sorted(set(re.findall(r"identity category='component' type='([^']+)'", blob)))
    conf = re.search(r"<conference ready='([^']+)'", blob)
    auth = re.search(r"name='authentication'|value='([^']*)' name='authentication'", blob)
    auth_val = re.search(r"value='([^']*)' name='authentication'", blob)
    turn_hosts = sorted(set(re.findall(r"type='turn'[^>]*host='([^']+)'", blob)
                            + re.findall(r"host='([^']+)'[^>]*type='turn'", blob)))
    return {
        "sasl_mechanisms": mechanisms,
        "disco_component_types": disco_types,
        "conference_ready": conf.group(1) if conf else None,
        "conference_authentication": auth_val.group(1) if auth_val else None,
        "turn_hosts": turn_hosts,
    }


async def capture_live(url):
    m = re.sub(r"^https?://", "", url).split("/")
    host = m[0]
    room_local = "jitsimeetswiftdriftcheck" + uuid.uuid4().hex[:8]
    room = f"{room_local}@conference.{host}"
    focus = f"focus.{host}"
    nick = "driftbot" + uuid.uuid4().hex[:4]
    ws_url = f"wss://{host}/xmpp-websocket"

    frames = []
    rec = lambda d, p: frames.append({"direction": d, "payload": p})
    O = f'<open xmlns="urn:ietf:params:xml:ns:xmpp-framing" to="{host}" version="1.0"/>'

    async with websockets.connect(ws_url, subprotocols=["xmpp"], open_timeout=15, max_size=None) as ws:
        async def send(p):
            rec("out", p); await ws.send(p)
        stop = asyncio.Event()

        async def rx():
            while not stop.is_set():
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=1.0)
                except (asyncio.TimeoutError,):
                    continue
                except websockets.ConnectionClosed:
                    break
                if isinstance(msg, bytes):
                    msg = msg.decode("utf-8", "replace")
                rec("in", msg)

        rxt = asyncio.create_task(rx())
        await send(O); await asyncio.sleep(0.7)
        await send('<auth xmlns="urn:ietf:params:xml:ns:xmpp-sasl" mechanism="ANONYMOUS"/>'); await asyncio.sleep(0.7)
        await send(O); await asyncio.sleep(0.7)
        await send('<iq type="set" id="b" xmlns="jabber:client"><bind xmlns="urn:ietf:params:xml:ns:xmpp-bind"/></iq>'); await asyncio.sleep(0.7)
        await send(f'<iq type="get" id="d" to="{host}" xmlns="jabber:client"><query xmlns="http://jabber.org/protocol/disco#info"/></iq>'); await asyncio.sleep(0.4)
        await send(f'<iq type="get" id="e" to="{host}" xmlns="jabber:client"><services xmlns="urn:xmpp:extdisco:2"/></iq>'); await asyncio.sleep(0.4)
        await send(f'<iq type="set" id="c" to="{focus}" xmlns="jabber:client"><conference xmlns="http://jitsi.org/protocol/focus" room="{room}" machine-uid="{uuid.uuid4().hex}"/></iq>'); await asyncio.sleep(1.5)
        await send(f'<presence to="{room}/{nick}" type="unavailable" xmlns="jabber:client"/>'); await asyncio.sleep(0.3)
        stop.set(); await rxt
    return frames


def main():
    args = [a for a in sys.argv[1:]]
    url = "https://jitsi.luki.org/driftcheck"
    fixture = "docs/fixtures/lukijitsi-join.json"
    i = 0
    while i < len(args):
        if args[i] == "--fixture":
            fixture = args[i + 1]; i += 2
        else:
            url = args[i]; i += 1

    expected = markers_from_frames(json.load(open(fixture)))
    # The fixture is a 2-party capture; the drift check is single-client, so drop
    # markers a solo client can't observe (none here — all handshake markers).
    live = markers_from_frames(asyncio.run(capture_live(url)))

    drift = {}
    for key in ("sasl_mechanisms", "disco_component_types", "conference_ready",
                "conference_authentication", "turn_hosts"):
        if expected.get(key) != live.get(key):
            drift[key] = {"fixture": expected.get(key), "live": live.get(key)}

    if drift:
        print("DRIFT DETECTED — refresh fixtures deliberately:")
        print(json.dumps(drift, indent=2))
        sys.exit(1)
    print("No drift. Live markers match the committed fixture:")
    print(json.dumps(live, indent=2))


if __name__ == "__main__":
    main()
