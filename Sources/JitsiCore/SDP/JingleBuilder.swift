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
        let localByKind = Dictionary(local.media.map { ($0.kind, $0) },
                                     uniquingKeysWith: { first, _ in first })
        return iq(action: "session-accept", sid: sid, to: to, id: id,
                  initiator: initiator, responder: responder,
                  contents: offer.media.map { content(media: $0, local: localByKind[$0.kind]) }.joined())
    }

    /// A `transport-info` carrying trickle ICE candidates for one media section.
    /// `to` is the focus occupant JID — see ``sessionAccept(sid:to:id:initiator:responder:offer:local:)``.
    public static func transportInfo(sid: String, to: String, id: String,
                                     initiator: String, responder: String,
                                     mediaName: String, ufrag: String?, pwd: String?,
                                     candidates: [ICECandidate]) -> String {
        iq(action: "transport-info", sid: sid, to: to, id: id,
           initiator: initiator, responder: responder,
           contents: "<content creator='responder'" + attr("name", mediaName) + ">"
               + transport(ufrag: ufrag, pwd: pwd, fingerprint: nil, candidates: candidates)
               + "</content>")
    }

    // MARK: - Elements

    /// The `<iq><jingle …>` envelope every action we send shares.
    private static func iq(action: String, sid: String, to: String, id: String,
                           initiator: String, responder: String, contents: String) -> String {
        "<iq type='set'" + attr("to", to) + attr("id", id) + " xmlns='jabber:client'>"
            + "<jingle xmlns='urn:xmpp:jingle:1'" + attr("action", action) + attr("sid", sid)
            + attr("initiator", initiator) + attr("responder", responder) + ">"
            + contents + "</jingle></iq>"
    }

    private static func content(media: MediaDescription, local: LocalSDPMedia?) -> String {
        var xml = "<content creator='responder'" + attr("name", media.kind) + " senders='both'>"
        xml += "<description xmlns='urn:xmpp:jingle:apps:rtp:1'" + attr("media", media.kind) + ">"
        for payload in media.payloadTypes {
            xml += payloadType(payload)
        }
        for ext in media.headerExtensions {
            xml += "<rtp-hdrext xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'"
                + attr("id", ext.id) + attr("uri", ext.uri) + "/>"
        }
        if media.rtcpMux { xml += "<rtcp-mux/>" }
        for source in local?.sources ?? [] {
            xml += "<source" + attr("ssrc", source.ssrc) + " xmlns='urn:xmpp:jingle:apps:rtp:ssma:0'>"
                + parameter("cname", source.cname)
                + parameter("msid", source.msid)
                + "</source>"
        }
        xml += "</description>"
        xml += transport(ufrag: local?.ufrag, pwd: local?.pwd,
                         fingerprint: local?.fingerprint, candidates: local?.candidates ?? [])
        xml += "</content>"
        return xml
    }

    private static func payloadType(_ payload: PayloadType) -> String {
        var xml = "<payload-type" + attr("id", payload.id) + attr("name", payload.name)
            + attr("clockrate", payload.clockrate) + attr("channels", payload.channels) + ">"
        for (name, value) in payload.parameters.sorted(by: { $0.key < $1.key }) {
            xml += parameter(name, value)
        }
        for fb in payload.rtcpFeedback {
            xml += "<rtcp-fb xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'"
                + attr("type", fb.type) + attr("subtype", fb.subtype) + "/>"
        }
        return xml + "</payload-type>"
    }

    private static func transport(ufrag: String?, pwd: String?,
                                  fingerprint: DTLSFingerprint?, candidates: [ICECandidate]) -> String {
        var xml = "<transport xmlns='urn:xmpp:jingle:transports:ice-udp:1'"
            + attr("ufrag", ufrag) + attr("pwd", pwd) + ">"
        if let fp = fingerprint {
            xml += "<fingerprint xmlns='urn:xmpp:jingle:apps:dtls:0'"
                + attr("hash", fp.hash) + attr("setup", fp.setup) + ">\(escape(fp.value))</fingerprint>"
        }
        for candidate in candidates {
            xml += candidateElement(candidate)
        }
        return xml + "</transport>"
    }

    private static func candidateElement(_ c: ICECandidate) -> String {
        "<candidate"
            + attr("foundation", c.foundation) + attr("component", c.component)
            + attr("protocol", c.proto) + attr("priority", c.priority)
            + attr("ip", c.ip) + attr("port", c.port) + attr("type", c.type)
            + " generation='0'/>"
    }

    // MARK: - Escaping

    /// One attribute, omitted entirely when the value is nil.
    private static func attr(_ name: String, _ value: (some CustomStringConvertible)?) -> String {
        guard let value else { return "" }
        return " \(name)='\(escape(value.description))'"
    }

    /// A `<parameter name= value=/>`, omitted entirely when the value is nil.
    private static func parameter(_ name: String, _ value: String?) -> String {
        guard let value else { return "" }
        return "<parameter" + attr("name", name) + attr("value", value) + "/>"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
