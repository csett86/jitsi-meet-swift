import Foundation

/// A `StanzaTransport` that replays committed fixture frames instead of touching
/// the network. Emits the recorded inbound frames (server → client) in order and
/// records everything the conference sends, so the full join → focus-invite →
/// session-description flow is driven and asserted **offline** ([CLOUD]).
public actor FakeTransport: StanzaTransport {
    private let inboundFrames: [String]
    private var sentStanzas: [String] = []

    private let incomingStream: AsyncStream<Data>
    private let incomingContinuation: AsyncStream<Data>.Continuation
    private let stateStream: AsyncStream<ConnectionState>
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    public var incoming: AsyncStream<Data> { incomingStream }
    public var state: AsyncStream<ConnectionState> { stateStream }

    /// - Parameter inboundFrames: the server → client payloads to replay, in order.
    public init(inboundFrames: [String]) {
        self.inboundFrames = inboundFrames
        (incomingStream, incomingContinuation) = AsyncStream.makeStream(of: Data.self)
        (stateStream, stateContinuation) = AsyncStream.makeStream(of: ConnectionState.self)
    }

    public func connect() async throws {
        stateContinuation.yield(.connecting)
        stateContinuation.yield(.connected)
        // AsyncStream buffers unbounded, so a consumer that starts iterating
        // after this returns still receives every frame in order.
        for frame in inboundFrames {
            incomingContinuation.yield(Data(frame.utf8))
        }
        incomingContinuation.finish()
    }

    public func send(_ stanza: String) async throws {
        sentStanzas.append(stanza)
    }

    public func disconnect() async {
        stateContinuation.yield(.disconnected)
        stateContinuation.finish()
    }

    /// Everything the conference sent, in order — for test assertions.
    public func sent() -> [String] { sentStanzas }
}
