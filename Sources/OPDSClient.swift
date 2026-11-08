import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

typealias CatalogSearchProgress = @Sendable ([CatalogBook]) async -> Void

/// OPDS 1.x (Atom) catalog reader. Navigation entries are kept so the UI can
/// traverse author pages and book detail pages, not just flat acquisition feeds.
struct OPDSClient {
    let searchEndpoint: String
    let queryParameter: String
    var session: URLSession = .shared

    func search(_ query: String, onPage: CatalogSearchProgress? = nil) async throws -> [CatalogBook] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, let endpoint = URL(string: searchEndpoint),
              ["http", "https"].contains(endpoint.scheme ?? "") else { throw ReaderError.invalidCatalogURL }
        var template: String?
        if endpoint.query == nil && !endpoint.path.contains("search") {
            let (data, base) = try await fetch(endpoint)
            let feed = try Self.parse(data, baseURL: base)
            template = feed.searchTemplate
            if let template, !template.contains("{searchTerms"),
               let descriptionURL = URL(string: template, relativeTo: base)?.absoluteURL {
                let (xml, _) = try await fetch(descriptionURL)
                let description = OpenSearchParser()
                let parser = XMLParser(data: xml)
                parser.shouldResolveExternalEntities = false
                parser.delegate = description
                guard parser.parse() else { throw ReaderError.invalidCatalogURL }
                if let discovered = description.template { return try await searchTemplate(discovered, query: term, base: descriptionURL, onPage: onPage) }
            } else if let template { return try await searchTemplate(template, query: term, base: base, onPage: onPage) }
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true) else { throw ReaderError.invalidCatalogURL }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != queryParameter } +
            [URLQueryItem(name: queryParameter.isEmpty ? "searchTerm" : queryParameter, value: term)]
        return try await browse(components.url!, maxPages: 5, onPage: onPage)
    }

    private func searchTemplate(_ template: String, query: String, base: URL, onPage: CatalogSearchProgress?) async throws -> [CatalogBook] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let expanded = template.replacingOccurrences(of: "{searchTerms}", with: encoded)
            .replacingOccurrences(of: "{searchTerms?}", with: encoded)
            .replacingOccurrences(of: "\\{[^}]+\\?\\}", with: "", options: .regularExpression)
        guard !expanded.contains("{"), let url = URL(string: expanded, relativeTo: base)?.absoluteURL else {
            throw ReaderError.invalidCatalogURL
        }
        return try await browse(url, maxPages: 5, onPage: onPage)
    }

    func browse(_ url: URL, maxPages: Int = 1, onPage: CatalogSearchProgress? = nil) async throws -> [CatalogBook] {
        var next: URL? = url
        var visited = Set<URL>()
        var seen = Set<String>()
        var books: [CatalogBook] = []
        for _ in 0..<max(1, min(10, maxPages)) {
            try Task.checkCancellation()
            guard let current = next, visited.insert(current).inserted else { break }
            do {
                let (data, base) = try await fetch(current)
                let feed = try Self.parse(data, baseURL: base)
                for book in feed.books where seen.insert(book.id).inserted { books.append(book) }
                if !books.isEmpty { await onPage?(Array(books.prefix(200))) }
                next = feed.nextURL
                if books.count >= 200 { break }
            } catch is CancellationError { throw CancellationError() }
            catch { if books.isEmpty { throw error }; break }
        }
        return Array(books.prefix(200))
    }

    private func fetch(_ url: URL) async throws -> (Data, URL) {
        guard ["http", "https"].contains(url.scheme ?? "") else { throw ReaderError.invalidCatalogURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/atom+xml, application/opensearchdescription+xml, application/xml;q=0.9", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 5_000_000 else { throw ReaderError.invalidCatalogURL }
        return (data, http.url ?? url)
    }

    static func parse(_ data: Data, baseURL: URL) throws -> OPDSFeedParser {
        let delegate = OPDSFeedParser(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.isAtom else { throw ReaderError.invalidCatalogURL }
        return delegate
    }
}

final class OPDSFeedParser: NSObject, XMLParserDelegate {
    let baseURL: URL
    var books: [CatalogBook] = []
    var searchTemplate: String?
    var nextURL: URL?
    var isAtom = false
    private var feedBase: URL?
    private var entryBase: URL?

    private var currentEntry = false
    private var inAuthor = false
    private var currentField = ""
    private var textBuffer = ""
    private var identifier = ""
    private var title = ""
    private var author = ""
    private var epubURL: URL?
    private var audioURL:URL?
    private var navigationURL: URL?
    private var coverURL: URL?
    private var summary = ""
    private var downloadFormat: String?

    init(baseURL: URL) { self.baseURL = baseURL }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "feed" || name == "entry" { isAtom = true }
        if name == "feed", let xmlBase = attributeDict["xml:base"] { feedBase = URL(string: xmlBase, relativeTo: baseURL)?.absoluteURL }
        if name == "link", !currentEntry, attributeDict["rel"] == "search", let href = attributeDict["href"] {
            searchTemplate = href
        }
        if name == "link", !currentEntry, attributeDict["rel"] == "next", let href = attributeDict["href"],
           let url = URL(string: href, relativeTo: feedBase ?? baseURL)?.absoluteURL,
           ["http", "https"].contains(url.scheme ?? "") { nextURL = url }
        if name == "entry" {
            entryBase = attributeDict["xml:base"].flatMap { URL(string: $0, relativeTo: feedBase ?? baseURL)?.absoluteURL } ?? feedBase ?? baseURL
            currentEntry = true
            inAuthor = false
            identifier = ""
            title = ""
            author = ""
            epubURL = nil
            audioURL=nil
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
           let linkURL = URL(string: href, relativeTo: entryBase ?? feedBase ?? baseURL)?.absoluteURL,
           ["http", "https"].contains(linkURL.scheme ?? "") {
            let rel = attributeDict["rel"] ?? ""
            let mime = (attributeDict["type"] ?? "").lowercased()
            guard !["buy", "borrow", "sample", "subscribe"].contains(where: { rel.hasSuffix("/" + $0) }) else { return }
            if (rel.contains("image") || rel == "x-stanza-cover-image" || rel == "x-stanza-cover-image-thumbnail"), mime.hasPrefix("image/") {
                if coverURL == nil { coverURL = linkURL }
            } else if mime.hasPrefix("audio/") && (rel.contains("acquisition") || rel == "http://opds-spec.org/acquisition/open-access" || rel == "enclosure") {
                if audioURL == nil {audioURL=linkURL}
            } else if mime.contains("epub+zip") || mime.contains("application/epub")
                        || mime.contains("fb2") || mime.contains("fictionbook") || mime.contains("mobipocket") {
                if epubURL == nil {
                    epubURL = linkURL
                    downloadFormat = (mime.contains("fb2") || mime.contains("fictionbook")) ? (mime.contains("zip") ? "zip" : "fb2") : (mime.contains("mobipocket") ? "mobi" : "epub")
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
            if !title.isEmpty && (epubURL != nil || navigationURL != nil || audioURL != nil) {
                let fallbackID = (epubURL ?? audioURL ?? navigationURL)?.absoluteString ?? title
                books.append(CatalogBook(
                    id: identifier.isEmpty ? fallbackID : identifier,
                    title: title,
                    author: author.isEmpty ? "Автор не указан" : author,
                    epubURL: epubURL,
                    navigationURL: navigationURL,
                    coverURL: coverURL,
                    summary: summary.isEmpty ? nil : summary,
                    downloadFormat: downloadFormat,audioURL:audioURL
                ))
            }
            currentEntry = false
        }
    }
}

private final class OpenSearchParser: NSObject, XMLParserDelegate {
    var template: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "Url", attributes["type"]?.contains("atom+xml") == true { template = attributes["template"] }
    }
}
