// MARK: - Message stanza

public struct MessageStanza: Sendable {
    public enum MessageType: String, Sendable {
        case chat      = "chat"
        case groupchat = "groupchat"
        case normal    = "normal"
        case headline  = "headline"
        case error     = "error"
    }

    public let id: String?
    public let from: String?
    public let to: String?
    public let type: MessageType
    public let body: String?
    public let thread: String?
    public let subject: String?

    init(element: XMLElement) {
        id      = element.attr("id")
        from    = element.attr("from")
        to      = element.attr("to")
        let typeStr = element.attr("type") ?? "normal"
        type    = MessageType(rawValue: typeStr) ?? .normal
        body    = element.firstChild(localName: "body")?.trimmedText
        thread  = element.firstChild(localName: "thread")?.trimmedText
        subject = element.firstChild(localName: "subject")?.trimmedText
    }
}
