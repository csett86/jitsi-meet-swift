// XMPPClient.swift — event-driven XMPP-over-WebSocket client for the SignalingSpike tool.
// Uses Foundation.XMLParser in SAX/event mode for streaming stanza detection.
// This is deliberately throwaway spike code — clarity over elegance.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - Connection state

enum XMPPPhase {
    case connecting
    case waitingFeatures        // after stream open sent
    case sentSASL               // ANONYMOUS auth sent
    case restartingStream       // after SASL success, before new features
    case waitingBindFeatures    // after stream restart
    case sentBind               // bind IQ in flight
    case ready                  // fully authenticated and bound
    case joinedMUC              // MUC presence sent
    case inConference           // self-presence confirmed (status 110)
    case done                   // session-initiate received and ACKed
}

// MARK: - XML SAX parser to detect complete stanza boundaries

/// Detects the end of an element at depth 1 (i.e., a complete XMPP stanza).
/// XMPP-over-WebSocket (RFC 7395) sends one complete XML document per WS frame,
/// so each frame is itself a single stanza — we parse frame-by-frame.
final class StanzaDetector: NSObject, XMLParserDelegate, @unchecked Sendable {
    var rootElementName: String?
    var rootAttributes: [String: String] = [:]
    var textContent: String = ""
    private var depth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        depth += 1
        if depth == 1 {
            rootElementName = elementName
            rootAttributes = attributes
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if depth == 1 { textContent += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        depth -= 1
    }
}

// MARK: - XMPPClient

/// Minimal XMPP client for the spike: connects, authenticates, joins a room,
/// and prints the raw Jingle session-initiate stanza from Jicofo.
final class XMPPClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let domain: String
    private let room: String
    private let nick: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var phase: XMPPPhase = .connecting
    private var myJID: String?
    private var boundID = 1

    // Logging helpers
    private let log: (String) -> Void

    init(domain: String, room: String, nick: String, log: @escaping (String) -> Void = { print($0) }) {
        self.domain = domain
        self.room = room
        self.nick = nick
        self.log = log
    }

    // MARK: - Entry point

    func run() {
        let url = URL(string: "wss://\(domain)/xmpp-websocket")!
        log("Connecting to \(url) …")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url, protocols: ["xmpp"])
        webSocketTask = task
        task.resume()

        // Send initial stream open
        send(StanzaBuilder.streamOpen(to: domain), phase: .waitingFeatures)

        // Receive loop
        receiveLoop()

        // Keep main thread alive (CLI tool)
        dispatchMain()
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        log("WebSocket opened, protocol: \(proto ?? "<none>")")
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let msg = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        log("WebSocket closed: \(closeCode) \(msg)")
        exit(0)
    }

    // MARK: - Receive loop

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(frame: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handle(frame: text)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()

            case .failure(let error):
                self.log("Receive error: \(error)")
                exit(1)
            }
        }
    }

    // MARK: - Frame dispatch

    private func handle(frame: String) {
        log("← \(frame.prefix(200))\(frame.count > 200 ? "…" : "")")

        let detector = StanzaDetector()
        let parser = XMLParser(data: Data(frame.utf8))
        parser.shouldProcessNamespaces = true
        parser.delegate = detector
        _ = parser.parse()

        let element = detector.rootElementName ?? ""
        let attrs = detector.rootAttributes

        switch phase {
        case .waitingFeatures:
            // Expect <open> then <stream:features>
            if element == "features" || element == "open" {
                // If features arrived already in the open frame (some impls combine them), fall through
                if frame.contains("ANONYMOUS") {
                    log("→ Sending SASL ANONYMOUS")
                    send(StanzaBuilder.saslAnonymous(), phase: .sentSASL)
                }
            } else if element == "features" && frame.contains("ANONYMOUS") {
                log("→ Sending SASL ANONYMOUS")
                send(StanzaBuilder.saslAnonymous(), phase: .sentSASL)
            }

        case .sentSASL:
            if element == "success" {
                log("SASL success — restarting stream")
                send(StanzaBuilder.streamOpen(to: domain), phase: .waitingBindFeatures)
            } else if element == "failure" {
                log("SASL failure: \(frame)")
                exit(1)
            }

        case .waitingBindFeatures:
            if element == "features" && frame.contains("bind") {
                let id = "bind_\(boundID)"
                log("→ Binding resource '\(nick)'")
                send(StanzaBuilder.bindIQ(id: id, resource: nick), phase: .sentBind)
            }

        case .sentBind:
            if element == "iq", attrs["type"] == "result" {
                // Extract the assigned JID
                if let jidRange = frame.range(of: "<jid>"),
                   let jidEnd = frame.range(of: "</jid>") {
                    let jid = String(frame[jidRange.upperBound..<jidEnd.lowerBound])
                    myJID = jid
                    log("Bound JID: \(jid)")
                }
                phase = .ready
                onReady()
            }

        case .ready:
            // Shouldn't normally receive here before we send disco/MUC
            break

        case .joinedMUC:
            // Wait for self-presence (status 110) or session-initiate
            if element == "presence" {
                let from = attrs["from"] ?? ""
                if frame.contains("code=\"110\"") {
                    log("✓ Joined MUC as \(from) — waiting for focus and session-initiate")
                    phase = .inConference
                }
            }

        case .inConference:
            if element == "presence" {
                let from = attrs["from"] ?? ""
                if frame.contains("focus") && (frame.contains("moderator") || from.hasSuffix("/focus")) {
                    log("✓ Focus (Jicofo) joined: \(from)")
                }
            } else if element == "iq", attrs["type"] == "set" {
                if frame.contains("session-initiate") {
                    log("\n====== SESSION-INITIATE RECEIVED ======")
                    log(frame)
                    log("======================================\n")
                    // ACK the IQ
                    let iqID = attrs["id"] ?? ""
                    let iqFrom = attrs["from"] ?? ""
                    if !iqID.isEmpty {
                        send(StanzaBuilder.jingleAck(to: iqFrom, id: iqID), phase: .done)
                    }
                }
            }

        case .done:
            log("Session complete. Exiting.")
            exit(0)

        default:
            // Handle unexpected stanzas for informational features
            if element == "iq" && attrs["type"] == "result" {
                let id = attrs["id"] ?? ""
                if id == "extdisco_1" {
                    log("TURN/STUN services received:")
                    log(frame)
                } else if id.hasPrefix("disco_") {
                    log("Disco result (\(id)):")
                    log(frame)
                }
            }
        }
    }

    // MARK: - Post-bind sequence

    private func onReady() {
        // 1. disco#info on server domain
        let d1 = StanzaBuilder.discoInfoGet(to: domain, id: "disco_1")
        send(d1)
        log("→ disco#info to \(domain)")

        // 2. disco#info on conference component
        let confDomain = "conference.\(domain)"
        let d2 = StanzaBuilder.discoInfoGet(to: confDomain, id: "disco_2")
        send(d2)
        log("→ disco#info to \(confDomain)")

        // 3. XEP-0215 external service discovery
        let ext = StanzaBuilder.extDiscoGet(to: domain, id: "extdisco_1")
        send(ext)
        log("→ extdisco to \(domain)")

        // 4. Join the MUC
        let statsID = "SpikeDevice-\(Int.random(in: 10000...99999))"
        let joinXML = StanzaBuilder.mucJoin(room: room, nick: nick, statsID: statsID)
        send(joinXML)
        log("→ MUC join presence to \(room)/\(nick)")
        phase = .joinedMUC
    }

    // MARK: - Send helper

    private func send(_ stanza: String, phase newPhase: XMPPPhase? = nil) {
        if let p = newPhase { phase = p }
        log("→ \(stanza.prefix(160))\(stanza.count > 160 ? "…" : "")")
        webSocketTask?.send(.string(stanza)) { [weak self] error in
            if let error {
                self?.log("Send error: \(error)")
            }
        }
    }
}
