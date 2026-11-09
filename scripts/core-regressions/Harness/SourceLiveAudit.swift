import Foundation

/// Network evidence is recorded separately from deterministic regression tests.
/// An unavailable service is not silently treated as a successful integration.
enum SourceLiveAudit {
    struct Work: Codable, Sendable {
        var title: String
        var author: String
        var language: String?
        var genres: [String]
        var cover: Bool
        var actualFile: Bool
        var chapters: Int
        var testedTrackIndices: [Int]
        var playableAssets: [Bool]
        var error: String?
    }
    struct Source: Codable, Sendable {
        var id: String
        var query: String
        var works: [Work]
        var error: String?
        var nativeVerified: Bool
    }
    struct Genre: Codable, Sendable {
        var genre: String
        var requested = 20
        var candidates: Int
        var matched: Int
        var titles: [String]
        var error: String?
    }
    struct Report: Codable {
        var checkedAt: Date
        var sources: [Source]
        var genres: [Genre]
        var note = "Asset checks inspect the first, middle and last chapter. They do not claim audible playback, headset or lock-screen testing on a real iPhone. A shortfall below five works or twenty genre matches remains unverified."
    }
    static func run() async throws {
        var sources: [Source] = []
        // Default-enabled sources must have reproducible checks. Disabled candidate
        // HTTP/search-form investigations are in docs/source-audit-http.json.
        var iterator = SourceCatalog.all.filter { $0.defaultEnabled || $0.domain == "aknigi24.com" }.makeIterator()
        await withTaskGroup(of: Source.self) { group in
            for _ in 0..<2 { if let source = iterator.next() { group.addTask { await audit(source) } } }
            while let result = await group.next() {
                sources.append(result)
                print("SOURCE_CHECK \(result.id) works=\(result.works.count) nativeVerified=\(result.nativeVerified) error=\(result.error ?? "none")")
                if let source = iterator.next() { group.addTask { await audit(source) } }
            }
        }
        var genres: [Genre] = []
        let topics = ["history", "fantasy", "science_fiction", "detective", "romance", "biography", "adventure", "children", "nonfiction", "thriller"]
        let gutenberg = GutenbergBookSource(source: SourceCatalog.source("books:gutenberg.org")!)
        for genre in topics {
            do {
                var candidates = (try? await gutenberg.browse(genre: genre, shelf: .genre, language: "en")) ?? []
                let archive = ArchiveBookSource(source: SourceCatalog.source("books:archive.org")!)
                if let books = try? await archive.browse(genre: genre, shelf: .genre, language: "en") { candidates += books }
                let ranked = RecommendationEngine.rank(candidates, context: RecommendationContext(genres: [genre], language: "en"), shelf: .genre, limit: 20)
                genres.append(Genre(genre: genre, candidates: candidates.count, matched: ranked.count, titles: ranked.map(\.title)))
            } catch { genres.append(Genre(genre: genre, candidates: 0, matched: 0, titles: [], error: error.localizedDescription)) }
            print("GENRE_CHECK \(genre) matched=\(genres.last!.matched)/20")
        }
        let report = Report(checkedAt: Date(), sources: sources.sorted { $0.id < $1.id }, genres: genres)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(report)
        try bytes.write(to: URL(fileURLWithPath: "source-live-audit.json"), options: .atomic)
        print("SOURCE_AUDIT_JSON " + String(decoding: bytes, as: UTF8.self))
    }
    static func audit(_ source: SourceDescriptor) async -> Source {
        let query = [SourceAdapter.gutenberg, .librivox, .archiveBooks, .archiveAudio].contains(source.adapter) ? "Doyle" : "Дойл"
        var result = Source(id: source.id, query: query, works: [], nativeVerified: false)
        do {
            if source.kind == .books {
                let adapter = BookSourceFactory.adapter(source)
                let books = try await adapter.search(query, byAuthor: true, onPage: nil)
                var seen = Set<String>()
                for book in books where seen.insert(EditionIdentity.book(book)).inserted {
                    guard result.works.count < 5 else { break }
                    do {
                        let entry = try await adapter.detail(book)
                        let file = entry.epubURL
                        let actual = file == nil ? false : await SourceFileProbe.check(file!, kind: .book)
                        result.works.append(Work(title: entry.title, author: entry.author, language: entry.language,
                            genres: entry.genres ?? [], cover: entry.coverURL != nil, actualFile: actual,
                            chapters: 0, testedTrackIndices: [], playableAssets: []))
                    } catch { result.works.append(Work(title: book.title, author: book.author, language: book.language, genres: [], cover: false,
                        actualFile: false, chapters: 0, testedTrackIndices: [], playableAssets: [], error: error.localizedDescription)) }
                }
                result.nativeVerified = result.works.count == 5 && result.works.allSatisfy { $0.actualFile && $0.error == nil }
            } else {
                let adapter = AudioSourceFactory.adapter(source)
                let books = try await adapter.search(query, byAuthor: true, onPage: nil)
                var seen = Set<String>()
                for book in books where seen.insert(EditionIdentity.audioWork(book)).inserted {
                    guard result.works.count < 5 else { break }
                    do {
                        let entry = try await adapter.detail(book)
                        let tracks = try await adapter.chapters(entry)
                        let indices = Set([0, tracks.count / 2, tracks.count - 1]).filter { $0 >= 0 && $0 < tracks.count }.sorted()
                        var playable: [Bool] = []
                        for index in indices { playable.append(await SourceFileProbe.playable(tracks[index].url)) }
                        result.works.append(Work(title: entry.title, author: entry.author, language: entry.language,
                            genres: entry.genres ?? [], cover: entry.coverURL != nil, actualFile: false, chapters: tracks.count,
                            testedTrackIndices: indices, playableAssets: playable))
                    } catch { result.works.append(Work(title: book.title, author: book.author, language: book.language, genres: [], cover: false,
                        actualFile: false, chapters: 0, testedTrackIndices: [], playableAssets: [], error: error.localizedDescription)) }
                }
                result.nativeVerified = result.works.count == 5 && result.works.allSatisfy { !$0.playableAssets.isEmpty && $0.playableAssets.allSatisfy { $0 } && $0.error == nil }
            }
        } catch { result.error = error.localizedDescription }
        return result
    }
}
