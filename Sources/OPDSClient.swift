import Foundation

/// Basic OPDS 1.x Atom feed search client. Endpoint URL is user-configurable.
struct OPDSClient {
    let searchEndpoint: String
    let queryParameter: String

    func search(_ query: String) async throws -> [CatalogBook] {
        guard var components = URLComponents(string: searchEndpoint),
              components.scheme == "https" else { throw ReaderError.invalidCatalogURL }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: queryParameter, value: query.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        guard let url = components.url else { throw ReaderError.invalidCatalogURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/atom+xml, application/xml;q=0.9", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              data.count < 5_000_000 else { throw ReaderError.invalidCatalogURL }
        let delegate = OPDSFeedParser(baseURL: url)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? ReaderError.invalidCatalogURL }
        return delegate.books
    }
}

private final class OPDSFeedParser: NSObject, XMLParserDelegate {
    let baseURL: URL
    var books: [CatalogBook] = []
    private var currentEntry = false
    private var inAuthor = false
    private var currentField = ""
    private var textBuffer = ""
    private var identifier = ""
    private var title = ""
    private var author = ""
    private var epubURL: URL?

    init(baseURL: URL) { self.baseURL = baseURL }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "entry" {
            currentEntry = true
            identifier = ""
            title = ""
            author = ""
            epubURL = nil
        }
        guard currentEntry else { return }
        if name == "author" { inAuthor = true }
        if name == "title" || name == "id" || (name == "name" && inAuthor) {
            currentField = name
            textBuffer = ""
        }
        if name == "link", let href = attributeDict["href"] {
            let rel = attributeDict["rel"] ?? ""
            let mime = attributeDict["type"] ?? ""
            if rel.contains("acquisition") && mime.contains("epub+zip") {
                epubURL = URL(string: href, relativeTo: baseURL)?.absoluteURL
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentEntry && !currentField.isEmpty { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if currentEntry && name == currentField {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "title": title = value
            case "id": identifier = value
            case "name": if inAuthor { author = value }
            default: break
            }
            currentField = ""
        }
        if name == "author" { inAuthor = false }
        if name == "entry" {
            if !title.isEmpty, let epubURL = epubURL, epubURL.scheme == "https" {
                books.append(CatalogBook(
                    id: identifier.isEmpty ? epubURL.absoluteString : identifier,
                    title: title,
                    author: author.isEmpty ? "Автор не указан" : author,
                    epubURL: epubURL
                ))
            }
            currentEntry = false
        }
    }
}
