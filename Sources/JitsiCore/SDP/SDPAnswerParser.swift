import Foundation

/// One SSRC declared in a local SDP answer.
public struct LocalSSRC: Equatable, Sendable {
    public var ssrc: String
    public var cname: String?
    public var msid: String?
    public init(ssrc: String, cname: String? = nil, msid: String? = nil) {
        self.ssrc = ssrc; self.cname = cname; self.msid = msid
    }
}

/// One media section of a local SDP answer, reduced to what a Jingle
/// `session-accept` / `transport-info` / `source-add` needs.
public struct LocalSDPMedia: Equatable, Sendable {
    public var mid: String
    public var kind: String                 // audio / video
    public var payloadIDs: [Int]
    public var ufrag: String?
    public var pwd: String?
    public var fingerprint: DTLSFingerprint?
    public var candidates: [ICECandidate]
    public var sources: [LocalSSRC]
}

/// A parsed local SDP answer.
public struct LocalSDP: Equatable, Sendable {
    public var media: [LocalSDPMedia]
}

/// Parses a local SDP answer (what `RTCPeerConnection.createAnswer` produces)
/// into a typed structure. Pure string logic, unit-tested offline; the media
/// layer uses it to build the Jingle we send back to Jicofo.
public enum SDPAnswerParser {

    public static func parse(_ sdp: String) -> LocalSDP {
        // Session-level ICE/DTLS can apply to all media (bundle); track as fallback.
        var sessionUfrag: String?
        var sessionPwd: String?
        var sessionFingerprintHash: String?
        var sessionFingerprintValue: String?
        var sessionSetup: String?

        var media: [LocalSDPMedia] = []
        var current: LocalSDPMedia?
        // ssrc -> (cname, msid), preserving first-seen order.
        var ssrcOrder: [String] = []
        var ssrcInfo: [String: LocalSSRC] = [:]
        var fpHash: String?
        var fpValue: String?
        var setup: String?

        func flush() {
            guard var m = current else { return }
            m.ufrag = m.ufrag ?? sessionUfrag
            m.pwd = m.pwd ?? sessionPwd
            let hash = fpHash ?? sessionFingerprintHash
            let value = fpValue ?? sessionFingerprintValue
            if let hash, let value {
                m.fingerprint = DTLSFingerprint(hash: hash, setup: setup ?? sessionSetup, value: value)
            }
            m.sources = ssrcOrder.compactMap { ssrcInfo[$0] }
            media.append(m)
            current = nil
            ssrcOrder = []; ssrcInfo = [:]; fpHash = nil; fpValue = nil; setup = nil
        }

        // Normalize CRLF first: in Swift "\r\n" is a single Character (grapheme),
        // so splitting on '\n'/'\r' directly would never match it.
        let normalized = sdp
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.hasPrefix("m=") {
                flush()
                current = parseMediaHeader(line)
            } else if line.hasPrefix("a=ice-ufrag:") {
                let v = value(line, after: "a=ice-ufrag:")
                if current != nil { current?.ufrag = v } else { sessionUfrag = v }
            } else if line.hasPrefix("a=ice-pwd:") {
                let v = value(line, after: "a=ice-pwd:")
                if current != nil { current?.pwd = v } else { sessionPwd = v }
            } else if line.hasPrefix("a=fingerprint:") {
                let parts = value(line, after: "a=fingerprint:").split(separator: " ")
                if parts.count == 2 {
                    if current != nil { fpHash = String(parts[0]); fpValue = String(parts[1]) }
                    else { sessionFingerprintHash = String(parts[0]); sessionFingerprintValue = String(parts[1]) }
                }
            } else if line.hasPrefix("a=setup:") {
                let v = value(line, after: "a=setup:")
                if current != nil { setup = v } else { sessionSetup = v }
            } else if line.hasPrefix("a=candidate:") {
                if let c = SDPCandidate.parse(line) { current?.candidates.append(c) }
            } else if line.hasPrefix("a=ssrc:") {
                parseSSRC(value(line, after: "a=ssrc:"), order: &ssrcOrder, info: &ssrcInfo)
            }
        }
        flush()
        return LocalSDP(media: media)
    }

    private static func parseMediaHeader(_ line: String) -> LocalSDPMedia {
        // m=<kind> <port> <proto> <pt> <pt> ...
        let tokens = value(line, after: "m=").split(separator: " ").map(String.init)
        let kind = tokens.first ?? ""
        let payloadIDs = tokens.dropFirst(3).compactMap(Int.init)
        return LocalSDPMedia(mid: kind, kind: kind, payloadIDs: Array(payloadIDs),
                             ufrag: nil, pwd: nil, fingerprint: nil,
                             candidates: [], sources: [])
    }

    private static func parseSSRC(_ rest: String, order: inout [String], info: inout [String: LocalSSRC]) {
        // "<ssrc> cname:foo"  or  "<ssrc> msid:stream track"
        guard let space = rest.firstIndex(of: " ") else { return }
        let ssrc = String(rest[..<space])
        let attr = String(rest[rest.index(after: space)...])
        if info[ssrc] == nil { order.append(ssrc); info[ssrc] = LocalSSRC(ssrc: ssrc) }
        if attr.hasPrefix("cname:") {
            info[ssrc]?.cname = String(attr.dropFirst("cname:".count))
        } else if attr.hasPrefix("msid:") {
            info[ssrc]?.msid = String(attr.dropFirst("msid:".count))
        }
    }

    private static func value(_ line: String, after prefix: String) -> String {
        String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
