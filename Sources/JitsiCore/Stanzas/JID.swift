import Foundation

/// An XMPP JID (`local@domain/resource`), with any part optional.
public struct JID: Equatable, Sendable {
    public let local: String?
    public let domain: String
    public let resource: String?

    public init(local: String?, domain: String, resource: String?) {
        self.local = local
        self.domain = domain
        self.resource = resource
    }

    public init?(_ string: String) {
        var rest = Substring(string)
        var local: String?
        if let at = rest.firstIndex(of: "@") {
            local = String(rest[..<at])
            rest = rest[rest.index(after: at)...]
        }
        var resource: String?
        if let slash = rest.firstIndex(of: "/") {
            resource = String(rest[rest.index(after: slash)...])
            rest = rest[..<slash]
        }
        guard !rest.isEmpty else { return nil }
        self.local = local
        self.domain = String(rest)
        self.resource = resource
    }

    /// The bare JID (`local@domain`), dropping any resource.
    public var bare: String {
        if let local { return "\(local)@\(domain)" }
        return domain
    }

    public var full: String {
        if let resource { return "\(bare)/\(resource)" }
        return bare
    }
}
