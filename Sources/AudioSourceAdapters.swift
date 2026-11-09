import Foundation

typealias AudioSearchProgress = @Sendable ([AudioBook]) async -> Void
protocol AudiobookSourceAdapter: Sendable {
    var source: SourceDescriptor { get }
    func search(_ query: String, byAuthor: Bool, onPage: AudioSearchProgress?) async throws -> [AudioBook]
    func detail(_ book: AudioBook) async throws -> AudioBook
    func searchNarrator(_ query: String, onPage: AudioSearchProgress?) async throws -> [AudioBook]
    func chapters(_ book: AudioBook) async throws -> [AudioChapter]
    func browse(genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [AudioBook]
}
extension AudiobookSourceAdapter {
    func searchNarrator(_ query: String, onPage: AudioSearchProgress?) async throws -> [AudioBook] {
        let books = try await search(query, byAuthor: false, onPage: nil)
        let found = books.filter { SearchQueryPolicy.matches(title: "", author: $0.narrator ?? "", query: query, byAuthor: true) }
        await onPage?(found); return found
    }
    func detail(_ book: AudioBook) async throws -> AudioBook { book }
    func browse(genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [AudioBook] { [] }
    func stamp(_ books: [AudioBook]) -> [AudioBook] {
        books.map { value in
            var book = value; book.providerID = source.id
            if book.pageURL == nil {
                if [.knigavuhe, .akniga].contains(book.source) { book.pageURL = book.feedURL ?? URL(string: book.sourceID) }
                else if book.source == .archive { book.pageURL = URL(string: "https://archive.org/details/")!.appendingPathComponent(book.sourceID) }
            }
            return book
        }
    }
}
struct NativeAudiobookSource: AudiobookSourceAdapter {
    let source: SourceDescriptor
    private var native: AudioSource {
        switch source.adapter { case .librivox: .librivox; case .knigavuhe: .knigavuhe; case .akniga: .akniga; default: .archive }
    }
    func search(_ query: String, byAuthor: Bool, onPage: AudioSearchProgress?) async throws -> [AudioBook] {
        let raw = try await AudioCatalogService.search(source: native, query: query, byAuthor: byAuthor, language: nil, onPage: { await onPage?(stamp($0)) })
        let books = try await hydrate(stamp(raw), onPage: onPage)
        await onPage?(books); return books
    }
    func detail(_ book: AudioBook) async throws -> AudioBook {
        guard native == .knigavuhe || native == .akniga else { return book }
        return try await HTMLAudiobookSource(source: source).detail(book)
    }
    private func hydrate(_ books: [AudioBook], onPage: AudioSearchProgress?) async throws -> [AudioBook] {
        guard native == .knigavuhe || native == .akniga else { return books }
        var iterator = books.prefix(30).makeIterator(); var result: [AudioBook] = []
        try await withThrowingTaskGroup(of: AudioBook.self) { group in
            func add(_ book: AudioBook) {
                group.addTask {
                    do { return try await detail(book) }
                    catch is CancellationError { throw CancellationError() } catch { return book }
                }
            }
            for _ in 0..<3 { if let book = iterator.next() { add(book) } }
            while let book = try await group.next() {
                try Task.checkCancellation(); result.append(book); await onPage?(result)
                if let next = iterator.next() { add(next) }
            }
        }
        return result
    }
    func chapters(_ book: AudioBook) async throws -> [AudioChapter] { try await AudioCatalogService.chapters(for: book) }
    func browse(genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [AudioBook] {
        let raw = try await AudioCatalogService.featured(source: native, language: nil, genres: genre.map { [$0] } ?? [], newest: shelf == .recent)
        return try await hydrate(stamp(raw), onPage: nil)
    }
}
struct HTMLAudiobookSource: AudiobookSourceAdapter {
    let source: SourceDescriptor
    func search(_ query: String, byAuthor: Bool, onPage: AudioSearchProgress?) async throws -> [AudioBook] {
        let books = try await HTMLBookSource(source: source).search(query, byAuthor: byAuthor, onPage: { page in
            await onPage?(page.map { make($0) })
        })
        return books.map(make)
    }
    func searchNarrator(_ query: String, onPage: AudioSearchProgress?) async throws -> [AudioBook] {
        let books = try await HTMLBookSource(source: source).search(query, byAuthor: false, matchingNarrator: true, onPage: { await onPage?($0.map(make)) })
        return books.map(make)
    }
    private func make(_ entry: CatalogBook) -> AudioBook {
        AudioBook(id: entry.id, source: .opds, sourceID: entry.id, title: entry.title, author: entry.author,
                  description: entry.summary ?? "", coverURL: entry.coverURL, language: entry.language,
                  genres: entry.genres, feedURL: entry.navigationURL, providerID: source.id,
                  pageURL: entry.navigationURL, narrator: entry.narrator, durationSeconds: entry.durationSeconds, publicationDate: entry.publicationDate,
                  popularity: entry.popularity, popularityBasis: entry.popularityBasis,
                  series: entry.series, seriesNumber: entry.seriesNumber)
    }
    func detail(_ book: AudioBook) async throws -> AudioBook {
        guard let url = book.pageURL else { return book }
        let response = try await SourceHTTPClient.shared.load(url)
        let doc = try HTMLSourceParser.document(response)
        let metadata = try HTMLSourceParser.book(doc, url: response.url, source: source, fallbackTitle: book.title)
        // Preserve native source/track identity and stored positions during hydration.
        var result = book
        result = AudioBook(id: book.id, source: book.source, sourceID: book.sourceID,
            title: book.title, author: metadata.author == "Неизвестный автор" ? book.author : metadata.author,
            description: metadata.summary ?? book.description, coverURL: metadata.coverURL ?? book.coverURL,
            language: metadata.language ?? book.language, genres: metadata.genres?.isEmpty == false ? metadata.genres : book.genres,
            streamURL: book.streamURL, feedURL: book.feedURL, providerID: source.id, pageURL: response.url,
            publicationDate: metadata.publicationDate, popularity: metadata.popularity, popularityBasis: metadata.popularityBasis,
            series: metadata.series, seriesNumber: metadata.seriesNumber)
        let ld = HTMLSourceParser.linkedData(doc).first { (HTMLSourceParser.scalar($0["@type"]) ?? "").localizedCaseInsensitiveContains("audiobook") } ?? [:]
        result.narrator = metadata.narrator ?? HTMLSourceParser.scalar(ld["readBy"]) ?? HTMLSourceParser.value("[itemprop=readBy], .book-reader, .book_reader", in: doc)
        result.durationSeconds = metadata.durationSeconds ?? HTMLSourceParser.duration(HTMLSourceParser.scalar(ld["duration"]))
        // Only the site's actual download anchor is accepted; routes are never guessed.
        if source.domain == "aknigi24.com" {
            for link in try doc.select("a[href]") {
                guard let address = HTMLSourceParser.url(try link.attr("href"), base: response.url),
                      address.host == response.url.host, address.path.hasSuffix("/download"),
                      address.path.hasPrefix(response.url.path + "/") else { continue }
                result.archiveURL = address; break
            }
        }
        return result
    }
    func browse(genre: String?, shelf: RecommendationShelf, language: String?) async throws -> [AudioBook] {
        try await HTMLBookSource(source: source).browse(genre: genre, shelf: shelf, language: language).map(make)
    }
    func chapters(_ book: AudioBook) async throws -> [AudioChapter] {
        guard let url = book.pageURL else { throw AudioCatalogError.noTracks }
        let response = try await SourceHTTPClient.shared.load(url)
        let tracks = try HTMLSourceParser.chapters(HTMLSourceParser.document(response), base: response.url)
        guard !tracks.isEmpty else { throw AudioCatalogError.noTracks }
        return tracks
    }
}
enum AudioSourceFactory {
    static func adapter(_ source: SourceDescriptor) -> any AudiobookSourceAdapter {
        if source.adapter == .html { return HTMLAudiobookSource(source: source) }
        return NativeAudiobookSource(source: source)
    }
}
extension AudioBook {
    var edition: AudioEdition? {
        guard let providerID, let page = pageURL ?? feedURL else { return nil }
        return AudioEdition(providerID: providerID, pageURL: page, narrator: narrator, year: PublicationDate.year(publicationDate),
                            durationSeconds: durationSeconds, nativeID: sourceID, sourceCode: source.rawValue,
                            streamURL: streamURL, feedURL: feedURL)
    }
    func selecting(_ edition: AudioEdition) -> AudioBook {
        AudioBook(id: edition.providerID + ":" + (edition.nativeID ?? edition.pageURL.absoluteString),
                  source: AudioSource(rawValue: edition.sourceCode ?? "") ?? .opds,
                  sourceID: edition.nativeID ?? edition.pageURL.absoluteString, title: title, author: author,
                  description: description, coverURL: coverURL, language: language, genres: genres,
                  streamURL: edition.streamURL, feedURL: edition.feedURL, providerID: edition.providerID,
                  pageURL: edition.pageURL, narrator: edition.narrator, durationSeconds: edition.durationSeconds,
                  publicationDate: edition.year.map(String.init), series: series, seriesNumber: seriesNumber)
    }
}
private actor UnifiedAudioAccumulator {
    var values: [String: AudioBook] = [:]; var failed: [String] = []; var completed = 0; var sequence = 0
    let total: Int; let query: String; let byAuthor: Bool; let language: String?
    init(total: Int, query: String, byAuthor: Bool, language: String?) { self.total = total; self.query = query; self.byAuthor = byAuthor; self.language = language }
    func merge(_ books: [AudioBook], finished: Bool = false, failure: String? = nil) -> UnifiedAudioUpdate {
        for book in books { values[book.id] = book }
        if finished { completed += 1 }; if let failure { failed.append(failure) }; sequence += 1
        var merged: [String: AudioBook] = [:]
        for book in values.values.sorted(by: { $0.id < $1.id }) where SearchQueryPolicy.matchesSearchLanguage(book.language, requested: language) {
            let key = EditionIdentity.audioWork(book)
            if var old = merged[key] {
                var seen = Set<String>()
                old.editions = ((old.editions ?? []) + (book.edition.map { [$0] } ?? [])).filter { seen.insert($0.id).inserted }
                merged[key] = old
            } else { var first = book; first.editions = book.edition.map { [$0] }; merged[key] = first }
        }
        let ranked = merged.values.sorted {
            let a = SearchQueryPolicy.score(title: $0.title, author: $0.author, query: query, byAuthor: byAuthor)
            let b = SearchQueryPolicy.score(title: $1.title, author: $1.author, query: query, byAuthor: byAuthor)
            return a == b ? $0.id < $1.id : a > b
        }
        return UnifiedAudioUpdate(sequence: sequence, books: ranked, completed: completed, total: total, failed: failed)
    }
}
extension UnifiedSearchService {
    static func audio(query: String, byAuthor: Bool, language: String?, byNarrator: Bool = false, sources explicit: [SourceDescriptor]? = nil,
                      onResults: UnifiedAudioProgress? = nil) async throws -> [AudioBook] {
        if explicit == nil { SearchHistory.record(query, kind: .audio) }
        let sources = explicit ?? SourcePreferences.enabled(.audio)
        guard !sources.isEmpty else { throw SourceError.noEnabledSources }
        let accumulator = UnifiedAudioAccumulator(total: sources.count, query: query, byAuthor: byAuthor, language: language)
        var iterator = sources.makeIterator()
        return try await withThrowingTaskGroup(of: Void.self) { group in
            func add(_ source: SourceDescriptor) {
                group.addTask {
                    do {
                        let adapter = AudioSourceFactory.adapter(source)
                        let progress: AudioSearchProgress = { page in
                            guard !Task.isCancelled else { return }
                            await onResults?(await accumulator.merge(page))
                        }
                        let books: [AudioBook]
                        if byNarrator { books = try await adapter.searchNarrator(query, onPage: progress) }
                        else { books = try await adapter.search(query, byAuthor: byAuthor, onPage: progress) }
                        try Task.checkCancellation()
                        await onResults?(await accumulator.merge(books, finished: true))
                    } catch is CancellationError { throw CancellationError() }
                    catch { await onResults?(await accumulator.merge([], finished: true, failure: source.id)) }
                }
            }
            for _ in 0..<min(4, sources.count) { if let source = iterator.next() { add(source) } }
            while let _ = try await group.next() { try Task.checkCancellation(); if let source = iterator.next() { add(source) } }
            try Task.checkCancellation()
            return await accumulator.merge([]).books
        }
    }
}

extension AudioBook {
    var withResolvedSource: AudioBook {
        var value = self
        if value.providerID == nil {
            let adapter: SourceAdapter?
            switch source {
            case .librivox: adapter = .librivox
            case .archive: adapter = .archiveAudio
            case .knigavuhe: adapter = .knigavuhe
            case .akniga: adapter = .akniga
            default: adapter = nil
            }
            if let adapter { value.providerID = SourceCatalog.all.first { $0.kind == .audio && $0.adapter == adapter }?.id }
        }
        if value.pageURL == nil {
            if source == .archive { value.pageURL = URL(string: "https://archive.org/details/")!.appendingPathComponent(sourceID) }
            else if source == .akniga || source == .knigavuhe { value.pageURL = feedURL }
        }
        return value
    }
}
