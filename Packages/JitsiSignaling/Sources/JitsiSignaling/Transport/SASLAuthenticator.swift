import Foundation

// MARK: - SASL ANONYMOUS helpers

/// Builds and validates SASL ANONYMOUS stanzas.
///
/// SASL ANONYMOUS (RFC 4505) requires no credentials — the initial response
/// is empty. The server assigns a temporary identity.
public enum SASLAuthenticator {
    /// The SASL mechanism name this authenticator implements.
    public static let mechanism = "ANONYMOUS"

    /// Returns the `<auth>` stanza to send after receiving stream features
    /// that advertise the ANONYMOUS mechanism.
    public static func authStanza() -> String {
        "<auth xmlns=\"\(XMPPNS.sasl)\" mechanism=\"ANONYMOUS\"/>"
    }

    /// Returns `true` if the raw XML frame is a SASL `<success/>`.
    public static func isSuccess(_ xml: String) -> Bool {
        xml.contains("<success") && xml.contains(XMPPNS.sasl)
    }

    /// Returns `true` if the raw XML frame is a SASL `<failure>`.
    public static func isFailure(_ xml: String) -> Bool {
        xml.contains("<failure") && xml.contains(XMPPNS.sasl)
    }
}
