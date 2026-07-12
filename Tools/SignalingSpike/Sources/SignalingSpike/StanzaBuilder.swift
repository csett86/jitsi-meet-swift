// StanzaBuilder.swift — minimal XMPP stanza string helpers for the SignalingSpike CLI tool.
// These are deliberately simple string builders; the production library uses typed structs.

import Foundation

enum StanzaBuilder {
    // MARK: - Stream-level frames (RFC 7395 / XEP-0206)

    static func streamOpen(to domain: String) -> String {
        "<open xmlns=\"urn:ietf:params:xml:ns:xmpp-framing\" to=\"\(domain)\" version=\"1.0\"/>"
    }

    // MARK: - SASL

    static func saslAnonymous() -> String {
        "<auth xmlns=\"urn:ietf:params:xml:ns:xmpp-sasl\" mechanism=\"ANONYMOUS\"/>"
    }

    // MARK: - Resource bind

    static func bindIQ(id: String, resource: String) -> String {
        "<iq xmlns=\"jabber:client\" type=\"set\" id=\"\(id)\">" +
        "<bind xmlns=\"urn:ietf:params:xml:ns:xmpp-bind\">" +
        "<resource>\(resource)</resource>" +
        "</bind></iq>"
    }

    // MARK: - Service discovery (XEP-0030)

    static func discoInfoGet(to: String, id: String) -> String {
        "<iq xmlns=\"jabber:client\" type=\"get\" to=\"\(to)\" id=\"\(id)\">" +
        "<query xmlns=\"http://jabber.org/protocol/disco#info\"/>" +
        "</iq>"
    }

    // MARK: - External service discovery (XEP-0215)

    static func extDiscoGet(to: String, id: String) -> String {
        "<iq xmlns=\"jabber:client\" type=\"get\" to=\"\(to)\" id=\"\(id)\">" +
        "<services xmlns=\"urn:xmpp:extdisco:2\"/>" +
        "</iq>"
    }

    // MARK: - MUC join (XEP-0045)

    /// Sends a MUC join presence to room/nick with Jitsi-specific extensions.
    static func mucJoin(room: String, nick: String, statsID: String) -> String {
        "<presence xmlns=\"jabber:client\" to=\"\(room)/\(nick)\">" +
        "<x xmlns=\"http://jabber.org/protocol/muc\"/>" +
        "<nick xmlns=\"http://jabber.org/protocol/nick\">\(nick)</nick>" +
        "<stats-id xmlns=\"http://jitsi.org/jitmeet\">\(statsID)</stats-id>" +
        "<videotype xmlns=\"http://jitsi.org/jitmeet/video\">camera</videotype>" +
        "<features xmlns=\"http://jitsi.org/jitmeet\">" +
        "<feature var=\"urn:ietf:rfc:5888\"/>" +
        "<feature var=\"urn:ietf:rfc:5761\"/>" +
        "<feature var=\"urn:ietf:rfc:4588\"/>" +
        "</features>" +
        "</presence>"
    }

    // MARK: - Jingle ACK

    static func jingleAck(to: String, id: String) -> String {
        "<iq xmlns=\"jabber:client\" type=\"result\" to=\"\(to)\" id=\"\(id)\"/>"
    }
}
