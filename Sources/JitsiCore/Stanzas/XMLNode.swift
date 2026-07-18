import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A minimal parsed XML element tree. XMPP stanzas are small (the server caps
/// stanza size), so each frame is read into a lightweight node tree by the
/// event-driven ``XMLParser`` and then mapped to typed stanzas. Namespace
/// processing is left off: element names keep any prefix (`stream:features`) and
/// namespaces are read from `xmlns` attributes, which mirrors the wire format.
public final class XMLElementNode {
    public let name: String
    public private(set) var attributes: [String: String]
    public private(set) var children: [XMLElementNode] = []
    public internal(set) var text: String = ""
    public weak var parent: XMLElementNode?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// The element's own namespace, resolved from its `xmlns` attribute if any.
    public var namespace: String? { attributes["xmlns"] }

    /// The local name with any namespace prefix stripped (`stream:features` -> `features`).
    public var localName: String {
        if let idx = name.firstIndex(of: ":") {
            return String(name[name.index(after: idx)...])
        }
        return name
    }

    public func attribute(_ key: String) -> String? { attributes[key] }

    /// First direct child whose local name matches.
    public func child(_ localName: String) -> XMLElementNode? {
        children.first { $0.localName == localName }
    }

    /// All direct children whose local name matches.
    public func children(_ localName: String) -> [XMLElementNode] {
        children.filter { $0.localName == localName }
    }

    /// Depth-first search for the first descendant (or self) with this local name.
    public func firstDescendant(_ localName: String) -> XMLElementNode? {
        if self.localName == localName { return self }
        for child in children {
            if let found = child.firstDescendant(localName) { return found }
        }
        return nil
    }

    func addChild(_ node: XMLElementNode) {
        node.parent = self
        children.append(node)
    }
}

/// Reads a single XML frame into an ``XMLElementNode`` tree.
public enum XMLReader {
    public static func parse(_ frame: String) -> XMLElementNode? {
        guard let data = frame.data(using: .utf8) else { return nil }
        let delegate = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { return nil }
        return root
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLElementNode?
    private var stack: [XMLElementNode] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let node = XMLElementNode(name: elementName, attributes: attributeDict)
        if let top = stack.last {
            top.addChild(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if let node = stack.last {
            node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        stack.removeLast()
    }
}
