import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - Internal XML element tree

/// A lightweight, immutable XML element node built by ``XMLTreeBuilder``.
/// Used internally by ``StanzaParser`` — not part of the public API.
struct XMLElement: Sendable {
    let localName: String
    let namespaceURI: String?
    let qualifiedName: String?
    /// Unqualified attribute names as keys (namespace-processed).
    let attributes: [String: String]
    var children: [XMLElement]
    /// Accumulated character data for this element.
    var text: String

    // MARK: Conveniences

    func attr(_ name: String) -> String? { attributes[name] }

    func firstChild(localName name: String, namespace ns: String? = nil) -> XMLElement? {
        children.first { $0.localName == name && (ns == nil || $0.namespaceURI == ns) }
    }

    func allChildren(localName name: String, namespace ns: String? = nil) -> [XMLElement] {
        children.filter { $0.localName == name && (ns == nil || $0.namespaceURI == ns) }
    }

    /// Returns the trimmed text content of this element.
    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - SAX builder

/// SAX-style XMLParser delegate that builds an ``XMLElement`` tree.
/// Marked `@unchecked Sendable` because NSObject isn't Sendable, yet the
/// instance is never shared across concurrency domains — it is created,
/// populated, and read within a single synchronous `parse()` call.
final class XMLTreeBuilder: NSObject, XMLParserDelegate, @unchecked Sendable {
    private(set) var root: XMLElement?
    private var stack: [XMLElement] = []
    private(set) var parseError: Error?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = XMLElement(
            localName: elementName,
            namespaceURI: namespaceURI?.isEmpty == false ? namespaceURI : nil,
            qualifiedName: qName,
            attributes: attributeDict,
            children: [],
            text: ""
        )
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard !stack.isEmpty else { return }
        let finished = stack.removeLast()
        if stack.isEmpty {
            root = finished
        } else {
            stack[stack.count - 1].children.append(finished)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        parseError = error
    }

    func parser(_ parser: XMLParser, validationErrorOccurred error: Error) {
        parseError = error
    }
}

// MARK: - Parsing helper

enum XMLParseError: Error, Sendable {
    case invalidEncoding
    case emptyDocument
    case parserError(Error)
}

/// Parses a complete XML string into an ``XMLElement`` tree.
/// Each XMPP-over-WebSocket frame is a complete XML document,
/// so one call per received frame is correct.
func parseXMLElement(_ xmlString: String) throws -> XMLElement {
    guard let data = xmlString.data(using: .utf8) else {
        throw XMLParseError.invalidEncoding
    }
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = false
    let builder = XMLTreeBuilder()
    parser.delegate = builder
    _ = parser.parse()
    if let err = builder.parseError { throw XMLParseError.parserError(err) }
    guard let root = builder.root else { throw XMLParseError.emptyDocument }
    return root
}
