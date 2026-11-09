import Foundation

protocol BookSourceAdapter: Sendable {
    var source: SourceDescriptor { get }
    func search(_ query: String, byAuthor: Bool, onPage: CatalogSearchProgress?) async throws -> [CatalogBook]
    func detail(_ book: CatalogBook) async throws -> CatalogBook
    func browse(genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [CatalogBook]
}
extension BookSourceAdapter {
    func detail(_ book: CatalogBook) async throws -> CatalogBook { book }
    func browse(genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [CatalogBook] { [] }
    func stamp(_ books: [CatalogBook]) -> [CatalogBook] {
        books.map { entry in
            var book = entry; book.sourceID = source.id
            if book.offers == nil, let page = book.navigationURL ?? book.epubURL {
                book.offers = [BookOffer(sourceID: source.id, sourceName: source.name, pageURL: page,
                                        fileURL: book.epubURL, format: book.downloadFormat)]
            }
            return book
        }
    }
}
struct FlibustaBookSource: BookSourceAdapter {
    let source: SourceDescriptor
    func search(_ query: String, byAuthor: Bool, onPage: CatalogSearchProgress?) async throws -> [CatalogBook] {
        let result = try await CatalogProviders.search(query: query, mode: byAuthor ? "author" : "title", provider: "flibusta",
            customURL: "", customParameter: "", onResults: { await onPage?(stamp($0)) })
        return stamp(result)
    }
}
struct GutenbergBookSource: BookSourceAdapter {
    let source: SourceDescriptor
    func search(_ query: String, byAuthor: Bool, onPage: CatalogSearchProgress?) async throws -> [CatalogBook] {
        let books = try await load(search: query, genre: nil, language: nil, shelf: .popular)
        await onPage?(books); return books
    }
    func browse(genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [CatalogBook] {
        try await load(search: nil, genre: genre, language: language, shelf: shelf)
    }
    private func load(search: String?, genre: String?, language: String?, shelf: RecommendationShelf) async throws -> [CatalogBook] {
        var url = URLComponents(string: "https://gutendex.com/books/")!
        var query: [URLQueryItem] = [.init(name: "sort", value: "popular")]
        if let search { query.append(.init(name: "search", value: search)) }
        if let language, language != "all" { query.append(.init(name: "languages", value: language)) }
        if let genre, let topic = GenreTaxonomy.aliases[genre]?.first(where: { $0.range(of: "^[a-z ]+$", options: .regularExpression) != nil }) {
            query.append(.init(name: "topic", value: topic))
        }
        url.queryItems = query
        let object = try await SourceHTTPClient.shared.json(url.url!)
        return ((object["results"] as? [[String: Any]]) ?? []).compactMap { row in
            guard let number = row["id"] as? Int, let title = row["title"] as? String else { return nil }
            let formats = row["formats"] as? [String: String] ?? [:]
            let file = formats.first(where: { $0.key.hasPrefix("application/epub+zip") })?.value
            guard let file, let address = URL(string: file), address.scheme == "https" else { return nil }
            let languages = row["languages"] as? [String] ?? []
            let subjects = (row["subjects"] as? [String] ?? []) + (row["bookshelves"] as? [String] ?? [])
            let author = ((row["authors"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            let page = URL(string: "https://www.gutenberg.org/ebooks/\(number)")!
            return CatalogBook(id: "gutenberg:\(number)", title: title, author: author, epubURL: address, navigationURL: page,
                coverURL: formats["image/jpeg"].flatMap(URL.init(string:)), summary: (row["summaries"] as? [String])?.first,
                downloadFormat: "epub", sourceID: source.id, language: languages.joined(separator: " "),
                genres: GenreTaxonomy.normalize(subjects), popularity: (row["download_count"] as? NSNumber)?.doubleValue,
                popularityBasis: "Количество скачиваний в Project Gutenberg",
                offers: [BookOffer(sourceID: source.id, sourceName: source.name, pageURL: page, fileURL: address, format: "epub")])
        }
    }
}
struct ArchiveBookSource: BookSourceAdapter {
    let source: SourceDescriptor
    func search(_ query: String, byAuthor: Bool, onPage: CatalogSearchProgress?) async throws -> [CatalogBook] {
        let words = GenreTaxonomy.normalized(query).split(separator: " ").map { (byAuthor ? "creator:" : "title:") + $0 + "*" }.joined(separator: " AND ")
        let result = try await load(expression: words, genre: nil, shelf: .popular, language: nil)
        await onPage?(result); return result
    }
    func browse(genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [CatalogBook] {
        try await load(expression: nil, genre: genre, shelf: shelf, language: language)
    }
    private func load(expression: String?, genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [CatalogBook] {
        var clauses = ["mediatype:texts", "NOT access-restricted-item:true", "NOT collection:inlibrary"]
        if let expression, !expression.isEmpty { clauses.append("(" + expression + ")") }
        if let language, language != "all" { clauses.append("language:(" + (language == "ru" ? "rus OR ru OR Russian" : "eng OR en OR English") + ")") }
        if let genre, let terms = GenreTaxonomy.aliases[genre] { clauses.append("subject:(" + terms.map { "\"" + $0 + "\"" }.joined(separator: " OR ") + ")") }
        if shelf == .recent {
            let year = Calendar.current.component(.year, from: Date()); clauses.append("year:[\(year-1) TO \(year)]")
        }
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [.init(name: "q", value: clauses.joined(separator: " AND ")),
            .init(name: "output", value: "json"), .init(name: "rows", value: "60"),
            .init(name: "sort[]", value: shelf == .recent ? "year desc" : "downloads desc")]
        for field in ["identifier", "title", "creator", "language", "subject", "year", "date", "downloads", "description"] {
            components.queryItems!.append(.init(name: "fl[]", value: field))
        }
        let object = try await SourceHTTPClient.shared.json(components.url!)
        return (((object["response"] as? [String: Any])?["docs"] as? [[String: Any]]) ?? []).compactMap { row in
            guard let id = row["identifier"] as? String, let title = row["title"] as? String,
                  let page = URL(string: "https://archive.org/details/")?.appendingPathComponent(id) else { return nil }
            let subjects = row["subject"] as? [String] ?? HTMLSourceParser.scalar(row["subject"]).map { [$0] } ?? []
            return CatalogBook(id: "archive-book:" + id, title: title, author: HTMLSourceParser.scalar(row["creator"]) ?? "Неизвестный автор",
                epubURL: nil, navigationURL: page, coverURL: URL(string: "https://archive.org/services/img/")?.appendingPathComponent(id),
                summary: HTMLSourceParser.scalar(row["description"]), sourceID: source.id,
                language: (row["language"] as? [String])?.joined(separator: " ") ?? HTMLSourceParser.scalar(row["language"]),
                genres: GenreTaxonomy.normalize(subjects), publicationDate: HTMLSourceParser.scalar(row["date"] ?? row["year"]),
                popularity: (row["downloads"] as? NSNumber)?.doubleValue, popularityBasis: "Количество скачиваний в Internet Archive",
                offers: [BookOffer(sourceID: source.id, sourceName: source.name, pageURL: page)])
        }
    }
    func detail(_ book: CatalogBook) async throws -> CatalogBook {
        let id = String(book.id.dropFirst("archive-book:".count))
        let metadataURL = URL(string: "https://archive.org/metadata/")!.appendingPathComponent(id)
        let object = try await SourceHTTPClient.shared.json(metadataURL)
        let metadata = object["metadata"] as? [String: Any] ?? [:]
        guard HTMLSourceParser.scalar(metadata["access-restricted-item"]) != "true" else { return book }
        var result = book; var offers: [BookOffer] = []
        for file in object["files"] as? [[String: Any]] ?? [] {
            guard let name = file["name"] as? String, HTMLSourceParser.scalar(file["private"]) != "true",
                  let ext = ["epub", "fb2", "mobi", "pdf", "txt"].first(where: { name.lowercased().hasSuffix("." + $0) }),
                  let page = book.navigationURL else { continue }
            let url = URL(string: "https://archive.org/download/")!.appendingPathComponent(id).appendingPathComponent(name)
            offers.append(BookOffer(sourceID: source.id, sourceName: source.name, pageURL: page, fileURL: url, format: ext))
        }
        let priority = ["epub", "fb2", "mobi", "pdf", "txt"]
        offers.sort { (priority.firstIndex(of: $0.format ?? "") ?? 99) < (priority.firstIndex(of: $1.format ?? "") ?? 99) }
        if !offers.isEmpty { result.offers = offers; result.epubURL = offers.first?.fileURL; result.downloadFormat = offers.first?.format }
        return result
    }
}
struct HTMLBookSource: BookSourceAdapter {
    let source: SourceDescriptor
    func search(_ query: String, byAuthor: Bool, onPage: CatalogSearchProgress?) async throws -> [CatalogBook] {
        let homepage = try await SourceHTTPClient.shared.load(source.homepage)
        let document = try HTMLSourceParser.document(homepage)
        guard let form = try HTMLSourceParser.searchForm(document, base: homepage.url) ?? source.searchConfiguration else { throw SourceError.noSearch }
        let response = try await SourceHTTPClient.shared.load(form.request(query))
        let links = try HTMLSourceParser.bookLinks(HTMLSourceParser.document(response), base: response.url)
        var found: [CatalogBook] = []
        // Bounded detail hydration. Emit every successfully parsed card immediately.
        for (url, title) in links.prefix(20) {
            try Task.checkCancellation()
            do {
                let page = try await SourceHTTPClient.shared.load(url)
                let book = try HTMLSourceParser.book(HTMLSourceParser.document(page), url: page.url, source: source, fallbackTitle: title)
                if byAuthor, !GenreTaxonomy.normalized(book.author).contains(GenreTaxonomy.normalized(query)) { continue }
                found.append(book); await onPage?(found)
            } catch is CancellationError { throw CancellationError() } catch { continue }
        }
        return found
    }
    func detail(_ book: CatalogBook) async throws -> CatalogBook {
        guard let url = book.navigationURL else { return book }
        let page = try await SourceHTTPClient.shared.load(url)
        return try HTMLSourceParser.book(HTMLSourceParser.document(page), url: page.url, source: source, fallbackTitle: book.title)
    }
}
enum BookSourceFactory {
    static func adapter(_ source: SourceDescriptor) -> any BookSourceAdapter {
        switch source.adapter {
        case .flibusta: return FlibustaBookSource(source: source)
        case .gutenberg: return GutenbergBookSource(source: source)
        case .archiveBooks: return ArchiveBookSource(source: source)
        default: return HTMLBookSource(source: source)
        }
    }
}
