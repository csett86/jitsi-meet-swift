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

    /// ICE/DTLS state gathered for one scope (session level, or one m-section).
    private struct TransportAttributes {
        var ufrag: String?
        var pwd: String?
        var fingerprintHash: String?
        var fingerprintValue: String?
        var setup: String?
    }

    public static func parse(_ sdp: String) -> LocalSDP {
        // Session-level ICE/DTLS can apply to all media (bundle); keep it as the
        // fallback for anything an m-section does not restate.
        var session = TransportAttributes()
        var section = TransportAttributes()
        var media: [LocalSDPMedia] = []
        var current: LocalSDPMedia?
        // SSRCs in first-seen order; a real answer has only a handful per section.
        var sources: [LocalSSRC] = []

        /// Attributes before the first `m=` belong to the session, not a section.
        func set(_ key: WritableKeyPath<TransportAttributes, String?>, _ value: String) {
            if current == nil { session[keyPath: key] = value } else { section[keyPath: key] = value }
        }

        func flush() {
            guard var m = current else { return }
            m.ufrag = section.ufrag ?? session.ufrag
            m.pwd = section.pwd ?? session.pwd
            if let hash = section.fingerprintHash ?? session.fingerprintHash,
               let value = section.fingerprintValue ?? session.fingerprintValue {
                m.fingerprint = DTLSFingerprint(hash: hash,
                                                setup: section.setup ?? session.setup,
                                                value: value)
            }
            m.sources = sources
            media.append(m)
            current = nil
            section = TransportAttributes()
            sources = []
        }

        // Normalize CRLF first: in Swift "\r\n" is a single Character (grapheme),
        // so splitting on '\n'/'\r' directly would never match it.
        let normalized = sdp
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            // Every SDP line is `<type>=<body>`; attributes are `a=<name>[:<value>]`.
            let (type, body) = split(line, on: "=")
            switch type {
            case "m":
                flush()
                current = parseMediaHeader(body)
            case "a":
                let (name, value) = split(body, on: ":")
                switch name {
                case "ice-ufrag": set(\.ufrag, value)
                case "ice-pwd": set(\.pwd, value)
                case "setup": set(\.setup, value)
                case "fingerprint":
                    let parts = value.split(separator: " ")
                    if parts.count == 2 {
                        set(\.fingerprintHash, String(parts[0]))
                        set(\.fingerprintValue, String(parts[1]))
                    }
                case "candidate":
                    if let candidate = SDPCandidate.parse(value) { current?.candidates.append(candidate) }
                case "ssrc":
                    parseSSRC(value, into: &sources)
                default: break
                }
            default: break
            }
        }
        flush()
        return LocalSDP(media: media)
    }

    private static func parseMediaHeader(_ body: String) -> LocalSDPMedia {
        // m=<kind> <port> <proto> <pt> <pt> ...
        let tokens = body.split(separator: " ")
        let kind = tokens.first.map(String.init) ?? ""
        return LocalSDPMedia(mid: kind, kind: kind,
                             payloadIDs: tokens.dropFirst(3).compactMap { Int($0) },
                             ufrag: nil, pwd: nil, fingerprint: nil,
                             candidates: [], sources: [])
    }

    private static func parseSSRC(_ value: String, into sources: inout [LocalSSRC]) {
        // "<ssrc> cname:foo"  or  "<ssrc> msid:stream track"
        let (ssrc, attribute) = split(value, on: " ")
        guard !attribute.isEmpty else { return }
        let index: Int
        if let existing = sources.firstIndex(where: { $0.ssrc == ssrc }) {
            index = existing
        } else {
            sources.append(LocalSSRC(ssrc: ssrc))
            index = sources.count - 1
        }
        let (name, detail) = split(attribute, on: ":")
        switch name {
        case "cname": sources[index].cname = detail
        case "msid": sources[index].msid = detail
        default: break
        }
    }

    /// Split at the first occurrence of `separator`; the tail is empty when the
    /// separator is absent. Both halves are whitespace-trimmed.
    private static func split(_ line: some StringProtocol, on separator: Character) -> (String, String) {
        guard let index = line.firstIndex(of: separator) else {
            return (line.trimmingCharacters(in: .whitespaces), "")
        }
        return (line[..<index].trimmingCharacters(in: .whitespaces),
                line[line.index(after: index)...].trimmingCharacters(in: .whitespaces))
    }
}
