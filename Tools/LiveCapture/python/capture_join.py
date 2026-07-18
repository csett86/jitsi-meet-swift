#!/usr/bin/env python3
"""Two-client join capture (Phase 0 'two-party join' fixture). Client A records
everything it sees; Client B joins a few seconds later to trigger Jicofo's
session-initiate + source-add, then both leave. Courtesy: 2 clients, one
dedicated room, ~22s total, on-demand."""
import asyncio, json, re, sys, time, uuid
import websockets

HOST = "jitsi.luki.org"
WS_URL = f"wss://{HOST}/xmpp-websocket"
MUC = f"conference.{HOST}"
FOCUS = f"focus.{HOST}"
ROOM_LOCAL = "jitsimeetswiftfixturecapture" + uuid.uuid4().hex[:8]
ROOM_JID = f"{ROOM_LOCAL}@{MUC}"

CLIENT_FEATURES = [
    "http://jabber.org/protocol/disco#info", "urn:xmpp:jingle:1",
    "urn:xmpp:jingle:apps:rtp:1", "urn:xmpp:jingle:apps:rtp:audio",
    "urn:xmpp:jingle:apps:rtp:video", "urn:xmpp:jingle:transports:ice-udp:1",
    "urn:xmpp:jingle:apps:dtls:0", "urn:xmpp:jingle:transports:dtls-sctp:1",
    "urn:ietf:rfc:5761", "urn:ietf:rfc:5888", "http://jitsi.org/tcc",
    "http://jitsi.org/opus-red", "urn:xmpp:jingle:apps:rtp:rtp-hdrext:0",
]
DISCO_GET_RE = re.compile(r"<iq[^>]*type='get'[^>]*from='([^']+)'[^>]*id='([^']+)'[^>]*>.*?disco#info", re.S)
DISCO_GET_RE2 = re.compile(r"<iq[^>]*from='([^']+)'[^>]*id='([^']+)'[^>]*type='get'[^>]*>.*?disco#info", re.S)

class Client:
    def __init__(self, name, record=False):
        self.name = name
        self.nick = "bot" + name + uuid.uuid4().hex[:4]
        self.uid = uuid.uuid4().hex
        self.record = record
        self.frames = []
        self.t0 = time.time()
        self.ws = None
        self.stop = asyncio.Event()

    def rec(self, d, p):
        if self.record:
            self.frames.append({"direction": d, "timestamp": round(time.time()-self.t0,4), "payload": p})

    async def send(self, p):
        self.rec("out", p); await self.ws.send(p)

    def disco_result(self, to, iq_id):
        feats = "".join(f'<feature var="{f}"/>' for f in CLIENT_FEATURES)
        return (f'<iq type="result" to="{to}" id="{iq_id}" xmlns="jabber:client">'
            f'<query xmlns="http://jabber.org/protocol/disco#info">'
            f'<identity category="client" type="pc" name="JitsiMeetSwift"/>{feats}</query></iq>')

    async def receiver(self):
        while not self.stop.is_set():
            try:
                msg = await asyncio.wait_for(self.ws.recv(), timeout=1.0)
            except asyncio.TimeoutError: continue
            except websockets.ConnectionClosed: break
            if isinstance(msg, bytes): msg = msg.decode("utf-8","replace")
            self.rec("in", msg)
            if "disco#info" in msg and "type='get'" in msg:
                m = DISCO_GET_RE.search(msg) or DISCO_GET_RE2.search(msg)
                if m:
                    await self.send(self.disco_result(m.group(1), m.group(2)))
            # Auto-accept the Jingle session so the flow completes (transport-info etc.)
            if "session-initiate" in msg:
                sid = re.search(r"sid='([^']+)'", msg)
                frm = re.search(r"from='([^']+)'", msg)
                iqid = re.search(r"id='([^']+)'", msg)
                if iqid:
                    await self.send(f'<iq type="result" to="{frm.group(1)}" id="{iqid.group(1)}" xmlns="jabber:client"/>')

    async def connect_and_join(self):
        self.ws = await websockets.connect(WS_URL, subprotocols=["xmpp"], open_timeout=15, max_size=None)
        self.rx = asyncio.create_task(self.receiver())
        O = f'<open xmlns="urn:ietf:params:xml:ns:xmpp-framing" to="{HOST}" version="1.0"/>'
        await self.send(O); await asyncio.sleep(0.6)
        await self.send('<auth xmlns="urn:ietf:params:xml:ns:xmpp-sasl" mechanism="ANONYMOUS"/>'); await asyncio.sleep(0.6)
        await self.send(O); await asyncio.sleep(0.6)
        await self.send('<iq type="set" id="bind1" xmlns="jabber:client"><bind xmlns="urn:ietf:params:xml:ns:xmpp-bind"/></iq>'); await asyncio.sleep(0.6)
        if self.record:
            await self.send(f'<iq type="get" id="disco1" to="{HOST}" xmlns="jabber:client"><query xmlns="http://jabber.org/protocol/disco#info"/></iq>'); await asyncio.sleep(0.3)
            await self.send(f'<iq type="get" id="ext2" to="{HOST}" xmlns="jabber:client"><services xmlns="urn:xmpp:extdisco:2"/></iq>'); await asyncio.sleep(0.3)
        await self.send(f'<iq type="set" id="conf1" to="{FOCUS}" xmlns="jabber:client"><conference xmlns="http://jitsi.org/protocol/focus" room="{ROOM_JID}" machine-uid="{self.uid}"/></iq>'); await asyncio.sleep(1.0)
        await self.send(f'<presence to="{ROOM_JID}/{self.nick}" xmlns="jabber:client">'
            f'<x xmlns="http://jabber.org/protocol/muc"/><stats-id>{self.nick}</stats-id>'
            f'<nick xmlns="http://jabber.org/protocol/nick">{self.nick}</nick>'
            f'<videomuted xmlns="http://jitsi.org/jitmeet/video">false</videomuted>'
            f'<audiomuted xmlns="http://jitsi.org/jitmeet/audio">false</audiomuted></presence>')

    async def leave(self):
        try:
            await self.send(f'<presence to="{ROOM_JID}/{self.nick}" type="unavailable" xmlns="jabber:client"/>')
        except Exception: pass
        await asyncio.sleep(0.3)
        self.stop.set()
        try: await self.ws.close()
        except Exception: pass

async def main():
    A = Client("A", record=True)
    B = Client("B", record=False)
    await A.connect_and_join()
    await asyncio.sleep(4.0)          # A alone
    await B.connect_and_join()        # B joins -> should trigger session-initiate for A
    await asyncio.sleep(10.0)         # capture session-initiate + source-add
    await B.leave()                   # -> source-remove for A
    await asyncio.sleep(3.0)
    await A.leave()

    out = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdout"
    with open(out, "w") as f: json.dump(A.frames, f, indent=2)
    si = any("session-initiate" in fr["payload"] for fr in A.frames)
    sa = any("source-add" in fr["payload"] for fr in A.frames)
    sr = any("source-remove" in fr["payload"] for fr in A.frames)
    print(f"room={ROOM_JID} frames={len(A.frames)} session_initiate={si} source_add={sa} source_remove={sr}", file=sys.stderr)

asyncio.run(main())
