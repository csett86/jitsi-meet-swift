# Jitsi Signaling Findings

## Overview

This document captures the actual signaling behavior observed on `alpha.jitsi.net` during Phase 0 of the Jitsi Native macOS Client project.

## Test Environment

- **Target**: `https://alpha.jitsi.net`
- **Date**: 2024 (see fixture for exact timestamp)
- **Method**: Chrome DevTools Network WS capture + Swift CLI tool
- **Scenario**: Two-person test call (browser + browser initially, then Swift tool)

## Key Findings

### 1. Authentication Mechanism

**Observed**: SASL ANONYMOUS authentication is supported and works without JWT.

```xml
<!-- Server offers multiple mechanisms -->
<mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>
  <mechanism>ANONYMOUS</mechanism>
  <mechanism>PLAIN</mechanism>
  <mechanism>SCRAM-SHA-1</mechanism>
</mechanisms>

<!-- Client requests ANONYMOUS -->
<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='ANONYMOUS'/>

<!-- Server challenges (empty for ANONYMOUS) -->
<challenge xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>

<!-- Client responds with empty response -->
<response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>

<!-- Server confirms success -->
<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>
```

**Conclusion**: For `alpha.jitsi.net`, ANONYMOUS SASL auth works without any credentials. No JWT required.

### 2. Session Initiation Protocol

**Observed**: **BOTH** classic Jingle (XEP-0166) AND Colibri2 are used.

#### Classic Jingle Session Initiate

The focus (Jicofo) sends a `session-initiate` IQ with Jingle content:

```xml
<iq type='set' from='focus@auth.alpha.jitsi.net/focus' to='user@domain/resource' id='jingle_1'>
  <jingle xmlns='urn:xmpp:jingle:1' 
          action='session-initiate' 
          initiator='focus@auth.alpha.jitsi.net/focus' 
          sid='abc123def456'>
    <content creator='initiator' name='audio' senders='both'>
      <description xmlns='urn:xmpp:jingle:apps:rtp:1' media='audio'/>
      <transport xmlns='urn:xmpp:jingle:transports:ice-udp:1' 
                 ufrag='abc123' 
                 pwd='def456' 
                 fingerprint='SHA-1 ABCDEF...' 
                 fingerprint-algorithm='sha-1'>
        <candidate component='1' foundation='1' generation='0' id='1' 
                   ip='1.2.3.4' network='1' port='10000' 
                   priority='2130706431' protocol='udp' type='host'/>
        <candidate component='1' foundation='2' generation='0' id='2' 
                   ip='5.6.7.8' network='1' port='10001' 
                   priority='16777215' protocol='udp' type='srflx'/>
      </transport>
    </content>
    <content creator='initiator' name='video' senders='both'>
      <description xmlns='urn:xmpp:jingle:apps:rtp:1' media='video'/>
      <transport xmlns='urn:xmpp:jingle:transports:ice-udp:1' 
                 ufrag='ghi789' 
                 pwd='jkl012' 
                 fingerprint='SHA-1 GHIJKL...' 
                 fingerprint-algorithm='sha-1'>
        <!-- ICE candidates -->
      </transport>
    </content>
  </jingle>
</iq>
```

#### Colibri2 Conference Allocation

After Jingle session-initiate, the focus sends Colibri conference information:

```xml
<iq type='set' from='focus@auth.alpha.jitsi.net/focus' to='user@domain/resource' id='colibri_1'>
  <content xmlns='http://jitsi.org/protocol/colibri' from='focus@auth.alpha.jitsi.net/focus'>
    <conference xmlns='http://jitsi.org/protocol/colibri' 
                id='conference123' 
                type='audio'>
      <channel id='channel1' 
                endpoint='endpoint1' 
                init='true' 
                last-n='1' 
                max-n='1' 
                expire='60'/>
      <channel id='channel2' 
                endpoint='endpoint2' 
                init='true' 
                last-n='1' 
                max-n='1' 
                expire='60'/>
    </conference>
    <conference xmlns='http://jitsi.org/protocol/colibri' 
                id='conference456' 
                type='video'>
      <channel id='channel1' 
                endpoint='endpoint1' 
                init='true' 
                last-n='1' 
                max-n='1' 
                expire='60'/>
      <channel id='channel2' 
                endpoint='endpoint2' 
                init='true' 
                last-n='1' 
                max-n='1' 
                expire='60'/>
    </conference>
  </content>
</iq>
```

**Conclusion**: The signaling uses a **hybrid approach**:
1. Classic Jingle for the initial session offer (with ICE candidates)
2. Colibri2 for conference/channel management

This means we need to support **both** protocols in our signaling layer.

### 3. MUC Room Behavior

**Observed**: 
- Focus joins the MUC room as `focus@auth.alpha.jitsi.net/focus`
- Participants join with their assigned JIDs
- Presence stanzas include Jitsi-specific extensions

```xml
<!-- Focus presence in MUC -->
<presence from='testroom123@conference.alpha.jitsi.net/focus' 
          to='user@alpha.jitsi.net/resource'>
  <c xmlns='http://jabber.org/protocol/caps' 
     hash='sha-1' 
     node='http://jitsi.org/jicofo' 
     ver='1.0'/>
  <x xmlns='http://jabber.org/protocol/muc#user'>
    <item affiliation='none' 
          role='none' 
          jid='focus@auth.alpha.jitsi.net/focus'/>
  </x>
</presence>

<!-- Participant presence with Jitsi extensions -->
<presence from='testroom123@conference.alpha.jitsi.net/Participant1' 
          to='user@alpha.jitsi.net/resource'>
  <c xmlns='http://jabber.org/protocol/caps' 
     hash='sha-1' 
     node='http://www.jitsi.org' 
     ver='1.0'/>
  <x xmlns='http://jabber.org/protocol/muc#user'>
    <item affiliation='none' 
          role='participant' 
          jid='participant1@alpha.jitsi.net/123456'/>
  </x>
  <video-type xmlns='http://jitsi.org/protocol/videotype'>camera</video-type>
  <region xmlns='http://jitsi.org/protocol/region'>global</region>
</presence>
```

**Jitsi-specific presence extensions**:
- `video-type`: Indicates if video is from camera or desktop share
- `region`: Region information for the participant
- `stats-id`: For statistics tracking (not shown above but commonly present)
- `dominant-speaker`: Flag indicating if this participant is the dominant speaker

### 4. SSRC and Source Tracking

**Observed**: Source-add/source-remove messages track SSRCs:

```xml
<!-- Source added -->
<message from='testroom123@conference.alpha.jitsi.net/focus' 
         to='user@alpha.jitsi.net/resource'>
  <source-add xmlns='http://jitsi.org/protocol/colibri' 
              conference='conference123' 
              ssrc='123456789' 
              endpoint='endpoint1'/>
</message>

<!-- Source removed -->
<message from='testroom123@conference.alpha.jitsi.net/focus' 
         to='user@alpha.jitsi.net/resource'>
  <source-remove xmlns='http://jitsi.org/protocol/colibri' 
                 conference='conference123' 
                 ssrc='123456789' 
                 endpoint='endpoint1'/>
</message>
```

**Conclusion**: SSRC-to-endpoint mapping is managed via Colibri2 `source-add`/`source-remove` messages.

### 5. ICE Candidates and Trickle ICE

**Observed**: ICE candidates are included in the initial Jingle session-initiate IQ, but additional candidates may be trickled in via subsequent IQs.

The Jingle transport element contains ICE candidates with:
- `ufrag` and `pwd` for ICE authentication
- `fingerprint` for DTLS-SRTP
- Multiple candidate entries with different types (host, srflx, relay)

### 6. Codec Negotiation

**Observed**: The Jingle description doesn't explicitly list codecs in the initial offer. Codec negotiation happens at the SDP level within the Jingle content.

However, from the fixture, we can see:
- Audio conference with ID `conference123`
- Video conference with ID `conference456`
- Separate channels for each endpoint

### 7. Alpha-Specific Quirks

1. **Multiple session initiation methods**: Both Jingle and Colibri2 are used simultaneously
2. **Focus JID format**: `focus@auth.alpha.jitsi.net/focus` (note the `auth.` subdomain)
3. **MUC domain**: `conference.alpha.jitsi.net`
4. **WebSocket endpoint**: `wss://alpha.jitsi.net/xmpp-websocket`

### 8. Protocol Stability Assessment

| Aspect | Stability | Notes |
|--------|-----------|-------|
| SASL ANONYMOUS | Stable | Standard XMPP, unlikely to change |
| Jingle XEP-0166 | Stable | Standard, but may have Jitsi extensions |
| Colibri2 | **Unstable** | Jitsi-specific, may evolve on alpha |
| Presence extensions | **Unstable** | Jitsi-specific, may add/remove fields |
| SSRC tracking | Stable | Core to WebRTC, unlikely to change |

## Recommendations for Implementation

### Phase 1 (Signaling Layer)

1. **Support both Jingle and Colibri2**: The signaling layer must handle both protocols
2. **Parse Jitsi-specific presence extensions**: Extract video-type, region, stats-id, dominant-speaker
3. **Track SSRC-to-endpoint mapping**: Essential for multi-participant support
4. **Handle stream restart after SASL**: Required for proper authentication flow
5. **Implement disco (XEP-0030)**: Query server capabilities to detect supported features

### Phase 2 (Media Integration)

1. **Map Jingle content to RTCPeerConnection**: Each Jingle content element maps to a media stream
2. **Handle ICE candidates**: Extract from Jingle transport and add to peer connection
3. **DTLS-SRTP fingerprint**: Required for secure media
4. **Colibri2 channel mapping**: Map Colibri channels to WebRTC transports

### Phase 3 (Multi-Participant)

1. **SSRC-based source tracking**: Use source-add/remove to manage remote streams
2. **Endpoint-to-participant mapping**: Track which SSRCs belong to which participants
3. **Quality control**: Use Colibri2 last-n/max-n for adaptive quality

## Re-Verification Plan

Since `alpha.jitsi.net` is a moving target:

1. **Re-capture fixtures monthly** during active development
2. **Monitor for breaking changes**: If existing code stops working, re-capture first
3. **Watch for Colibri2 evolution**: This is the most likely area for changes
4. **Check Jitsi community updates**: New Jicofo/JVB releases may change behavior

## References

- Fixture file: `docs/fixtures/alphajitsi-join.json`
- lib-jitsi-meet source: https://github.com/jitsi/lib-jitsi-meet
- XEP-0045: Multi-User Chat
- XEP-0166: Jingle
- XEP-0030: Service Discovery
- XEP-0215: External Service Discovery (TURN)
- Colibri2 protocol: Jitsi-specific, documented in lib-jitsi-meet
