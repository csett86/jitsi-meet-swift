import Foundation

/// Drives a conference join over a ``StanzaTransport`` and emits a typed stream
/// of ``ConferenceEvent``s (roster changes, capabilities, ICE servers, and the
/// normalized ``ParsedSessionDescription``).
///
/// The join is a reactive state machine fed only by inbound stanzas, so the same
/// logic runs offline over ``FakeTransport`` (replaying fixtures) and live over
/// ``URLSessionStanzaTransport``. It never touches a socket directly.
public actor JitsiConference {
    private let transport: any StanzaTransport
    private let config: BackendConfig
    private let roomName: String
    private let nick: String
    private let machineUID: String

    private let eventStream: AsyncStream<ConferenceEvent>
    private let eventContinuation: AsyncStream<ConferenceEvent>.Continuation

    // Handshake / conference state.
    private var authenticated = false
    private var joined = false
    private var boundJID: JID?
    private var muc = MUCSession()
    private var capabilities: BackendCapabilities?

    /// Features we advertise when Jicofo probes our `disco#info` — enough for it
    /// to treat us as a Jingle/RTP media endpoint and send `session-initiate`.
    private static let clientFeatures = [
        "http://jabber.org/protocol/disco#info",
        "urn:xmpp:jingle:1",
        "urn:xmpp:jingle:apps:rtp:1",
        "urn:xmpp:jingle:apps:rtp:audio",
        "urn:xmpp:jingle:apps:rtp:video",
        "urn:xmpp:jingle:transports:ice-udp:1",
        "urn:xmpp:jingle:apps:dtls:0",
        "urn:xmpp:jingle:transports:dtls-sctp:1",
        "urn:ietf:rfc:5761",
        "urn:ietf:rfc:5888",
        "http://jitsi.org/tcc",
    ]

    public init(transport: any StanzaTransport, config: BackendConfig,
                roomName: String, nick: String? = nil, machineUID: String? = nil) {
        self.transport = transport
        self.config = config
        self.roomName = roomName
        self.nick = nick ?? "swift-" + String(UUID().uuidString.prefix(8))
        self.machineUID = machineUID ?? UUID().uuidString
        (eventStream, eventContinuation) = AsyncStream.makeStream(of: ConferenceEvent.self)
    }

    /// The event stream. Iterate this to observe the join; it finishes when the
    /// connection closes.
    public var events: AsyncStream<ConferenceEvent> { eventStream }

    /// Current roster (self first).
    public var roster: [Participant] { muc.ordered }

    /// Connect and run the join to completion (returns when the inbound stream
    /// ends). Emits events throughout.
    public func join() async {
        emit(.stateChanged(.connecting))
        let states = await transport.state
        let stateTask = Task { [weak self] in
            for await state in states { await self?.handleState(state) }
        }
        let inbound = await transport.incoming
        do {
            try await transport.connect()
            try await transport.send(streamOpen())
            emit(.stateChanged(.authenticating))
        } catch {
            emit(.stateChanged(.failed("connect failed: \(error)")))
            stateTask.cancel()
            eventContinuation.finish()
            return
        }
        for await data in inbound {
            let frame = String(decoding: data, as: UTF8.self)
            if let stanza = StanzaParser.parse(frame) {
                await handle(stanza)
            }
        }
        stateTask.cancel()
        eventContinuation.finish()
    }

    public func leave() async {
        try? await transport.send(leavePresence())
        await transport.disconnect()
    }

    // MARK: - Stanza handling

    private func handle(_ stanza: Stanza) async {
        switch stanza {
        case .streamOpen:
            break
        case .streamFeatures(let features):
            if !authenticated, features.supportsAnonymous {
                try? await transport.send(anonymousAuth())
            } else if authenticated, features.bindRequired {
                try? await transport.send(bindRequest())
            }
        case .saslSuccess:
            authenticated = true
            try? await transport.send(streamOpen())   // stream restart
        case .saslFailure(let condition):
            emit(.stateChanged(.failed("SASL failure: \(condition ?? "unknown")")))
        case .iq(let iq):
            await handleIQ(iq)
        case .presence(let presence):
            handlePresence(presence)
        case .message, .unknown:
            break
        }
    }

    private func handleIQ(_ iq: IQ) async {
        switch iq.payload {
        case .bind(let jid):
            boundJID = jid.flatMap(JID.init)
            // Post-bind: discover the deployment, then ask Jicofo to allocate.
            try? await transport.send(discoInfoRequest())
            try? await transport.send(externalServicesRequest())
            try? await transport.send(conferenceRequest())
            emit(.stateChanged(.joining))
        case .discoInfo(let disco):
            if iq.type == "result" {
                let caps = BackendCapabilities(disco: disco)
                capabilities = caps
                emit(.capabilities(caps))
            } else if iq.type == "get" {
                // Jicofo is probing our capabilities — answer so it invites us.
                try? await transport.send(discoInfoResponse(to: iq.from, id: iq.id))
            }
        case .externalServices(let services):
            emit(.iceServers(TURNDiscovery.iceServers(from: services)))
        case .conference(let response):
            emit(.conferenceReady(response))
            if response.ready {
                try? await transport.send(joinPresence())
            }
        case .jingle(let jingle):
            if jingle.action == "session-initiate" {
                if let id = iq.id, let from = iq.from {
                    try? await transport.send(iqResult(to: from, id: id))
                }
                emit(.sessionDescription(ParsedSessionDescription(jingle: jingle)))
            }
        case .empty, .unknown:
            break
        }
    }

    private func handlePresence(_ presence: Presence) {
        if let change = muc.apply(presence) {
            emit(.roster(change))
        }
        if presence.isSelfPresence {
            if presence.type == "unavailable" {
                emit(.stateChanged(.left))
            } else if !joined {
                joined = true
                emit(.stateChanged(.joined))
            }
        }
    }

    private func handleState(_ state: ConnectionState) {
        switch state {
        case .failed(let reason): emit(.stateChanged(.failed(reason)))
        case .reconnecting: emit(.stateChanged(.reconnecting))
        default: break
        }
    }

    private func emit(_ event: ConferenceEvent) {
        eventContinuation.yield(event)
    }

    // MARK: - Stanza builders

    private var host: String { config.xmppWebSocketURL.host ?? config.displayName }
    // Jitsi lowercases the room name when forming the MUC JID.
    private var roomJID: String { "\(roomName.lowercased())@\(config.mucDomain)" }

    private func streamOpen() -> String {
        "<open xmlns='urn:ietf:params:xml:ns:xmpp-framing' to='\(host)' version='1.0'/>"
    }
    private func anonymousAuth() -> String {
        "<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='ANONYMOUS'/>"
    }
    private func bindRequest() -> String {
        "<iq type='set' id='bind1' xmlns='jabber:client'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></iq>"
    }
    private func discoInfoRequest() -> String {
        "<iq type='get' id='disco1' to='\(host)' xmlns='jabber:client'><query xmlns='http://jabber.org/protocol/disco#info'/></iq>"
    }
    private func externalServicesRequest() -> String {
        "<iq type='get' id='ext1' to='\(host)' xmlns='jabber:client'><services xmlns='urn:xmpp:extdisco:2'/></iq>"
    }
    private func conferenceRequest() -> String {
        "<iq type='set' id='conf1' to='\(config.focusJID)' xmlns='jabber:client'>"
        + "<conference xmlns='http://jitsi.org/protocol/focus' room='\(roomJID)' machine-uid='\(machineUID)'/></iq>"
    }
    private func joinPresence() -> String {
        "<presence to='\(roomJID)/\(nick)' xmlns='jabber:client'>"
        + "<x xmlns='http://jabber.org/protocol/muc'/>"
        + "<stats-id>\(nick)</stats-id>"
        + "<nick xmlns='http://jabber.org/protocol/nick'>\(nick)</nick>"
        + "<audiomuted xmlns='http://jitsi.org/jitmeet/audio'>false</audiomuted>"
        + "<videomuted xmlns='http://jitsi.org/jitmeet/video'>false</videomuted>"
        + "</presence>"
    }
    private func leavePresence() -> String {
        "<presence to='\(roomJID)/\(nick)' type='unavailable' xmlns='jabber:client'/>"
    }
    private func discoInfoResponse(to: String?, id: String?) -> String {
        let features = Self.clientFeatures.map { "<feature var='\($0)'/>" }.joined()
        return "<iq type='result' to='\(to ?? config.focusJID)' id='\(id ?? "disco")' xmlns='jabber:client'>"
            + "<query xmlns='http://jabber.org/protocol/disco#info'>"
            + "<identity category='client' type='pc' name='JitsiMeetSwift'/>"
            + features + "</query></iq>"
    }
    private func iqResult(to: String, id: String) -> String {
        "<iq type='result' to='\(to)' id='\(id)' xmlns='jabber:client'/>"
    }
}
