import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The real signaling socket: XMPP over WebSocket (RFC 7395) via
/// `URLSessionWebSocketTask`.
///
/// [CLOUD-LIVE] on Linux (validates protocol + server behavior) and [MAC] for a
/// final confirmation that Apple's Foundation `URLSession` behaves identically —
/// the two Foundations differ, so the same code path is checked on both.
public actor URLSessionStanzaTransport: StanzaTransport {
    private let url: URL
    private let host: String
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    private let incomingStream: AsyncStream<Data>
    private let incomingContinuation: AsyncStream<Data>.Continuation
    private let stateStream: AsyncStream<ConnectionState>
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    private var receiveLoop: Task<Void, Never>?

    public var incoming: AsyncStream<Data> { incomingStream }
    public var state: AsyncStream<ConnectionState> { stateStream }

    public init(url: URL, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.url = url
        self.host = url.host ?? ""
        self.session = session
        (incomingStream, incomingContinuation) = AsyncStream.makeStream(of: Data.self)
        (stateStream, stateContinuation) = AsyncStream.makeStream(of: ConnectionState.self)
    }

    public func connect() async throws {
        stateContinuation.yield(.connecting)
        var request = URLRequest(url: url)
        // RFC 7395: the WebSocket subprotocol for XMPP framing.
        request.setValue("xmpp", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        stateContinuation.yield(.connected)
        startReceiving(on: task)
    }

    public func send(_ stanza: String) async throws {
        guard let task else { throw TransportError.notConnected }
        try await task.send(.string(stanza))
    }

    public func disconnect() async {
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        stateContinuation.yield(.disconnected)
        stateContinuation.finish()
        incomingContinuation.finish()
    }

    private func startReceiving(on task: URLSessionWebSocketTask) {
        receiveLoop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        await self?.yieldIncoming(Data(text.utf8))
                    case .data(let data):
                        await self?.yieldIncoming(data)
                    @unknown default:
                        break
                    }
                } catch {
                    await self?.failed(error)
                    return
                }
            }
        }
    }

    private func yieldIncoming(_ data: Data) {
        incomingContinuation.yield(data)
    }

    private func failed(_ error: Error) {
        stateContinuation.yield(.failed("\(error)"))
        incomingContinuation.finish()
    }

    public enum TransportError: Error { case notConnected }
}
