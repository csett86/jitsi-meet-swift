import Foundation
import JitsiCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// LiveCapture — a headless XMPP-over-WebSocket frame dumper used to capture
// [CLOUD-LIVE] signaling fixtures. This is throwaway plumbing: the shipping
// transport is Swift `URLSessionStanzaTransport`; this tool only needs to
// reliably record what a real Jitsi deployment sends so the deterministic
// offline tests have real fixtures to replay.
//
// Courtesy rules (see docs/live-testing.md): run on-demand only, single client,
// short sessions, dedicated test rooms. Never on a schedule.
//
// Usage:
//   LiveCapture <conference-url> [output.json]
// or set JITSI_TEST_URL. Without an explicit URL it refuses to run so it can
// never accidentally connect to a community server.

struct CapturedFrame: Codable {
    let direction: String   // "in" or "out"
    let timestamp: Double
    let payload: String
}

@main
struct LiveCapture {
    static func main() async {
        let args = CommandLine.arguments
        let urlArg = args.count > 1 ? args[1] : ProcessInfo.processInfo.environment["JITSI_TEST_URL"]
        guard let urlArg, let parsed = ConferenceURLParser.parse(urlArg) else {
            FileHandle.standardError.write(Data(
                "LiveCapture: provide a conference URL (arg or JITSI_TEST_URL). Refusing to run without an explicit target.\n".utf8
            ))
            exit(2)
        }
        let output = args.count > 2 ? args[2] : "docs/fixtures/live-capture.json"

        let capturer = FrameCapturer(config: parsed.config, roomName: parsed.roomName)
        do {
            let frames = try await capturer.run()
            let data = try JSONEncoder.prettyPrinted.encode(frames)
            try data.write(to: URL(fileURLWithPath: output))
            print("LiveCapture: wrote \(frames.count) frames to \(output)")
        } catch {
            FileHandle.standardError.write(Data("LiveCapture failed: \(error)\n".utf8))
            exit(1)
        }
    }
}

extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

/// Opens the XMPP-over-WebSocket stream (RFC 7395), sends the opening frame,
/// and records every frame in both directions until the stream settles or a
/// short timeout elapses. Deliberately minimal — a full SASL/bind/MUC join is
/// driven by scripting additional outbound stanzas.
actor FrameCapturer {
    private let config: BackendConfig
    private let roomName: String
    private var frames: [CapturedFrame] = []
    private let start = Date()

    init(config: BackendConfig, roomName: String) {
        self.config = config
        self.roomName = roomName
    }

    func run() async throws -> [CapturedFrame] {
        var request = URLRequest(url: config.xmppWebSocketURL)
        // RFC 7395: the WebSocket subprotocol for XMPP framing.
        request.setValue("xmpp", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        task.resume()

        let host = config.xmppWebSocketURL.host ?? config.displayName
        let open = #"<open xmlns="urn:ietf:params:xml:ns:xmpp-framing" to="\#(host)" version="1.0"/>"#
        try await send(task, open)

        // Read whatever the server offers (stream features / SASL mechanisms)
        // with a short bound so a probe stays minimal-footprint.
        try await readFrames(task, maxFrames: 8, timeoutSeconds: 8)

        task.cancel(with: .normalClosure, reason: nil)
        return frames
    }

    private func send(_ task: URLSessionWebSocketTask, _ text: String) async throws {
        record(direction: "out", payload: text)
        try await task.send(.string(text))
    }

    private func readFrames(_ task: URLSessionWebSocketTask, maxFrames: Int, timeoutSeconds: Double) async throws {
        for _ in 0..<maxFrames {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await withTimeout(seconds: timeoutSeconds) {
                    try await task.receive()
                }
            } catch is TimeoutError {
                return
            }
            switch message {
            case .string(let text):
                record(direction: "in", payload: text)
            case .data(let data):
                record(direction: "in", payload: String(decoding: data, as: UTF8.self))
            @unknown default:
                return
            }
        }
    }

    private func record(direction: String, payload: String) {
        frames.append(CapturedFrame(
            direction: direction,
            timestamp: Date().timeIntervalSince(start),
            payload: payload
        ))
    }
}

struct TimeoutError: Error {}

func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
