import Foundation
import SwiftSoup

enum SourceRegressionChecks {
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        guard value() else { fatalError("FAIL: " + label) }
        print("PASS: " + label)
    }
    static func run() async throws {
        let suite = "source-tests-" + UUID().uuidString
        let settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        let library = Data("library and bookmarks must survive".utf8)
        settings.set(library, forKey: "library.fixture")
        settings.set("bookmark", forKey: "reader.savedPosition")
        for key in SourcePreferences.legacyKeys { settings.set("legacy user catalog", forKey: key) }
        SourcePreferences.migrate(settings)
        SourcePreferences.migrate(settings)
        check(SourcePreferences.legacyKeys.allSatisfy { settings.object(forKey: $0) == nil }, "migration deletes all legacy user OPDS settings idempotently")
        check(settings.data(forKey: "library.fixture") == library && settings.string(forKey: "reader.savedPosition") == "bookmark", "source migration preserves library and positions")
        let source = SourceCatalog.source("books:flibusta.is")!
        SourcePreferences.set(source, enabled: true, defaults: settings)
        let failure = SourceHealthResult(state: .unverified, checkedAt: Date(), domainReachable: false, searchSucceeded: false,
            detailSucceeded: false, downloadSucceeded: false, playbackSucceeded: false, message: "offline")
        SourcePreferences.saveHealth(failure, source: source, defaults: settings)
        check(SourcePreferences.enabled(.books, defaults: settings).contains(source), "failed health check never disables a source")
        SourcePreferences.set(source, enabled: false, defaults: settings)
        check(!SourcePreferences.enabled(.books, defaults: settings).contains(source), "explicit source switch takes effect")
        check(Set(SourceCatalog.all.map(\.id)).count == SourceCatalog.all.count && SourceCatalog.all.count >= 54, "all specified book and audio domains have independent identities")
        check(SearchQueryPolicy.matches(title: "Любовь и дружба", author: "Автор", query: "любовь", byAuthor: false), "literal title query matches relevant work")
        check(!SearchQueryPolicy.matches(title: "Война и мир", author: "Толстой", query: "любовь", byAuthor: false), "sidebar books are excluded from search")
        check(SearchQueryPolicy.matchesSearchLanguage(nil, requested: "ru"), "search retains unknown-language metadata without inventing Russian")
        check(!GenreTaxonomy.matchesLanguage(nil, requested: "ru"), "recommendations require verified language")
        check(GenreTaxonomy.matchesLanguage("ru en", requested: "en"), "bilingual edition matches both declared languages")
        check(GenreTaxonomy.normalize(["Fantasy fiction", "Magic", "Wizards"]) == ["fantasy"], "Harry Potter subject metadata cannot become History")
        check(GenreTaxonomy.normalize(["Great Britain -- History -- Fiction"]) == ["historical_fiction"], "historical fiction differs from historical nonfiction")
        check(GenreTaxonomy.normalize(["Science fiction -- History and criticism"]).isEmpty, "literary criticism is not mislabeled as science fiction")
        check(GenreTaxonomy.normalize(["Science fiction and fantasy"]).isEmpty, "broad mixed categories cannot interchange science fiction and fantasy")
        let contexts: [(String, [String])] = [
            ("history", ["History", "История"]), ("fantasy", ["Fantasy fiction", "Фэнтези"]),
            ("science_fiction", ["Science fiction", "Научная фантастика"]), ("detective", ["Mystery", "Детективы"]),
            ("romance", ["Romance fiction", "Любовные романы"]), ("biography", ["Biography", "Мемуары"]),
            ("psychology", ["Psychology", "Психология"]), ("business", ["Business", "Экономика"]),
            ("adventure", ["Adventure stories", "Приключения"]), ("children", ["Juvenile fiction", "Детская литература"])
        ]
        // A deterministic classification matrix, explicitly not a live 200-work audit.
        for (genre, subjects) in contexts {
            var books: [CatalogBook] = []
            for i in 0..<20 {
                books.append(CatalogBook(id: "\(genre)-\(i)", title: "Fixture \(i)", author: "Author \(i)", epubURL: nil,
                    language: i % 2 == 0 ? "English" : "en", genres: GenreTaxonomy.normalize([subjects[i % subjects.count]])))
            }
            let result = RecommendationEngine.rank(books, context: RecommendationContext(genres: [genre], language: "en"), shelf: .genre)
            check(result.count == 20 && result.allSatisfy { $0.genres?.contains(genre) == true && $0.recommendationReason != nil }, "20 classification cases for " + genre)
        }
        var a = CatalogBook(id: "a", title: "A History", author: "Austen", epubURL: URL(string: "https://example.org/a.epub"), language: "en", genres: ["history"], publicationDate: "2018")
        var b = a; b.id = "b"; b.title = "A Fantasy"; b.author = "Shelley"; b.genres = ["fantasy"]
        let multiple = RecommendationEngine.rank([a, b], context: RecommendationContext(genres: ["history", "fantasy"], language: "en"), shelf: .personalized)
        check(multiple.count == 2, "new user sees all selected genres with explainable reasons")
        check(RecommendationEngine.rank([a, b], context: RecommendationContext(genres: ["fantasy"], language: "en"), shelf: .personalized).map(\.id) == ["b"], "changing interests does not preserve stale genres")
        check(RecommendationEngine.rank([a, b], context: RecommendationContext(genres: ["history"], excludedTitles: ["a history"], language: "en"), shelf: .personalized).isEmpty, "read or already added books are excluded")
        check(RecommendationEngine.rank([a], context: RecommendationContext(genres: ["history"], language: "ru"), shelf: .personalized).isEmpty, "changing language removes mismatching editions")
        check(RecommendationEngine.rank([a], context: RecommendationContext(genres: [], language: "en"), shelf: .recent).isEmpty, "old works are not new because they were recently crawled")
        a.publicationDate = String(Calendar.current.component(.year, from: Date()))
        check(RecommendationEngine.rank([a], context: RecommendationContext(genres: [], language: "en"), shelf: .recent).count == 1, "actual recent edition date permits Recent")
        check(RecommendationEngine.rank([a], context: RecommendationContext(genres: [], language: "en"), shelf: .popular).isEmpty, "missing popularity data never produces a fabricated ranking")
        a.popularity = 500; a.popularityBasis = "Recorded downloads"
        check(RecommendationEngine.rank([a], context: RecommendationContext(genres: [], language: "en"), shelf: .popular).count == 1, "recorded popularity has an explicit basis")
        var duplicate = a; duplicate.id = "another-source"; duplicate.coverURL = URL(string: "https://example.org/cover.jpg")
        a.offers = [BookOffer(sourceID: "one", sourceName: "One", pageURL: a.epubURL!, fileURL: a.epubURL, format: "epub")]
        duplicate.offers = [BookOffer(sourceID: "two", sourceName: "Two", pageURL: URL(string: "https://example.org/b")!, format: "fb2")]
        check(EditionIdentity.isbn("0-14-143951-3") == EditionIdentity.isbn("9780141439518"), "ISBN-10 and ISBN-13 checksums identify the same edition")
        check(EditionIdentity.isbn("9780141439510") == nil, "invalid ISBN check digit cannot merge unrelated editions")
        let merged = EditionIdentity.mergeBooks([a, duplicate], query: "History", byAuthor: false, language: "en")
        check(merged.count == 1 && merged[0].offers?.count == 2 && merged[0].coverURL != nil, "duplicate edition combines source offers and complementary metadata")
        duplicate.publicationDate = "2000"
        check(EditionIdentity.mergeBooks([a, duplicate], query: "", byAuthor: false, language: "en").count == 2, "different book edition years remain distinct")
        let html = #"""
        <html><head><script type="application/ld+json">{"@type":"Audiobook","name":"Желтое лицо","author":[{"name":"Дойл Артур Конан"}],"inLanguage":"ru","duration":"PT52M","datePublished":"2009","readBy":[{"name":"Василевский Пётр"}]}</script></head>
        <body><script id="player-data" type="application/json">{"chapterBase":"https://aknigi24.com/book/31554/chapter/","chapters":[{"n":1,"d":1456},{"n":2,"d":1664}]}</script>
        <a href="/book/zeltoe-lico#comments">Желтое лицо</a><a href="/book/zeltoe-lico">Желтое лицо</a></body></html>
        """#
        let base = URL(string: "https://aknigi24.com/book/zeltoe-lico")!
        let doc = try SwiftSoup.parse(html, base.absoluteString)
        let parsed = try HTMLSourceParser.book(doc, url: base, source: SourceCatalog.source("audio:aknigi24.com")!)
        let tracks = try HTMLSourceParser.chapters(doc, base: base)
        check(parsed.title == "Желтое лицо" && parsed.author == "Дойл Артур Конан" && parsed.language == "ru" && parsed.narrator == "Василевский Пётр" && parsed.durationSeconds == 3120, "real Aknigi24 structured metadata retains author array and language")
        check(tracks.count == 2 && tracks[0].durationSeconds == 1456 && tracks[1].url.path == "/book/31554/chapter/2", "ordinary player data retains chapter order, durations and actual route")
        let canonicalLinks = try HTMLSourceParser.bookLinks(doc, base: base)
        check(canonicalLinks.count == 1, "URL fragments do not create duplicate work cards")
        check(HTMLSourceParser.duration("PT2H15M30S") == 8130, "ISO audio duration is parsed without date assumptions")
        RecommendationProfile.record(title: "Audio", author: "Audio author", weight: 3, genre: "history", kind: .audio, defaults: settings)
        RecommendationProfile.record(title: "Book", author: "Book author", weight: 3, genre: "fantasy", kind: .books, defaults: settings)
        check(RecommendationProfile.genres([], kind: .audio, defaults: settings) == ["history"] && RecommendationProfile.genres([], kind: .books, defaults: settings) == ["fantasy"], "reading and listening histories do not leak across preferences")
        let gate = MediaTransferGate(limit: 1)
        let firstPermit = try await gate.acquire()
        let waiting = Task { try await gate.acquire() }
        try await Task.sleep(nanoseconds: 5_000_000)
        waiting.cancel()
        do { _ = try await waiting.value; fatalError("cancelled transfer kept a queue slot") }
        catch is CancellationError { print("PASS: cancellation removes a waiting shared transfer") }
        await gate.release(firstPermit)
        let nextPermit = try await gate.acquire()
        await gate.release(nextPermit)
        check(true, "shared transfer budget releases slots after cancellation")
        try await asynchronousSearchChecks()
    }
    static func asynchronousSearchChecks() async throws {
        let recorder = SearchProbeRecorder()
        let adapters: [any BookSourceAdapter] = (0..<7).map { MockBookSource(index: $0, recorder: recorder) }
        let started = Date()
        let result = try await UnifiedSearchService.books(query: "History", byAuthor: false, language: "en", onResults: { update in
            await recorder.saw(update, elapsed: Date().timeIntervalSince(started))
        }, adapters: adapters)
        let state = await recorder.snapshot()
        check(state.maximum <= 4 && state.maximum > 1, "unified search is concurrent with a four-source limit")
        check(state.firstResult < 0.15 && result.count == 6, "fast results appear before slow sources finish; one failure preserves other results")
        check(state.failed.contains("mock:6"), "individual source failure is reported")
        let task = Task { try await UnifiedSearchService.books(query: "Cancel", byAuthor: false, language: "en", adapters: adapters) }
        try await Task.sleep(nanoseconds: 5_000_000)
        task.cancel()
        do { _ = try await task.value; fatalError("cancellation ignored") }
        catch is CancellationError { print("PASS: previous search cancellation stops outstanding source work") }
    }
}
private actor SearchProbeRecorder {
    var active = 0; var maximum = 0; var firstResult = Double.infinity; var failed = Set<String>()
    func enter() { active += 1; maximum = max(maximum, active) }
    func leave() { active -= 1 }
    func saw(_ update: UnifiedBookUpdate, elapsed: Double) {
        if !update.books.isEmpty { firstResult = min(firstResult, elapsed) }
        failed.formUnion(update.failed)
    }
    func snapshot() -> (maximum: Int, firstResult: Double, failed: Set<String>) { (maximum, firstResult, failed) }
}
private struct MockBookSource: BookSourceAdapter {
    let index: Int
    let recorder: SearchProbeRecorder
    var source: SourceDescriptor { SourceDescriptor(id: "mock:\(index)", name: "Mock", domain: "example.org", kind: .books, adapter: .html, defaultEnabled: false) }
    func search(_ query: String, byAuthor: Bool, onPage: CatalogSearchProgress?) async throws -> [CatalogBook] {
        await recorder.enter()
        do {
            try await Task.sleep(nanoseconds: index == 0 ? 10_000_000 : 200_000_000)
            try Task.checkCancellation()
            if index == 6 { throw SourceError.unavailable }
            let books = [CatalogBook(id: source.id, title: "History \(index)", author: "Author \(index)", epubURL: nil, language: "en")]
            await onPage?(books); await recorder.leave(); return books
        } catch { await recorder.leave(); throw error }
    }
}
