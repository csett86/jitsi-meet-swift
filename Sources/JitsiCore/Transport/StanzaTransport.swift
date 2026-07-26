import Foundation

/// The lifecycle of a signaling connection, surfaced to the UI
/// (connecting/connected/reconnecting/failed).
public enum ConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
    case disconnected
    case failed(String)
}

/// The seam between the signaling logic and the actual socket.
///
/// Everything in `MUC`/`Conference` is written against this protocol — never
/// against `URLSession` directly — so the full join flow can be driven offline
/// by `FakeTransport` replaying committed fixtures, and live by
/// `URLSessionStanzaTransport`. `send` takes a stanza string; inbound frames and
/// connection state are delivered as `AsyncStream`s.
public protocol StanzaTransport: Actor {
    /// Open the connection. Emits `.connecting` then `.connected` (or `.failed`).
    func connect() async throws
    /// Send one stanza (a complete XML element) to the server.
    func send(_ stanza: String) async throws
    /// Close the connection.
    func disconnect() async
    /// Inbound frames, each a complete stanza as raw bytes.
    var incoming: AsyncStream<Data> { get async }
    /// Connection-state transitions.
    var state: AsyncStream<ConnectionState> { get async }
}
