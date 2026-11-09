import Foundation

struct UnifiedBookUpdate: Sendable { let sequence: Int; let books: [CatalogBook]; let completed: Int; let total: Int; let failed: [String] }
struct UnifiedAudioUpdate: Sendable { let sequence: Int; let books: [AudioBook]; let completed: Int; let total: Int; let failed: [String] }
typealias UnifiedBookProgress = @Sendable (UnifiedBookUpdate) async -> Void
typealias UnifiedAudioProgress = @Sendable (UnifiedAudioUpdate) async -> Void

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
                      onResults: UnifiedBookProgress? = nil, adapters suppliedAdapters: [any BookSourceAdapter]? = nil) async throws -> [CatalogBook] {
        if explicit == nil && suppliedAdapters == nil { SearchHistory.record(query, kind: .books) }
        let sources = explicit ?? SourcePreferences.enabled(.books)
        guard !sources.isEmpty else { throw SourceError.noEnabledSources }
        let adapters = suppliedAdapters ?? sources.map { BookSourceFactory.adapter($0) }
        let accumulator = UnifiedBookAccumulator(total: adapters.count, query: query, byAuthor: byAuthor, language: language)
        var iterator = adapters.makeIterator()
        return try await withThrowingTaskGroup(of: Void.self) { group in
            func add(_ adapter: any BookSourceAdapter) {
                let source = adapter.source
                group.addTask {
                    do {
                        let books = try await adapter.search(query, byAuthor: byAuthor, onPage: { page in
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
            for _ in 0..<min(4, adapters.count) { if let source = iterator.next() { add(source) } }
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
