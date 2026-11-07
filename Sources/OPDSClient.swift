import Foundation

/// OPDS 1.x (Atom) catalog reader. Navigation entries are kept so the UI can
/// traverse author pages and book detail pages, not just flat acquisition feeds.
struct OPDSClient {
    let searchEndpoint: String
    let queryParameter: String

    func search(_ query: String) async throws -> [CatalogBook] {
        guard var components = URLComponents(string: searchEndpoint),
              components.scheme == "https",
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReaderError.invalidCatalogURL
        }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != queryParameter } + [
            URLQueryItem(name: queryParameter, value: query.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        guard let url = components.url else { throw ReaderError.invalidCatalogURL }
        return try await browse(url)
    }

    func browse(_ url: URL) async throws -> [CatalogBook] {
        guard url.scheme == "https" else { throw ReaderError.invalidCatalogURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/atom+xml, application/xml;q=0.9", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count < 5_000_000 else { throw ReaderError.invalidCatalogURL }
        let delegate = OPDSFeedParser(baseURL: http.url ?? url)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? ReaderError.invalidCatalogURL
        }
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
    private var navigationURL: URL?
    private var coverURL: URL?
    private var summary = ""
    private var downloadFormat: String?

    init(baseURL: URL) { self.baseURL = baseURL }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "entry" {
            currentEntry = true
            inAuthor = false
            identifier = ""
            title = ""
            author = ""
            epubURL = nil
            navigationURL = nil
            coverURL = nil
            summary = ""
            downloadFormat = nil
        }
        guard currentEntry else { return }
        if name == "author" { inAuthor = true }
        if name == "title" || name == "id" || name == "summary" || name == "content" || (name == "name" && inAuthor) {
            currentField = name
            textBuffer = ""
        }
        if name == "link", let href = attributeDict["href"],
           let linkURL = URL(string: href, relativeTo: baseURL)?.absoluteURL,
           linkURL.scheme == "https" {
            let rel = attributeDict["rel"] ?? ""
            let mime = (attributeDict["type"] ?? "").lowercased()
            if (rel.contains("image") || rel == "x-stanza-cover-image" || rel == "x-stanza-cover-image-thumbnail"), mime.hasPrefix("image/") {
                if coverURL == nil { coverURL = linkURL }
            } else if mime.contains("epub+zip") || mime.contains("application/epub")
                        || mime.contains("fb2") || mime.contains("mobipocket") {
                if epubURL == nil {
                    epubURL = linkURL
                    downloadFormat = mime.contains("fb2") ? "fb2" : (mime.contains("mobipocket") ? "mobi" : "epub")
                }
            } else if mime.contains("atom+xml")
                        && !rel.contains("facet")
                        && rel != "related"
                        && navigationURL == nil {
                navigationURL = linkURL
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
            case "summary", "content": if summary.isEmpty { summary = value }
            case "name": if inAuthor { author = value }
            default: break
            }
            currentField = ""
        }
        if name == "author" { inAuthor = false }
        if name == "entry" {
            if !title.isEmpty && (epubURL != nil || navigationURL != nil) {
                let fallbackID = (epubURL ?? navigationURL)?.absoluteString ?? title
                books.append(CatalogBook(
                    id: identifier.isEmpty ? fallbackID : identifier,
                    title: title,
                    author: author.isEmpty ? "Автор не указан" : author,
                    epubURL: epubURL,
                    navigationURL: navigationURL,
                    coverURL: coverURL,
                    summary: summary.isEmpty ? nil : summary,
                    downloadFormat: downloadFormat
                ))
            }
            currentEntry = false
        }
    }
}
