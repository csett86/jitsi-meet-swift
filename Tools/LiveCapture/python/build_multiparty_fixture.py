#!/usr/bin/env python3
"""Build a synthetic multi-party source-add/source-remove fixture.

Headless clients can't publish media, so real source-add/source-remove can't be
captured (see docs/findings.md). These stanzas are synthesized from the source
format observed in the real session-initiate (jvb-a0/jvb-v0, ssrc-info owner,
SIM groups), with real endpoint owners instead of the bridge.
"""
import json

ROOM = "multipartyroom@conference.jitsi.luki.org"
FOCUS = "focus@auth.jitsi.luki.org/focus"
US = "us@jitsi.luki.org/res"
SID = "9pupqtidrilf8"


def source(ssrc, ep, name=None, msid=None):
    s = f"<source ssrc='{ssrc}'"
    if name:
        s += f" name='{name}'"
    s += " xmlns='urn:xmpp:jingle:apps:rtp:ssma:0'>"
    s += f"<ssrc-info owner='{ROOM}/{ep}' xmlns='http://jitsi.org/jitmeet'/>"
    if msid:
        s += f"<parameter name='msid' value='{msid}'/>"
    s += "</source>"
    return s


def content(name, media, sources_xml, groups_xml=""):
    return (f"<content creator='initiator' name='{name}' senders='both'>"
            f"<description xmlns='urn:xmpp:jingle:apps:rtp:1' media='{media}'>"
            f"{sources_xml}{groups_xml}</description></content>")


def jingle(action, contents_xml, iq_id):
    return (f"<iq type='set' from='{ROOM}/focus' to='{US}' id='{iq_id}'>"
            f"<jingle xmlns='urn:xmpp:jingle:1' action='{action}' sid='{SID}'"
            f" initiator='{FOCUS}'>{contents_xml}</jingle></iq>")


def sim_group(ssrcs):
    inner = "".join(f"<source ssrc='{s}'/>" for s in ssrcs)
    return f"<ssrc-group semantics='SIM' xmlns='urn:xmpp:jingle:apps:rtp:ssma:0'>{inner}</ssrc-group>"


frames = []


def add(direction, payload):
    frames.append({"direction": direction, "timestamp": round(len(frames) * 0.5, 2), "payload": payload})


# 1. Endpoint A joins with audio + simulcast video (3 layers).
a_audio = content("audio", "audio", source(1001, "a1b2c3d4", "a1b2c3d4-a0", "a1b2c3d4-audio-0 a1b2c3d4-audio-0-1"))
a_video = content(
    "video", "video",
    source(2001, "a1b2c3d4", "a1b2c3d4-v0", "a1b2c3d4-video-0 a1b2c3d4-video-0-1")
    + source(2002, "a1b2c3d4", "a1b2c3d4-v1")
    + source(2003, "a1b2c3d4", "a1b2c3d4-v2"),
    sim_group([2001, 2002, 2003]),
)
add("in", jingle("source-add", a_audio + a_video, "sa-a"))

# 2. Endpoint B joins with audio + single video.
b_audio = content("audio", "audio", source(1003, "e5f6a7b8", "e5f6a7b8-a0", "e5f6a7b8-audio-0 e5f6a7b8-audio-0-1"))
b_video = content("video", "video", source(3001, "e5f6a7b8", "e5f6a7b8-v0", "e5f6a7b8-video-0 e5f6a7b8-video-0-1"))
add("in", jingle("source-add", b_audio + b_video, "sa-b"))

# 3. Dominant speaker changes to endpoint B. (Modern deployments send this over
#    the WebRTC data channel; some send it over XMPP as a json-message. This
#    synthetic frame exercises the XMPP path.)
ds_json = ('{"colibriClass":"DominantSpeakerEndpointChangeEvent",'
           '"dominantSpeakerEndpoint":"e5f6a7b8"}')
add("in", f"<message from='{ROOM}/focus' to='{US}'>"
          f"<json-message xmlns='http://jitsi.org/jitmeet'>{ds_json}</json-message></message>")

# 4. Endpoint A turns their camera off — video sources removed (audio stays).
a_video_remove = content(
    "video", "video",
    source(2001, "a1b2c3d4") + source(2002, "a1b2c3d4") + source(2003, "a1b2c3d4"))
add("in", jingle("source-remove", a_video_remove, "sr-a"))

with open("/home/user/jitsi-meet-swift/docs/fixtures/multiparty-sources.json", "w") as f:
    json.dump(frames, f, indent=2)
print(f"wrote {len(frames)} frames")
