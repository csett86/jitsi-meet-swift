import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - JitsiConference

/// Top-level orchestration actor — the public entry point for all signaling.
///
/// ```swift
/// let conference = JitsiConference()
/// let events = try await conference.connect(
///     config: BackendConfig(conferenceURL: "https://alpha.jitsi.net/MyRoom")
/// )
/// for await event in events {
///     switch event {
///     case .sessionDescriptionReceived(let jingle):
///         // hand jingle to Phase 2 (WebRTC peer connection)
///     case .participantJoined(let p):
///         print("joined:", p.nick ?? p.occupantJID)
///     default:
///         break
///     }
/// }
/// ```
public actor JitsiConference {
    // MARK: - Public state

    public private(set) var state: ConferenceState = .initial

    // MARK: - Private

    private var connection: XMPPWebSocketConnection?
    private var mucSession: MUCSession?
    private var eventContinuation: AsyncThrowingStream<ConferenceEvent, Error>.Continuation?
    private var stanzaRouterTask: Task<Void, Never>?
    private var mucRouterTask: Task<Void, Never>?

    // MARK: - Init

    public init() {}

    // MARK: - Connect

    /// Connects to a Jitsi conference and returns an event stream.
    ///
    /// The stream emits:
    /// - ``ConferenceEvent/connectionStateChanged(_:)`` as state progresses
    /// - ``ConferenceEvent/participantJoined(_:)`` / ``ConferenceEvent/participantLeft(occupantJID:)``
    /// - ``ConferenceEvent/sessionDescriptionReceived(_:)`` when focus sends session-initiate
    ///
    /// Throws on fatal connection errors. The stream finishes when the session ends.
    @discardableResult
    public func connect(config: BackendConfig) -> AsyncThrowingStream<ConferenceEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<ConferenceEvent, Error>.makeStream()
        eventContinuation = continuation

        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(config: config)
        }

        continuation.onTermination = { [weak self] _ in
            task.cancel()
            Task { [weak self] in await self?.cleanup() }
        }

        return stream
    }

    // MARK: - Disconnect

    public func disconnect() async {
        await cleanup()
    }

    // MARK: - Private run loop

    private func run(config: BackendConfig) async {
        do {
            // --- Connect and authenticate ---
            emit(.connectionStateChanged(.connecting))
            let conn = XMPPWebSocketConnection()
            connection = conn
            try await conn.connect(
                to: config.xmppWebSocketURL,
                domain: config.xmppDomain,
                resource: "swift-\(randomResource())"
            )
            guard let myJID = await conn.fullJID else { throw XMPPConnectionError.bindFailed }
            updateState { s in
                ConferenceState(
                    connectionState: .authenticating,
                    capabilities: s.capabilities,
                    participants: s.participants,
                    jingleSession: s.jingleSession,
                    turnServices: s.turnServices,
                    myFullJID: myJID
                )
            }

            // --- Service discovery ---
            emit(.connectionStateChanged(.discoveringFeatures))
            let (caps, turns) = try await discoverFeatures(conn: conn, config: config)

            updateState { s in
                ConferenceState(
                    connectionState: .discoveringFeatures,
                    capabilities: caps,
                    participants: s.participants,
                    jingleSession: s.jingleSession,
                    turnServices: turns,
                    myFullJID: s.myFullJID
                )
            }

            // --- Join MUC ---
            emit(.connectionStateChanged(.joiningRoom))
            let muc = MUCSession(
                conferenceJID: config.conferenceJID,
                nick: "swift",
                myFullJID: myJID
            )
            mucSession = muc
            try await muc.join(via: conn)

            // Route MUC events
            mucRouterTask = Task { [weak self] in
                guard let self else { return }
                for await event in muc.events {
                    await self.handleMUCEvent(event, caps: caps)
                }
            }

            // --- Route stanzas from connection ---
            let stanzaStream = await conn.stanzas
            stanzaRouterTask = Task { [weak self] in
                guard let self else { return }
                for await stanza in stanzaStream {
                    await self.route(stanza: stanza, muc: muc)
                }
            }

            // Wait until cancelled
            try await Task.sleep(nanoseconds: .max)

        } catch is CancellationError {
            // Normal shutdown
        } catch {
            let sendableError = ConferenceSignalingError(underlying: error)
            emit(.connectionStateChanged(.error(sendableError)))
            eventContinuation?.finish(throwing: error)
        }
    }

    // MARK: - Service discovery

    private func discoverFeatures(
        conn: XMPPWebSocketConnection,
        config: BackendConfig
    ) async throws -> (BackendCapabilities, [ExternalService]) {
        // disco#info to XMPP server
        let serverDisco = try await sendDiscoInfo(conn: conn, to: config.xmppDomain)
        // disco#info to conference component
        let mucDisco = try await sendDiscoInfo(conn: conn, to: config.mucDomain)
        let caps = BackendCapabilities(serverInfo: serverDisco, mucInfo: mucDisco)

        // TURN discovery if supported
        var turns: [ExternalService] = []
        if caps.supportsExtdisco {
            turns = (try? await sendExtdisco(conn: conn, to: config.xmppDomain)) ?? []
        }
        return (caps, turns)
    }

    private func sendDiscoInfo(conn: XMPPWebSocketConnection, to jid: String) async throws -> DiscoInfoResult {
        let iqID = try await conn.sendIQ(
            type: "get",
            to: jid,
            payload: "<query xmlns=\"\(XMPPNS.discoInfo)\"/>"
        )
        // Block for the matching result IQ (simple: read until we see it)
        let stanzaStream = await conn.stanzas
        for await stanza in stanzaStream {
            if case .iq(let iq) = stanza,
               iq.id == iqID,
               iq.type == .result,
               case .discoInfo(let result) = iq.payload {
                return result
            }
        }
        return DiscoInfoResult(element: XMLElement(
            localName: "query", namespaceURI: XMPPNS.discoInfo,
            qualifiedName: nil, attributes: [:], children: [], text: ""
        ))
    }

    private func sendExtdisco(conn: XMPPWebSocketConnection, to jid: String) async throws -> [ExternalService] {
        let iqID = try await conn.sendIQ(
            type: "get",
            to: jid,
            payload: "<services xmlns=\"\(XMPPNS.extdisco)\"/>"
        )
        let stanzaStream = await conn.stanzas
        for await stanza in stanzaStream {
            if case .iq(let iq) = stanza,
               iq.id == iqID,
               iq.type == .result,
               case .externalServices(let svcs) = iq.payload {
                return svcs
            }
        }
        return []
    }

    // MARK: - Stanza routing

    private func route(stanza: ReceivedStanza, muc: MUCSession) async {
        switch stanza {
        case .presence(let p):
            await muc.handle(presence: p)

        case .iq(let iq) where iq.type == .set:
            if case .jingle(let jingle) = iq.payload, jingle.action == .sessionInitiate {
                // ACK the session-initiate
                if let id = iq.id, let from = iq.from {
                    let ack = "<iq xmlns=\"jabber:client\" type=\"result\" to=\"\(from)\" id=\"\(id)\"/>"
                    try? await connection?.sendRaw(ack)
                }
                updateState { s in
                    ConferenceState(
                        connectionState: s.connectionState,
                        capabilities: s.capabilities,
                        participants: s.participants,
                        jingleSession: jingle,
                        turnServices: s.turnServices,
                        myFullJID: s.myFullJID
                    )
                }
                emit(.sessionDescriptionReceived(jingle))
            }

        case .unknown(let name, _):
            emit(.warning("Unrecognised stanza: \(name)"))

        default:
            break
        }
    }

    private func handleMUCEvent(_ event: MUCSession.Event, caps: BackendCapabilities) {
        switch event {
        case .joined(let jid):
            updateState { s in
                ConferenceState(
                    connectionState: .joined(capabilities: caps),
                    capabilities: caps,
                    participants: s.participants,
                    jingleSession: s.jingleSession,
                    turnServices: s.turnServices,
                    myFullJID: s.myFullJID
                )
            }
            emit(.connectionStateChanged(.joined(capabilities: caps)))
            _ = jid

        case .participantJoined(let p):
            updateState { s in
                var m = s.participants; m[p.occupantJID] = p
                return ConferenceState(
                    connectionState: s.connectionState, capabilities: s.capabilities,
                    participants: m, jingleSession: s.jingleSession,
                    turnServices: s.turnServices, myFullJID: s.myFullJID
                )
            }
            emit(.participantJoined(p))

        case .participantUpdated(let p):
            updateState { s in
                var m = s.participants; m[p.occupantJID] = p
                return ConferenceState(
                    connectionState: s.connectionState, capabilities: s.capabilities,
                    participants: m, jingleSession: s.jingleSession,
                    turnServices: s.turnServices, myFullJID: s.myFullJID
                )
            }
            emit(.participantUpdated(p))

        case .participantLeft(let jid):
            updateState { s in
                var m = s.participants; m.removeValue(forKey: jid)
                return ConferenceState(
                    connectionState: s.connectionState, capabilities: s.capabilities,
                    participants: m, jingleSession: s.jingleSession,
                    turnServices: s.turnServices, myFullJID: s.myFullJID
                )
            }
            emit(.participantLeft(occupantJID: jid))

        case .focusJoined(let p):
            emit(.focusJoined(p))
        }
    }

    // MARK: - Helpers

    private func emit(_ event: ConferenceEvent) {
        eventContinuation?.yield(event)
    }

    private func updateState(_ transform: (ConferenceState) -> ConferenceState) {
        state = transform(state)
    }

    private func cleanup() async {
        stanzaRouterTask?.cancel()
        mucRouterTask?.cancel()
        await connection?.disconnect()
        connection = nil
        mucSession = nil
        eventContinuation?.finish()
        eventContinuation = nil
        state = .initial
    }

    private func randomResource() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<8).compactMap { _ in chars.randomElement() })
    }
}

// MARK: - Error wrapper (makes arbitrary errors Sendable for ConferenceState)

struct ConferenceSignalingError: Error, Sendable {
    let underlying: Error
    var localizedDescription: String { underlying.localizedDescription }
}
