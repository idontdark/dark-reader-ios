import Foundation

struct UnifiedBookUpdate: Sendable { let sequence: Int; let books: [CatalogBook]; let completed: Int; let total: Int; let failed: [String] }
struct UnifiedAudioUpdate: Sendable { let sequence: Int; let books: [AudioBook]; let completed: Int; let total: Int; let failed: [String] }
typealias UnifiedBookProgress = @Sendable (UnifiedBookUpdate) async -> Void
typealias UnifiedAudioProgress = @Sendable (UnifiedAudioUpdate) async -> Void

enum EditionIdentity {
    static func book(_ book: CatalogBook) -> String {
        let language = GenreTaxonomy.language(book.language) ?? "unknown"
        if let isbn = book.isbn?.filter({ $0.isNumber || $0 == "X" }), [10, 13].contains(isbn.count) { return "isbn:" + isbn + ":" + language }
        // Unknown author must not merge unrelated editions with the same title.
        let author = GenreTaxonomy.normalized(book.author)
        if author.isEmpty || ["неизвестный автор", "автор не указан"].contains(author) { return book.id }
        return [GenreTaxonomy.normalized(book.title), author, language, PublicationDate.year(book.publicationDate).map(String.init) ?? "undated"].joined(separator: ":")
    }
    static func audioWork(_ book: AudioBook) -> String {
        let author = GenreTaxonomy.normalized(book.author)
        guard !author.isEmpty, author != "неизвестный автор" else { return book.id }
        return [GenreTaxonomy.normalized(book.title), author, GenreTaxonomy.language(book.language) ?? "unknown"].joined(separator: ":")
    }
    static func mergeBooks(_ entries: [CatalogBook], query: String, byAuthor: Bool, language: String?) -> [CatalogBook] {
        var values: [String: CatalogBook] = [:]; var order: [String] = []
        for book in entries where GenreTaxonomy.matchesLanguage(book.language, requested: language) {
            let key = self.book(book)
            if var existing = values[key] {
                var seen = Set<String>()
                existing.offers = ((existing.offers ?? []) + (book.offers ?? [])).filter { seen.insert($0.id).inserted }
                if existing.coverURL == nil { existing.coverURL = book.coverURL }
                if existing.summary?.isEmpty != false { existing.summary = book.summary }
                if existing.epubURL == nil { existing.epubURL = book.epubURL; existing.downloadFormat = book.downloadFormat }
                existing.genres = Array(Set((existing.genres ?? []) + (book.genres ?? []))).sorted()
                values[key] = existing
            } else { values[key] = book; order.append(key) }
        }
        return order.compactMap { values[$0] }.enumerated().sorted {
            let a = SearchQueryPolicy.score(title: $0.element.title, author: $0.element.author, query: query, byAuthor: byAuthor)
            let b = SearchQueryPolicy.score(title: $1.element.title, author: $1.element.author, query: query, byAuthor: byAuthor)
            return a == b ? $0.offset < $1.offset : a > b
        }.map(\.element)
    }
}
private actor UnifiedBookAccumulator {
    var entries: [String: CatalogBook] = [:]
    var failed: [String] = []; var completed = 0; var sequence = 0
    let total: Int; let query: String; let byAuthor: Bool; let language: String?
    init(total: Int, query: String, byAuthor: Bool, language: String?) { self.total = total; self.query = query; self.byAuthor = byAuthor; self.language = language }
    func merge(_ books: [CatalogBook], finished: Bool = false, failure: String? = nil) -> UnifiedBookUpdate {
        for book in books { entries[book.id] = book }
        if finished { completed += 1 }; if let failure { failed.append(failure) }; sequence += 1
        return UnifiedBookUpdate(sequence: sequence, books: EditionIdentity.mergeBooks(Array(entries.values).sorted { $0.id < $1.id }, query: query, byAuthor: byAuthor, language: language), completed: completed, total: total, failed: failed)
    }
}
enum UnifiedSearchService {
    static func books(query: String, byAuthor: Bool, language: String?, sources explicit: [SourceDescriptor]? = nil,
                      onResults: UnifiedBookProgress? = nil) async throws -> [CatalogBook] {
        if explicit == nil { SearchHistory.record(query, kind: .books) }
        let sources = explicit ?? SourcePreferences.enabled(.books)
        guard !sources.isEmpty else { throw SourceError.noEnabledSources }
        let accumulator = UnifiedBookAccumulator(total: sources.count, query: query, byAuthor: byAuthor, language: language)
        var iterator = sources.makeIterator()
        return try await withThrowingTaskGroup(of: Void.self) { group in
            func add(_ source: SourceDescriptor) {
                group.addTask {
                    do {
                        let books = try await BookSourceFactory.adapter(source).search(query, byAuthor: byAuthor, onPage: { page in
                            try? Task.checkCancellation()
                            guard !Task.isCancelled else { return }
                            let update = await accumulator.merge(page)
                            await onResults?(update)
                        })
                        try Task.checkCancellation()
                        await onResults?(await accumulator.merge(books, finished: true))
                    } catch is CancellationError { throw CancellationError() }
                    catch { await onResults?(await accumulator.merge([], finished: true, failure: source.id)) }
                }
            }
            for _ in 0..<min(4, sources.count) { if let source = iterator.next() { add(source) } }
            while let _ = try await group.next() {
                try Task.checkCancellation()
                if let source = iterator.next() { add(source) }
            }
            try Task.checkCancellation()
            return await accumulator.merge([]).books
        }
    }
    static func detail(_ book: CatalogBook) async throws -> CatalogBook {
        guard let id = book.sourceID, let source = SourceCatalog.source(id) else { return book }
        var result = try await BookSourceFactory.adapter(source).detail(book)
        var seen = Set<String>()
        result.offers = ((result.offers ?? []) + (book.offers ?? [])).filter { seen.insert($0.id).inserted }
        return result
    }
}

enum SearchHistory {
    static func record(_ query: String, kind: SourceKind, defaults: UserDefaults = .standard) {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let key = "search.history." + kind.rawValue
        var values = defaults.stringArray(forKey: key) ?? []
        values.removeAll { GenreTaxonomy.normalized($0) == GenreTaxonomy.normalized(value) }
        values.insert(value, at: 0)
        defaults.set(Array(values.prefix(50)), forKey: key)
    }
}
