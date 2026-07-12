import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Connection state

public enum XMPPConnectionState: Sendable {
    case disconnected
    case connecting
    case streamOpening
    case authenticating
    case binding
    case ready
    case error(any Error & Sendable)
}

// MARK: - Connection errors

public enum XMPPConnectionError: Error, Sendable {
    case unexpectedFrame(String)
    case saslFailed(condition: String)
    case bindFailed
    case connectionClosed
    case timeout
    case noAnonymousSupport
}

// MARK: - XMPPWebSocketConnection

/// Low-level XMPP-over-WebSocket connection (RFC 7395).
///
/// Handles the full connection lifecycle:
/// 1. WebSocket connect
/// 2. XMPP stream open / features
/// 3. SASL ANONYMOUS authentication
/// 4. Stream restart
/// 5. Resource bind
///
/// After `connect(to:domain:resource:)` returns, ``fullJID`` is set and the
/// actor is ready to send/receive stanzas. Callers iterate the ``stanzas``
/// stream to receive incoming stanzas.
///
/// Reconnect-with-backoff is left to the caller (``JitsiConference``) so that
/// the reconnect policy stays configurable without coupling it to transport.
public actor XMPPWebSocketConnection {
    // MARK: Public state

    public private(set) var state: XMPPConnectionState = .disconnected
    public private(set) var fullJID: String?
    public private(set) var streamID: String?

    /// Incoming stanzas after successful connection. Finished when disconnected.
    public var stanzas: AsyncStream<ReceivedStanza> {
        get async { _stanzaStream() }
    }

    // MARK: Private

    private var wsTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private var receiveLoopTask: Task<Void, Never>?
    private var iqCounter: Int = 0

    // Stanza stream plumbing
    private var stanzaContinuation: AsyncStream<ReceivedStanza>.Continuation?
    private var _stanzas: AsyncStream<ReceivedStanza>?

    // MARK: - Init

    public init(urlSession: URLSession = URLSession(configuration: .default)) {
        self.urlSession = urlSession
    }

    // MARK: - Connect

    /// Connects to an XMPP server over WebSocket, performs SASL ANONYMOUS,
    /// and binds a resource. Returns when the session is fully ready.
    ///
    /// - Parameters:
    ///   - url: WebSocket URL, e.g. `wss://alpha.jitsi.net/xmpp-websocket`.
    ///   - domain: XMPP domain, e.g. `alpha.jitsi.net`.
    ///   - resource: Resource name to request (default: `"jitsi"`).
    public func connect(to url: URL, domain: String, resource: String = "jitsi") async throws {
        state = .connecting
        let task = urlSession.webSocketTask(with: url, protocols: ["xmpp"])
        wsTask = task
        task.resume()

        // --- Phase 1: Stream open ---
        state = .streamOpening
        try await sendRaw(streamOpenStanza(to: domain))
        let openFrame = try await receiveRaw()
        let openStanza = StanzaParser.parse(openFrame)
        if case .streamOpen(let s) = openStanza { streamID = s.id }

        // --- Phase 2: Stream features ---
        let featuresFrame = try await receiveRaw()
        let featuresStanza = StanzaParser.parse(featuresFrame)
        guard case .streamFeatures(let features) = featuresStanza else {
            throw XMPPConnectionError.unexpectedFrame(featuresFrame)
        }
        guard features.supportsAnonymous else {
            throw XMPPConnectionError.noAnonymousSupport
        }

        // --- Phase 3: SASL ANONYMOUS ---
        state = .authenticating
        try await sendRaw(SASLAuthenticator.authStanza())
        let saslFrame = try await receiveRaw()
        switch StanzaParser.parse(saslFrame) {
        case .saslSuccess:
            break
        case .saslFailure(let condition):
            throw XMPPConnectionError.saslFailed(condition: condition)
        default:
            throw XMPPConnectionError.unexpectedFrame(saslFrame)
        }

        // --- Phase 4: Stream restart ---
        try await sendRaw(streamOpenStanza(to: domain))
        let open2Frame = try await receiveRaw()
        if case .streamOpen(let s) = StanzaParser.parse(open2Frame) { streamID = s.id }
        _ = try await receiveRaw() // consume post-SASL features

        // --- Phase 5: Resource bind ---
        state = .binding
        iqCounter += 1
        let bindID = "bind_\(iqCounter)"
        try await sendRaw(bindIQStanza(id: bindID, resource: resource))
        let bindFrame = try await receiveRaw()
        if case .iq(let iq) = StanzaParser.parse(bindFrame),
           case .bind(let jid) = iq.payload, !jid.isEmpty {
            fullJID = jid
        } else {
            throw XMPPConnectionError.bindFailed
        }

        // --- Ready: start background receive loop ---
        state = .ready
        let (stream, continuation) = AsyncStream<ReceivedStanza>.makeStream()
        _stanzas = stream
        stanzaContinuation = continuation
        receiveLoopTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    // MARK: - Send stanzas

    /// Sends a raw XML string frame. Caller is responsible for well-formed XML.
    public func sendRaw(_ xml: String) async throws {
        guard let task = wsTask else { throw XMPPConnectionError.connectionClosed }
        try await task.send(.string(xml))
    }

    /// Sends an IQ stanza and returns a unique IQ id (for correlation).
    @discardableResult
    public func sendIQ(type: String, to: String?, payload: String) async throws -> String {
        iqCounter += 1
        let iqID = "iq_\(iqCounter)"
        let toAttr = to.map { " to=\"\($0)\"" } ?? ""
        let xml = "<iq xmlns=\"jabber:client\" type=\"\(type)\"\(toAttr) id=\"\(iqID)\">\(payload)</iq>"
        try await sendRaw(xml)
        return iqID
    }

    /// Sends a presence stanza.
    public func sendPresence(to: String, payload: String) async throws {
        let xml = "<presence xmlns=\"jabber:client\" to=\"\(to)\">\(payload)</presence>"
        try await sendRaw(xml)
    }

    // MARK: - Disconnect

    public func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        stanzaContinuation?.finish()
        stanzaContinuation = nil
        state = .disconnected
    }

    // MARK: - Private helpers

    private func _stanzaStream() -> AsyncStream<ReceivedStanza> {
        if let existing = _stanzas { return existing }
        let (stream, continuation) = AsyncStream<ReceivedStanza>.makeStream()
        _stanzas = stream
        stanzaContinuation = continuation
        return stream
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                let frame = try await receiveRaw()
                let stanza = StanzaParser.parse(frame)
                stanzaContinuation?.yield(stanza)
            } catch {
                stanzaContinuation?.finish()
                state = .error(XMPPConnectionError.connectionClosed)
                break
            }
        }
    }

    private func receiveRaw() async throws -> String {
        guard let task = wsTask else { throw XMPPConnectionError.connectionClosed }
        let message = try await task.receive()
        switch message {
        case .string(let s):
            return s
        case .data(let d):
            return String(data: d, encoding: .utf8) ?? ""
        @unknown default:
            throw XMPPConnectionError.unexpectedFrame("(unknown message type)")
        }
    }

    // MARK: - XMPP stanza builders

    private func streamOpenStanza(to domain: String) -> String {
        "<open xmlns=\"\(XMPPNS.framing)\" to=\"\(domain)\" version=\"1.0\"/>"
    }

    private func bindIQStanza(id: String, resource: String) -> String {
        "<iq xmlns=\"jabber:client\" type=\"set\" id=\"\(id)\">" +
        "<bind xmlns=\"\(XMPPNS.bind)\">" +
        "<resource>\(resource)</resource>" +
        "</bind></iq>"
    }
}
