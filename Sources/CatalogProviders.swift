import Foundation

/// All production catalog communication is implemented in Swift.
enum CatalogProviders {
    static func search(
        query: String, mode: String, provider: String,
        customURL: String, customParameter: String,
        language: String? = nil
    ) async throws -> [CatalogBook] {
        switch provider {
        case "flibusta":
            // The live OPDS server splits title and author search into two feeds.
            let type = mode == "author" ? "authors" : "books"
            let client = OPDSClient(
                searchEndpoint: "https://flibusta.is/opds/search?searchType=\(type)",
                queryParameter: "searchTerm"
            )
            return try await client.search(query)
        case "gutendex":
            return try await GutendexClient().search(query, mode: mode, language: language)
        case "gutenberg":
            return try await OPDSClient(
                searchEndpoint: "https://www.gutenberg.org/ebooks/search.opds/",
                queryParameter: "query"
            ).search(query)
        default:
            return try await OPDSClient(
                searchEndpoint: customURL,
                queryParameter: customParameter
            ).search(query)
        }
    }

    static func recommendations(genre: String, language: String?) async throws -> [CatalogBook] {
        try await GutendexClient().recommendations(genre: genre, language: language)
    }

    static func browse(url: URL) async throws -> [CatalogBook] {
        try await OPDSClient(searchEndpoint: "", queryParameter: "").browse(url)
    }
}

/// JSON API for Project Gutenberg metadata, including direct EPUB links.
/// Gutendex is a community server and can occasionally time out.
private struct GutendexClient {
    private struct Response: Decodable {
        let results: [Book]
    }
    private struct Book: Decodable {
        let id: Int
        let title: String
        let authors: [Author]
        let formats: [String: String]
    }
    private struct Author: Decodable {
        let name: String
    }

    func recommendations(genre: String, language: String?) async throws -> [CatalogBook] {
        let topics = [
            "detective": "mystery",
            "fantasy": "science fiction",
            "romance": "romance",
            "classics": "classics",
            "adventure": "adventure",
            "history": "history",
            "biography": "biography",
            "nonfiction": "philosophy",
            "children": "children",
            "thriller": "thriller"
        ]
        let topic = topics[genre] ?? genre
        var components = URLComponents(string: "https://gutendex.com/books/")!
        components.queryItems = [URLQueryItem(name: "topic", value: topic)]
        if let language, ["ru", "en"].contains(language) {
            components.queryItems?.append(URLQueryItem(name: "languages", value: language))
        }
        guard let url = components.url else { throw ReaderError.invalidCatalogURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 16
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              data.count <= 5_000_000 else { throw ReaderError.invalidCatalogURL }
        let result = try JSONDecoder().decode(Response.self, from: data)
        return result.results.compactMap { item -> CatalogBook? in
            guard let file = item.formats.first(where: { $0.key.contains("epub") })?.value,
                  let url = URL(string: file), url.scheme == "https" else { return nil }
            return CatalogBook(
                id: "gutenberg-\(item.id)",
                title: item.title,
                author: item.authors.map(\.name).joined(separator: ", "),
                epubURL: url,
                coverURL: URL(string: "https://www.gutenberg.org/cache/epub/\(item.id)/pg\(item.id).cover.medium.jpg")
            )
        }
    }

    func search(_ query: String, mode: String, language: String?) async throws -> [CatalogBook] {
        var lastError: Error = ReaderError.invalidCatalogURL
        for attempt in 0..<2 {
            do { return try await fetch(query, mode: mode, language: language) }
            catch {
                lastError = error
                if attempt == 0 { try? await Task.sleep(nanoseconds: 400_000_000) }
            }
        }
        throw lastError
    }

    private func fetch(_ query: String, mode: String, language: String?) async throws -> [CatalogBook] {
        var components = URLComponents(string: "https://gutendex.com/books/")!
        components.queryItems = [
            URLQueryItem(name: "search", value: query.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        if let language, language == "ru" || language == "en" {
            components.queryItems?.append(URLQueryItem(name: "languages", value: language))
        }
        guard let url = components.url else { throw ReaderError.invalidCatalogURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count < 5_000_000 else { throw ReaderError.invalidCatalogURL }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let converted = decoded.results.compactMap { item -> CatalogBook? in
            guard let file = item.formats.first(where: { $0.key.lowercased().contains("epub") })?.value,
                  let epubURL = URL(string: file), epubURL.scheme == "https" else { return nil }
            return CatalogBook(
                id: "gutenberg-\(item.id)",
                title: item.title,
                author: item.authors.map(\.name).joined(separator: ", ").isEmpty
                    ? "Автор не указан" : item.authors.map(\.name).joined(separator: ", "),
                epubURL: epubURL,
                coverURL: URL(string: "https://www.gutenberg.org/cache/epub/\(item.id)/pg\(item.id).cover.medium.jpg")
            )
        }
        let filtered = converted.filter {
            (mode == "author" ? $0.author : $0.title)
                .localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Mixed scripts and transliterated names can make exact field filtering
        // empty even though the upstream full-text search returned relevant books.
        return filtered.isEmpty ? converted : filtered
    }
}
