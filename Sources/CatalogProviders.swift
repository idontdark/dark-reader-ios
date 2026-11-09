import Foundation

/// All production catalog communication is implemented in Swift.
enum CatalogProviders {
    static func search(
        query: String, mode: String, provider: String,
        customURL: String, customParameter: String,
        language: String? = nil, onResults: CatalogSearchProgress? = nil
    ) async throws -> [CatalogBook] {
        switch provider {
        case "flibusta":
            var found: [CatalogBook] = []
            var seen = Set<String>()
            var succeeded = false
            var lastError: Error?
            let progress = CatalogSearchAccumulator(query: query, byAuthor: mode == "author")
            for variant in SearchQueryPolicy.variants(query, byAuthor: mode == "author") {
                do {
                    let batch = try await FlibustaCatalog.shared.search(variant, mode: mode, onPage: { page in
                        let merged = await progress.merge(page)
                        await onResults?(merged)
                    })
                    succeeded = true
                    for book in batch where seen.insert(book.id).inserted { found.append(book) }
                    if mode == "title", batch.contains(where: { SearchQueryPolicy.score(title:$0.title,author:$0.author,query:query) == 10_000 }) { break }
                } catch is CancellationError { throw CancellationError() }
                catch { lastError = error }
            }
            if !succeeded, let lastError { throw lastError }
            return found.enumerated().sorted { left, right in
                let lhs = SearchQueryPolicy.score(title:left.element.title,author:left.element.author,query:query,byAuthor:mode == "author")
                let rhs = SearchQueryPolicy.score(title:right.element.title,author:right.element.author,query:query,byAuthor:mode == "author")
                return lhs == rhs ? left.offset < right.offset : lhs > rhs
            }.map(\.element)
        case "gutendex", "gutenberg":
            guard let source = SourceCatalog.source("books:gutenberg.org") else { throw SourceError.unavailable }
            return try await GutenbergBookSource(source: source).search(query, byAuthor: mode == "author", onPage: onResults)
        default:
            return try await OPDSClient(
                searchEndpoint: customURL,
                queryParameter: customParameter
            ).search(query, onPage: onResults)
        }
    }

    static func browse(url: URL) async throws -> [CatalogBook] {
        try await OPDSClient(searchEndpoint: "", queryParameter: "").browse(url, maxPages: 5)
    }
}

