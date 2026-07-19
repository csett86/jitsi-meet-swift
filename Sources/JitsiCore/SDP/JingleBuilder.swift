import Foundation

/// Builds the Jingle we send back to Jicofo (`session-accept`, `transport-info`)
/// from the offer plus our local SDP answer. Pure XML string building — no
/// WebRTC types — so it is unit-tested offline. The media layer wires the
/// output into the signaling transport.
public enum JingleBuilder {

    /// A `session-accept` that echoes the offered media (payloads, header
    /// extensions, rtcp-mux) and carries our local ICE transport, DTLS
    /// fingerprint, and sending SSRCs from the SDP answer.
    ///
    /// `to` is the XMPP address we send the reply IQ to — the focus's **MUC
    /// occupant** JID (`room@conference.…/focus`, i.e. the `from` of the
    /// `session-initiate`). This is deliberately distinct from the Jingle
    /// `initiator` attribute (`focus@auth.…/focus`): Jicofo routes Jingle over
    /// the room, so addressing the reply to the bare auth JID is not delivered.
    public static func sessionAccept(sid: String, to: String, id: String,
                                     initiator: String, responder: String,
                                     offer: ParsedSessionDescription, local: LocalSDP) -> String {
        let localByKind = Dictionary(uniqueKeysWithValues: local.media.map { ($0.kind, $0) })
        var xml = "<iq type='set' to='\(to)' id='\(id)' xmlns='jabber:client'>"
        xml += "<jingle xmlns='urn:xmpp:jingle:1' action='session-accept' sid='\(sid)'"
        xml += " initiator='\(initiator)' responder='\(responder)'>"
        for media in offer.media {
            xml += content(media: media, local: localByKind[media.kind])
        }
        xml += "</jingle></iq>"
        return xml
    }

    /// A `transport-info` carrying trickle ICE candidates for one media section.
    /// `to` is the focus occupant JID — see ``sessionAccept(sid:to:id:initiator:responder:offer:local:)``.
    public static func transportInfo(sid: String, to: String, id: String,
                                     initiator: String, responder: String,
                                     mediaName: String, ufrag: String?, pwd: String?,
                                     candidates: [ICECandidate]) -> String {
        var xml = "<iq type='set' to='\(to)' id='\(id)' xmlns='jabber:client'>"
        xml += "<jingle xmlns='urn:xmpp:jingle:1' action='transport-info' sid='\(sid)'"
        xml += " initiator='\(initiator)' responder='\(responder)'>"
        xml += "<content creator='responder' name='\(mediaName)'>"
        xml += transport(ufrag: ufrag, pwd: pwd, fingerprint: nil, candidates: candidates)
        xml += "</content></jingle></iq>"
        return xml
    }

    // MARK: - Content

    private static func content(media: MediaDescription, local: LocalSDPMedia?) -> String {
        var xml = "<content creator='responder' name='\(media.kind)' senders='both'>"
        xml += "<description xmlns='urn:xmpp:jingle:apps:rtp:1' media='\(media.kind)'>"
        for payload in media.payloadTypes {
            xml += payloadType(payload)
        }
        for ext in media.headerExtensions {
            xml += "<rtp-hdrext xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0' id='\(ext.id)' uri='\(ext.uri)'/>"
        }
        if media.rtcpMux { xml += "<rtcp-mux/>" }
        for source in local?.sources ?? [] {
            xml += "<source ssrc='\(source.ssrc)' xmlns='urn:xmpp:jingle:apps:rtp:ssma:0'>"
            if let cname = source.cname {
                xml += "<parameter name='cname' value='\(cname)'/>"
            }
            if let msid = source.msid {
                xml += "<parameter name='msid' value='\(escape(msid))'/>"
            }
            xml += "</source>"
        }
        xml += "</description>"
        xml += transport(ufrag: local?.ufrag, pwd: local?.pwd,
                         fingerprint: local?.fingerprint, candidates: local?.candidates ?? [])
        xml += "</content>"
        return xml
    }

    private static func payloadType(_ payload: PayloadType) -> String {
        var xml = "<payload-type id='\(payload.id)'"
        if let name = payload.name { xml += " name='\(name)'" }
        if let clock = payload.clockrate { xml += " clockrate='\(clock)'" }
        if let channels = payload.channels { xml += " channels='\(channels)'" }
        xml += ">"
        for (key, value) in payload.parameters.sorted(by: { $0.key < $1.key }) {
            xml += "<parameter name='\(key)' value='\(escape(value))'/>"
        }
        for fb in payload.rtcpFeedback {
            xml += "<rtcp-fb xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0' type='\(fb.type)'"
            if let subtype = fb.subtype { xml += " subtype='\(subtype)'" }
            xml += "/>"
        }
        xml += "</payload-type>"
        return xml
    }

    private static func transport(ufrag: String?, pwd: String?,
                                  fingerprint: DTLSFingerprint?, candidates: [ICECandidate]) -> String {
        var xml = "<transport xmlns='urn:xmpp:jingle:transports:ice-udp:1'"
        if let ufrag { xml += " ufrag='\(ufrag)'" }
        if let pwd { xml += " pwd='\(pwd)'" }
        xml += ">"
        if let fp = fingerprint {
            xml += "<fingerprint xmlns='urn:xmpp:jingle:apps:dtls:0' hash='\(fp.hash)'"
            if let setup = fp.setup { xml += " setup='\(setup)'" }
            xml += ">\(fp.value)</fingerprint>"
        }
        for c in candidates {
            xml += candidateElement(c)
        }
        xml += "</transport>"
        return xml
    }

    private static func candidateElement(_ c: ICECandidate) -> String {
        var xml = "<candidate"
        if let f = c.foundation { xml += " foundation='\(f)'" }
        if let comp = c.component { xml += " component='\(comp)'" }
        if let proto = c.proto { xml += " protocol='\(proto)'" }
        if let prio = c.priority { xml += " priority='\(prio)'" }
        if let ip = c.ip { xml += " ip='\(ip)'" }
        if let port = c.port { xml += " port='\(port)'" }
        if let type = c.type { xml += " type='\(type)'" }
        xml += " generation='0'/>"
        return xml
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
