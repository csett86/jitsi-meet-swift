import Foundation

/// Builds a Unified-Plan SDP offer from a ``ParsedSessionDescription`` (i.e. from
/// the JVB's classic-Jingle `session-initiate`). Pure string logic with no
/// WebRTC types, so it is unit-tested offline; the Apple layer wraps the result
/// in an `RTCSessionDescription(type: .offer, sdp:)`.
///
/// This is flagged as the riskiest integration point (see docs/mac-runbook.md):
/// the structure is asserted here, but only a real `RTCPeerConnection` on macOS
/// can confirm WebRTC accepts it. Kept deterministic for testability.
public enum SDPBuilder {

    /// One extra m-section that exists only to *receive* a remote participant's
    /// track. The JVB never re-offers per participant — it announces sources with
    /// `source-add` — so the client synthesizes the m-section itself and
    /// renegotiates locally. A section whose `track` is nil is a tombstone for a
    /// source that went away: it stays (mids may never be renumbered) but is
    /// `a=inactive` and carries no SSRCs.
    public struct ReceiveMedia: Equatable, Sendable {
        public var mid: String
        public var kind: String              // audio / video
        public var track: RemoteTrack?

        public init(mid: String, kind: String, track: RemoteTrack?) {
            self.mid = mid; self.kind = kind; self.track = track
        }
    }

    /// Optionally override which codec we *send* with. WebRTC encodes with the
    /// first payload type of the m-section, so this just moves one to the front.
    ///
    /// Leave it `nil` — the default — to keep the JVB's own order. The
    /// `session-initiate` payload-type order **is** the deployment's announced
    /// codec preference (`videoQuality.codecPreferenceOrder`, AV1 first on
    /// jitsi.luki.org), and following it is what makes us behave like every other
    /// client there. The parameter exists for pinning a codec while debugging
    /// interop, not as a policy.
    public static func offer(from description: ParsedSessionDescription,
                             sessionID: String = "0",
                             version: Int = 2,
                             receive: [ReceiveMedia] = [],
                             sendVideoCodec: String? = nil) -> String {
        var lines: [String] = []
        lines.append("v=0")
        lines.append("o=- \(sessionID) \(version) IN IP4 127.0.0.1")
        lines.append("s=-")
        lines.append("t=0 0")
        let mids = description.media.map(\.kind) + receive.map(\.mid)
        lines.append("a=group:BUNDLE \(mids.joined(separator: " "))")
        lines.append("a=msid-semantic: WMS *")

        for media in description.media {
            lines.append(contentsOf: mediaLines(prefer(sendVideoCodec, in: media)))
        }
        for section in receive {
            // The template (payload types, header extensions, transport) is the
            // offered section of the same kind — the bridge bundles everything
            // onto one transport, so it is identical for every participant.
            guard let template = description.media.first(where: { $0.kind == section.kind })
            else { continue }
            lines.append(contentsOf: receiveLines(section, template: template))
        }
        // SDP uses CRLF line endings and a trailing CRLF.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Move `codec`'s payload type to the front of a video section, leaving the
    /// rest of the list (and audio) untouched — and leaving the JVB's announced
    /// order alone when no override is given. Nothing is ever dropped: this only
    /// changes which codec we encode with, never what we can decode.
    private static func prefer(_ codec: String?, in media: MediaDescription) -> MediaDescription {
        guard let codec, media.kind == "video" else { return media }
        let matches = { (payload: PayloadType) in
            payload.name?.caseInsensitiveCompare(codec) == .orderedSame
        }
        guard media.payloadTypes.contains(where: matches) else { return media }
        var reordered = media
        reordered.payloadTypes = media.payloadTypes.filter(matches)
            + media.payloadTypes.filter { !matches($0) }
        return reordered
    }

    /// A receive-only m-section for one remote track. `sendonly` is from the
    /// *offerer's* (the bridge's) point of view, so our answer comes out
    /// `recvonly` and WebRTC creates a receiver — which is what surfaces the
    /// remote track.
    private static func receiveLines(_ section: ReceiveMedia,
                                     template: MediaDescription) -> [String] {
        var lines: [String] = []
        let payloadIDs = template.payloadTypes.map { String($0.id) }.joined(separator: " ")
        lines.append("m=\(section.kind) 9 UDP/TLS/RTP/SAVPF \(payloadIDs)")
        lines.append("c=IN IP4 0.0.0.0")
        lines.append("a=rtcp:9 IN IP4 0.0.0.0")
        if let transport = template.transport {
            // Candidates are omitted: everything is bundled onto the transport of
            // the first m-line, so repeating them per section only bloats the SDP.
            lines.append(contentsOf: transportLines(transport, includeCandidates: false))
        }
        lines.append("a=mid:\(section.mid)")
        lines.append(section.track == nil ? "a=inactive" : "a=sendonly")
        if template.rtcpMux { lines.append("a=rtcp-mux") }
        for payload in template.payloadTypes {
            lines.append(contentsOf: payloadLines(payload))
        }
        for ext in template.headerExtensions {
            lines.append("a=extmap:\(ext.id) \(ext.uri)")
        }
        guard let track = section.track else { return lines }

        let msid = track.msid ?? "\(track.endpointID)-\(track.kind) \(track.primarySSRC)"
        lines.append("a=msid:\(msid)")
        // Simulcast layers / RTX belong to one track: group them so WebRTC treats
        // the section as a single track rather than rejecting it.
        if track.ssrcs.count > 1 {
            let semantics = track.kind == "video" ? "SIM" : "FID"
            lines.append("a=ssrc-group:\(semantics) \(track.ssrcs.joined(separator: " "))")
        }
        for ssrc in track.ssrcs {
            lines.append("a=ssrc:\(ssrc) cname:\(track.name ?? track.endpointID)")
            lines.append("a=ssrc:\(ssrc) msid:\(msid)")
        }
        return lines
    }

    private static func mediaLines(_ media: MediaDescription) -> [String] {
        var lines: [String] = []
        let payloadIDs = media.payloadTypes.map { String($0.id) }.joined(separator: " ")
        lines.append("m=\(media.kind) 9 UDP/TLS/RTP/SAVPF \(payloadIDs)")
        lines.append("c=IN IP4 0.0.0.0")
        lines.append("a=rtcp:9 IN IP4 0.0.0.0")

        if let transport = media.transport {
            lines.append(contentsOf: transportLines(transport))
        }

        lines.append("a=mid:\(media.kind)")
        lines.append("a=sendrecv")
        if media.rtcpMux { lines.append("a=rtcp-mux") }

        for payload in media.payloadTypes {
            lines.append(contentsOf: payloadLines(payload))
        }
        for ext in media.headerExtensions {
            lines.append("a=extmap:\(ext.id) \(ext.uri)")
        }
        // Unified Plan permits only one track (one set of a=ssrc lines) per
        // m-section, and the JVB's session-initiate can carry several sources per
        // section — its own placeholder plus every participant already publishing.
        // Only the bridge's own source stays here (it never actually sends);
        // every participant source gets a dedicated receive section instead, so
        // no SSRC is ever declared twice.
        if let source = media.sources.first(where: { $0.owner == "jvb" }) ?? media.sources.first(where: {
            $0.owner == nil && $0.name?.hasPrefix("jvb-") == true
        }) {
            lines.append(contentsOf: sourceLines(source))
        }
        return lines
    }

    private static func transportLines(_ transport: JingleTransport,
                                       includeCandidates: Bool = true) -> [String] {
        var lines: [String] = []
        if let ufrag = transport.ufrag { lines.append("a=ice-ufrag:\(ufrag)") }
        if let pwd = transport.pwd { lines.append("a=ice-pwd:\(pwd)") }
        if let fp = transport.fingerprint {
            lines.append("a=fingerprint:\(fp.hash) \(fp.value)")
            lines.append("a=setup:\(fp.setup ?? "actpass")")
        }
        if includeCandidates {
            lines.append(contentsOf: transport.candidates.map { "a=\(SDPCandidate.line(from: $0))" })
        }
        return lines
    }

    private static func payloadLines(_ payload: PayloadType) -> [String] {
        var lines: [String] = []
        var rtpmap = "a=rtpmap:\(payload.id) \(payload.name ?? "")/\(payload.clockrate ?? 90000)"
        if let channels = payload.channels, channels > 1 { rtpmap += "/\(channels)" }
        lines.append(rtpmap)

        if !payload.parameters.isEmpty {
            // Sorted for deterministic output.
            let fmtp = payload.parameters.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ";")
            lines.append("a=fmtp:\(payload.id) \(fmtp)")
        }
        for fb in payload.rtcpFeedback {
            if let subtype = fb.subtype {
                lines.append("a=rtcp-fb:\(payload.id) \(fb.type) \(subtype)")
            } else {
                lines.append("a=rtcp-fb:\(payload.id) \(fb.type)")
            }
        }
        return lines
    }

    private static func sourceLines(_ source: Source) -> [String] {
        var lines: [String] = []
        let cname = source.name ?? "jitsi"
        lines.append("a=ssrc:\(source.ssrc) cname:\(cname)")
        if let msid = source.parameters["msid"] {
            lines.append("a=ssrc:\(source.ssrc) msid:\(msid)")
        }
        return lines
    }
}
