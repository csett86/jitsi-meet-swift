#if os(macOS)
import Foundation
import JitsiCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The JVB "colibri" bridge channel. On jitsi.luki.org this is a WebSocket (the
/// `<web-socket url=…>` in the `session-initiate`), not an SCTP data channel; it
/// carries endpoint messages — receiver video constraints out, dominant-speaker
/// (and other colibri events) in.
///
/// [MAC] — uses `URLSessionWebSocketTask` (wss), which only works on Apple
/// Foundation (Linux swift-corelibs cannot open wss). The message *content*
/// (`ReceiverConstraints.colibriMessageJSON`, `EndpointMessage.dominantSpeaker`)
/// is pure `JitsiCore` and unit-tested on Linux; this is just the socket.
public actor BridgeChannel {
    private let url: URL
    private let session: URLSession
    private let delegate: WSDelegate
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?

    /// Called with the dominant-speaker endpoint id when it changes.
    public var onDominantSpeaker: (@Sendable (String) -> Void)?
    /// Called once when the wss handshake completes (the JVB accepted us).
    public var onOpen: (@Sendable () -> Void)?
    /// Called when the socket closes, with the close code.
    public var onClose: (@Sendable (Int) -> Void)?

    public init(url: URL) {
        self.url = url
        self.delegate = WSDelegate()
        self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }

    public func setDominantSpeakerHandler(_ handler: @escaping @Sendable (String) -> Void) {
        onDominantSpeaker = handler
    }

    public func setOpenHandler(_ handler: @escaping @Sendable () -> Void) {
        onOpen = handler
        delegate.onOpen = handler
    }

    public func setCloseHandler(_ handler: @escaping @Sendable (Int) -> Void) {
        onClose = handler
        delegate.onClose = handler
    }

    public func connect() {
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        startReceiving(on: task)
    }

    /// Push receiver video constraints (lastN, selected endpoints, resolutions).
    public func send(_ constraints: ReceiverConstraints) async throws {
        try await send(json: constraints.colibriMessageJSON())
    }

    public func send(json: String) async throws {
        guard let task else { return }
        try await task.send(.string(json))
    }

    public func close() {
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func startReceiving(on task: URLSessionWebSocketTask) {
        receiveLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let message = try? await task.receive() else { return }
                let text: String
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(decoding: d, as: UTF8.self)
                @unknown default: continue
                }
                await self?.handleInbound(text)
            }
        }
    }

    private func handleInbound(_ text: String) {
        if let endpoint = EndpointMessage.dominantSpeaker(fromJSON: text) {
            onDominantSpeaker?(endpoint)
        }
    }
}

/// Bridges `URLSessionWebSocketDelegate`'s open/close callbacks (delivered on the
/// session's delegate queue) to `@Sendable` handlers `BridgeChannel` sets before
/// connecting. Confirming the wss handshake is the [MAC] signal Linux can't give.
private final class WSDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    var onOpen: (@Sendable () -> Void)?
    var onClose: (@Sendable (Int) -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        onOpen?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose?(closeCode.rawValue)
    }
}
#endif
