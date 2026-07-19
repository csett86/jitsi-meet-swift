import Foundation

/// A wire-format-agnostic description of the media session the bridge offered.
///
/// The signaling core normalizes the server's `session-initiate` into this so
/// the (Apple-only) media layer never sees Jingle or Colibri. `jitsi.luki.org`
/// was confirmed to use classic Jingle (XEP-0166); the Colibri2 path is not
/// needed for it, but this type is the single shape media code consumes either
/// way.
public struct ParsedSessionDescription: Equatable, Sendable {
    public var sid: String
    public var initiator: String?
    public var media: [MediaDescription]
    /// The JVB colibri bridge WebSocket URL, if offered (used for the bridge
    /// data channel / endpoint messages).
    public var bridgeWebSocketURL: String?

    public init(sid: String, initiator: String?, media: [MediaDescription],
                bridgeWebSocketURL: String?) {
        self.sid = sid; self.initiator = initiator
        self.media = media; self.bridgeWebSocketURL = bridgeWebSocketURL
    }

    /// Normalize a Jingle action (a `session-initiate`) into a session description.
    public init(jingle: Jingle) {
        self.sid = jingle.sid
        self.initiator = jingle.initiator
        self.media = jingle.contents.map(MediaDescription.init)
        self.bridgeWebSocketURL = jingle.contents
            .compactMap { $0.transport?.webSocketURL }
            .first
    }

    public var audio: MediaDescription? { media.first { $0.kind == "audio" } }
    public var video: MediaDescription? { media.first { $0.kind == "video" } }
}

/// One media line (audio or video) in a session description.
public struct MediaDescription: Equatable, Sendable {
    public var kind: String          // "audio" / "video"
    public var payloadTypes: [PayloadType]
    public var headerExtensions: [RTPHeaderExtension]
    public var sources: [Source]
    public var sourceGroups: [SourceGroup]
    public var transport: JingleTransport?
    public var rtcpMux: Bool

    public init(kind: String, payloadTypes: [PayloadType],
                headerExtensions: [RTPHeaderExtension], sources: [Source],
                sourceGroups: [SourceGroup], transport: JingleTransport?, rtcpMux: Bool = true) {
        self.kind = kind; self.payloadTypes = payloadTypes
        self.headerExtensions = headerExtensions; self.sources = sources
        self.sourceGroups = sourceGroups; self.transport = transport; self.rtcpMux = rtcpMux
    }

    public init(_ content: JingleContent) {
        self.kind = content.media ?? content.name
        self.payloadTypes = content.payloadTypes
        self.headerExtensions = content.headerExtensions
        self.sources = content.sources
        self.sourceGroups = content.sourceGroups
        self.transport = content.transport
        self.rtcpMux = content.rtcpMux
    }

    public var codecNames: [String] { payloadTypes.compactMap(\.name) }
}
