import Foundation

enum UnifiedDiscoveryService {
    static func context(genres: [String], language: String, kind: SourceKind, defaults: UserDefaults = .standard) -> RecommendationContext {
        let authors = (defaults.string(forKey: "preferredAuthorsJSON")?.data(using: .utf8)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        var excluded = Set<String>()
        let historyKey = kind == .audio ? "audio.historyJSON" : "discovery.wishlistJSON"
        if let data = defaults.string(forKey: historyKey)?.data(using: .utf8),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for row in rows {
                guard let title = row["title"] as? String else { continue }
                if kind == .audio { excluded.insert(GenreTaxonomy.normalized(title)) }
            }
        }
        var favoriteAuthors = Set(authors.map(GenreTaxonomy.normalized))
        for key in kind == .audio ? ["audio.favoritesJSON"] : ["favoriteBooksJSON", "catalog.favoritesJSON"] {
            if let raw = defaults.string(forKey: key)?.data(using: .utf8), let favorites = try? JSONSerialization.jsonObject(with: raw) as? [[String: Any]] {
                for favorite in favorites { if let author = favorite["author"] as? String { favoriteAuthors.insert(GenreTaxonomy.normalized(author)) } }
            }
        }
        if kind == .books {
            let index = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Books/books.json")
            if let data = try? Data(contentsOf: index), let books = try? JSONDecoder().decode([LocalBook].self, from: data) {
                for book in books { excluded.insert(GenreTaxonomy.normalized(book.title)); if book.isFavorite == true { favoriteAuthors.insert(GenreTaxonomy.normalized(book.author)) } }
            }
        }
        let previous = Set(defaults.stringArray(forKey: "recommendation.previous." + kind.rawValue) ?? [])
        var context = RecommendationContext(genres: genres, authors: favoriteAuthors, excludedTitles: excluded,
                                     previousIDs: previous, language: language)
        for signal in RecommendationProfile.signals(defaults) where (signal.kind ?? .books) == kind {
            let author = GenreTaxonomy.normalized(signal.author)
            if !author.isEmpty && author != "неизвестный автор" {
                context.authors.insert(author)
                context.authorWeights[author, default: 0] += min(6, Double(signal.weight))
            }
            if let series = signal.series { context.series.insert(GenreTaxonomy.normalized(series)) }
            if signal.weight >= 3 { context.excludedTitles.insert(GenreTaxonomy.normalized(signal.title)) }
        }
        context.searches = defaults.stringArray(forKey: "search.history." + kind.rawValue) ?? []
        return context
    }
    static func books(genres: [String], language: String, shelf: RecommendationShelf, limit: Int = 24,
                      defaults: UserDefaults = .standard) async throws -> [CatalogBook] {
        let sources = SourcePreferences.enabled(.books, defaults: defaults)
        guard !sources.isEmpty else { throw SourceError.noEnabledSources }
        let selected = genres.isEmpty ? [String?](arrayLiteral: nil) : genres.map(Optional.some)
        let context = context(genres: genres, language: language, kind: .books, defaults: defaults)
        var requests = sources.flatMap { source in selected.map { (source, $0, String?.none, false) } }
        if shelf == .personalized {
            for source in sources {
                if let author = context.authors.sorted().first { requests.append((source, nil, author, true)) }
                if let query = context.searches.first { requests.append((source, nil, query, false)) }
            }
        }
        var jobs = requests.makeIterator()
        var found: [CatalogBook] = []; var succeeded = false
        try await withThrowingTaskGroup(of: [CatalogBook]?.self) { group in
            func add(_ job: (SourceDescriptor, String?, String?, Bool)) {
                group.addTask {
                    do {
                        let adapter = BookSourceFactory.adapter(job.0)
                        if let query = job.2 { return try await adapter.search(query, byAuthor: job.3, onPage: nil) }
                        return try await adapter.browse(genre: job.1, shelf: shelf, language: language)
                    }
                    catch is CancellationError { throw CancellationError() }
                    catch { return nil }
                }
            }
            for _ in 0..<4 { if let job = jobs.next() { add(job) } }
            while let result = try await group.next() {
                try Task.checkCancellation()
                if let result { found += result; succeeded = true }
                if let job = jobs.next() { add(job) }
            }
        }
        guard succeeded else { throw SourceError.unavailable }
        let merged = EditionIdentity.mergeBooks(found, query: "", byAuthor: false, language: language)
        let result = RecommendationEngine.rank(merged, context: context, shelf: shelf, limit: limit)
        if shelf == .personalized { defaults.set(result.map(\.id), forKey: "recommendation.previous.books") }
        return result
    }
    static func audio(genres: [String], language: String, shelf: RecommendationShelf, limit: Int = 24,
                      defaults: UserDefaults = .standard) async throws -> [AudioBook] {
        let sources = SourcePreferences.enabled(.audio, defaults: defaults)
        guard !sources.isEmpty else { throw SourceError.noEnabledSources }
        let selected = genres.isEmpty ? [String?](arrayLiteral: nil) : genres.map(Optional.some)
        let context = context(genres: genres, language: language, kind: .audio, defaults: defaults)
        var requests = sources.flatMap { source in selected.map { (source, $0, String?.none, false) } }
        if shelf == .personalized {
            for source in sources {
                if let author = context.authors.sorted().first { requests.append((source, nil, author, true)) }
                if let query = context.searches.first { requests.append((source, nil, query, false)) }
            }
        }
        var jobs = requests.makeIterator()
        var found: [AudioBook] = []; var succeeded = false
        try await withThrowingTaskGroup(of: [AudioBook]?.self) { group in
            func add(_ job: (SourceDescriptor, String?, String?, Bool)) {
                group.addTask {
                    do {
                        let adapter = AudioSourceFactory.adapter(job.0)
                        if let query = job.2 { return try await adapter.search(query, byAuthor: job.3, onPage: nil) }
                        return try await adapter.browse(genre: job.1, shelf: shelf, language: language)
                    }
                    catch is CancellationError { throw CancellationError() } catch { return nil }
                }
            }
            for _ in 0..<4 { if let job = jobs.next() { add(job) } }
            while let result = try await group.next() {
                try Task.checkCancellation()
                if let result { found += result; succeeded = true }
                if let job = jobs.next() { add(job) }
            }
        }
        guard succeeded else { throw SourceError.unavailable }
        let candidates = found.map { book in
            CatalogBook(id: book.id, title: book.title, author: book.author, epubURL: nil,
                        sourceID: book.providerID, language: book.language, genres: book.genres,
                        publicationDate: book.publicationDate, popularity: book.popularity, popularityBasis: book.popularityBasis, series: book.series, seriesNumber: book.seriesNumber)
        }
        let ranked = RecommendationEngine.rank(candidates, context: context, shelf: shelf, limit: limit)
        let lookup = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let result = ranked.compactMap { item -> AudioBook? in
            guard var book = lookup[item.id] else { return nil }
            book.recommendationReason = item.recommendationReason; return book
        }
        if shelf == .personalized { defaults.set(result.map(\.id), forKey: "recommendation.previous.audio") }
        return result
    }
}
