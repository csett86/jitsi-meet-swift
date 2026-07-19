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

    public static func offer(from description: ParsedSessionDescription,
                             sessionID: String = "0") -> String {
        var lines: [String] = []
        lines.append("v=0")
        lines.append("o=- \(sessionID) 2 IN IP4 127.0.0.1")
        lines.append("s=-")
        lines.append("t=0 0")
        let mids = description.media.map(\.kind)
        lines.append("a=group:BUNDLE \(mids.joined(separator: " "))")
        lines.append("a=msid-semantic: WMS *")

        for media in description.media {
            lines.append(contentsOf: mediaLines(media))
        }
        // SDP uses CRLF line endings and a trailing CRLF.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func mediaLines(_ media: MediaDescription) -> [String] {
        var lines: [String] = []
        let payloadIDs = media.payloadTypes.map { String($0.id) }.joined(separator: " ")
        lines.append("m=\(media.kind) 9 UDP/TLS/RTP/SAVPF \(payloadIDs)")
        lines.append("c=IN IP4 0.0.0.0")
        lines.append("a=rtcp:9 IN IP4 0.0.0.0")

        if let transport = media.transport {
            if let ufrag = transport.ufrag { lines.append("a=ice-ufrag:\(ufrag)") }
            if let pwd = transport.pwd { lines.append("a=ice-pwd:\(pwd)") }
            if let fp = transport.fingerprint {
                lines.append("a=fingerprint:\(fp.hash) \(fp.value)")
                lines.append("a=setup:\(fp.setup ?? "actpass")")
            }
            for candidate in transport.candidates {
                lines.append("a=\(SDPCandidate.line(from: candidate))")
            }
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
        // m-section. The JVB's session-initiate can carry several sources per
        // section — its own mixed source plus every other participant's — which
        // WebRTC rejects ("more than one track specified with a=ssrc lines").
        // Collapse to the first source so setRemoteDescription accepts the offer;
        // this is enough to negotiate transport + send our media. Receiving each
        // remote participant as its own m-line (via source-add → new
        // transceivers) is a separate, later step.
        if let source = media.sources.first {
            lines.append(contentsOf: sourceLines(source))
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
