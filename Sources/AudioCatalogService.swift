import Foundation

/// Two independent public catalog APIs. Results are never synthesized.
enum AudioCatalogService {
    static func search(source: AudioSource, query: String, byAuthor: Bool = false, language: String? = nil) async throws -> [AudioBook] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw AudioCatalogError.invalidSearch }
        if source == .knigavuhe || source == .akniga {
            var found:[AudioBook]=[];var seen=Set<String>();var succeeded=false;var lastError:Error?
            for variant in SearchQueryPolicy.variants(term,byAuthor:byAuthor) {
                do {
                    let batch=try await WebAudioSourceService.search(source:source,query:variant,byAuthor:byAuthor)
                    succeeded=true
                    for book in batch where seen.insert(book.id).inserted {found.append(book)}
                } catch is CancellationError {throw CancellationError()}
                catch {lastError=error}
            }
            if !succeeded,let lastError {throw lastError}
            return ranked(found.filter {matchesLanguage($0.language,choice:language)},query:term,byAuthor:byAuthor)
        }
        var variants = searchVariants(term)
        for value in SearchQueryPolicy.variants(term,byAuthor:byAuthor) where !variants.contains(value) { variants.append(value) }
        if !byAuthor,RecommendationProfile.normalized(term) == "любовь" {variants += ["love","любв"]}
        var results:[AudioBook]=[]
        var seen=Set<String>()
        var lastError:Error?
        var succeeded=false
        for variant in variants {
            do {
                let found:[AudioBook]
                switch source {
                case .librivox: found=try await searchLibriVox(variant,byAuthor:byAuthor)
                case .archive: found=try await searchArchive(variant,byAuthor:byAuthor,language:language)
                case .local,.opds,.knigavuhe,.akniga: return []
                }
                try Task.checkCancellation()
                succeeded=true
                for book in found where matchesLanguage(book.language,choice:language) && seen.insert(book.id).inserted {results.append(book)}
                if results.count>=100 {break}
            } catch is CancellationError {throw CancellationError()}
            catch {lastError=error}
        }
        if !succeeded,let lastError {throw lastError}
        return Array(ranked(results,query:term,byAuthor:byAuthor).prefix(100))
    }

    private static func ranked(_ books:[AudioBook],query:String,byAuthor:Bool)->[AudioBook] {
        books.enumerated().sorted {left,right in
            let lhs=SearchQueryPolicy.score(title:left.element.title,author:left.element.author,query:query,byAuthor:byAuthor)
            let rhs=SearchQueryPolicy.score(title:right.element.title,author:right.element.author,query:query,byAuthor:byAuthor)
            return lhs == rhs ? left.offset < right.offset : lhs > rhs
        }.map(\.element)
    }

    static func matchesLanguage(_ value: String?, choice: String?) -> Bool {
        guard let choice, choice != "all" else { return true }
        let tokens = (value ?? "").lowercased().components(separatedBy: CharacterSet.letters.inverted)
        return choice == "ru" ? tokens.contains(where: { ["ru", "rus", "russian", "русский"].contains($0) })
            : tokens.contains(where: { ["en", "eng", "english"].contains($0) })
    }

    static func searchVariants(_ term: String) -> [String] {
        let aliases = [
            "богатый папа": "Rich Dad Poor Dad",
            "богатый папа бедный папа": "Rich Dad Poor Dad",
            "мастер и маргарита": "Master and Margarita",
            "преступление и наказание": "Crime and Punishment",
            "война и мир": "War and Peace",
            "анна каренина": "Anna Karenina",
            "достоевский": "Dostoyevsky", "толстой": "Tolstoy",
            "булгаков": "Bulgakov", "кийосаки": "Kiyosaki",
            "dostoevsky": "Dostoyevsky", "dostoyevsky": "Достоевский",
            "tolstoy": "Толстой", "bulgakov": "Булгаков", "kiyosaki": "Кийосаки"
        ]
        let normalized = RecommendationProfile.normalized(term)
        if let alias = aliases[normalized] { return [term, alias] }
        if let match = aliases.keys.sorted(by: { $0.count > $1.count }).first(where: { normalized.contains($0) }),
           let alias = aliases[match] { return [term, alias] }
        return [term]
    }

    static func featured(source: AudioSource, language: String? = nil, genres: [String] = [], newest: Bool = false) async throws -> [AudioBook] {
        switch source {
        case .librivox: return try await archiveFeatured(language:language,genres:genres,newest:newest,librivoxOnly:true)
        case .archive: return try await archiveFeatured(language:language,genres:genres,newest:newest,librivoxOnly:false)
        case .knigavuhe,.akniga:
            let found=try await WebAudioSourceService.featured(source:source,genres:genres,newest:newest)
            return found.filter {matchesLanguage($0.language,choice:language)}
        case .local,.opds: return []
        }
    }

    private static func archiveFeatured(language:String?,genres:[String],newest:Bool,librivoxOnly:Bool) async throws -> [AudioBook] {
            var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
            components.queryItems = [
                .init(name: "q", value: "mediatype:audio AND " + (librivoxOnly ? "collection:librivoxaudio":"(collection:librivoxaudio OR collection:audio_bookspoetry OR subject:audiobooks OR subject:аудиокниги)") + languageQuery(language) + (genres.first.flatMap { audioGenreQuery($0, archive: true) } ?? "")),
                .init(name: "fl[]", value: "language"),
                .init(name: "fl[]", value: "subject"),
            .init(name: "fl[]", value: "date"),
            .init(name: "fl[]", value: "year"),
            .init(name: "fl[]", value: "downloads"),
                .init(name: "fl[]", value: "date"),
                .init(name: "fl[]", value: "year"),
                .init(name: "fl[]", value: "downloads"),
                .init(name: "fl[]", value: "identifier"),
                .init(name: "fl[]", value: "title"),
                .init(name: "fl[]", value: "creator"),
                .init(name: "rows", value: "30"),
                .init(name: "sort[]", value: newest ? "date desc" : "downloads desc"),
                .init(name: "output", value: "json")
            ]
            guard let url = components.url else { throw AudioCatalogError.invalidReply }
            let object = try await requestObject(url)
            return parseArchive(object)
    }

    static func chapters(for book: AudioBook) async throws -> [AudioChapter] {
        if book.source == .opds, let provider = book.providerID, let source = SourceCatalog.source(provider) {
            return try await HTMLAudiobookSource(source: source).chapters(book)
        }
        if ![AudioSource.local,.knigavuhe,.akniga].contains(book.source), let cached = AudioTrackCache.load(book), !cached.isEmpty { return cached }
        let found: [AudioChapter]
        switch book.source {
        case .opds:
            if let url=book.streamURL {
                found=[AudioChapter(id:book.id+":track",title:book.title,url:url,durationSeconds:nil)]
            } else if let url=book.feedURL {
                let entries=try await OPDSClient(searchEndpoint:"",queryParameter:"").browse(url)
                found=entries.enumerated().compactMap {index,entry in
                    guard let url=entry.audioURL else{return nil}
                    return AudioChapter(id:book.id+":\(index)",title:entry.title,url:url,durationSeconds:nil)
                }
            } else {throw AudioCatalogError.noTracks}
        case .local: return try AudioImportStore.chapters(for: book)
        case .knigavuhe,.akniga:
            do {found=try await WebAudioSourceService.chapters(for:book)}
            catch {if book.source == .knigavuhe,let cached=AudioTrackCache.load(book),!cached.isEmpty {return cached};throw error}
        case .librivox:
            let url = URL(string: "https://librivox.org/api/feed/audiotracks/?project_id=\(book.sourceID)&format=json")!
            let object = try await requestObject(url)
            let sections = object["sections"] as? [[String: Any]] ?? []
            found = sections.enumerated().compactMap { index, value in
                guard let address = value["listen_url"] as? String,
                      let url = secureURL(address) else { return nil }
                return AudioChapter(
                    id: "\(book.id):\(index)",
                    title: string(value["title"]) ?? "Глава \(index + 1)",
                    url: url,
                    durationSeconds: Double(string(value["playtime"]) ?? "")
                )
            }
        case .archive:
            guard let safeID = book.sourceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://archive.org/metadata/\(safeID)") else {
                throw AudioCatalogError.invalidReply
            }
            let object = try await requestObject(url)
            let files = object["files"] as? [[String: Any]] ?? []
            let hasMP3 = files.contains { (string($0["name"]) ?? "").lowercased().hasSuffix(".mp3") }
            found = files.enumerated().compactMap { index, file in
                guard let name = file["name"] as? String,
                      (name.lowercased().hasSuffix(".mp3") || (!hasMP3 && name.lowercased().hasSuffix(".m4b"))),
                      name.count < 260,
                      file["private"] as? String != "true", file["private"] as? Bool != true,
                      file["source"] as? String != "metadata",
                      let fileURL = URL(string: "https://archive.org/download/\(safeID)/")?
                        .appendingPathComponent(name) else { return nil }
                return AudioChapter(
                    id: "\(book.id):\(index)",
                    title: name.replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: ".mp3", with: "", options: .caseInsensitive),
                    url: fileURL,
                    durationSeconds: Double(string(file["length"]) ?? "")
                )
            }
        }
        guard !found.isEmpty else { throw AudioCatalogError.noTracks }
        let sorted = [AudioSource.knigavuhe,.akniga].contains(book.source) ? found:found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        AudioTrackCache.save(sorted, for: book)
        return sorted
    }

    private static func searchLibriVox(_ term: String, byAuthor: Bool) async throws -> [AudioBook] {
        var components = URLComponents(string: "https://librivox.org/api/feed/audiobooks/")!
        components.queryItems = [
            .init(name: byAuthor ? "author" : "title", value: term),
            .init(name: "format", value: "json"),
            .init(name: "limit", value: "20"),
            .init(name: "coverart", value: "1"),
            .init(name: "extended", value: "1")
        ]
        guard let url = components.url else { throw AudioCatalogError.invalidSearch }
        let object = try await requestObject(url)
        return parseLibriVox(object)
    }

    private static func parseLibriVox(_ object: [String: Any]) -> [AudioBook] {
        let rows = object["books"] as? [[String: Any]] ?? []
        return rows.compactMap { entry in
            guard let id = string(entry["id"]), !id.isEmpty,
                  let title = string(entry["title"]), !title.isEmpty else { return nil }
            let authors = entry["authors"] as? [[String: Any]] ?? []
            let names = authors.map { author in
                [string(author["first_name"]), string(author["last_name"])]
                    .compactMap { $0 }.joined(separator: " ")
            }.filter { !$0.isEmpty }
            return AudioBook(
                id: "librivox:\(id)", source: .librivox, sourceID: id,
                title: title, author: names.joined(separator: ", ").isEmpty ? "Неизвестный автор" : names.joined(separator: ", "),
                description: string(entry["description"]) ?? "",
                coverURL: secureURL(string(entry["coverart_thumbnail"]) ?? string(entry["coverart_jpg"]) ?? ""),
                language: string(entry["language"]),
                genres: GenreTaxonomy.normalize(((entry["genres"] as? [[String: Any]]) ?? []).compactMap { string($0["name"]) }),
                pageURL: secureURL(string(entry["url_librivox"]) ?? ""),
                narrator: ((entry["readers"] as? [[String: Any]]) ?? []).compactMap { string($0["display_name"] ?? $0["name"]) }.joined(separator: ", "),
                durationSeconds: Double(string(entry["totaltimesecs"]) ?? ""),
                publicationDate: string(entry["catalog_date"])
            )
        }
    }

    private static func searchArchive(_ term: String, byAuthor: Bool, language: String?, librivoxOnly:Bool=false) async throws -> [AudioBook] {
        guard let words = archiveSearchExpression(term, byAuthor: byAuthor) else { return [] }
        let scope=librivoxOnly ? "collection:librivoxaudio":"(subject:audiobooks OR subject:аудиокниги OR subject:\"audio books\" OR collection:librivoxaudio OR collection:audio_bookspoetry)"
        let query = "mediatype:audio AND \(scope) AND (\(words))" + languageQuery(language)
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "fl[]", value: "identifier"),
            .init(name: "fl[]", value: "title"),
            .init(name: "fl[]", value: "creator"),
            .init(name: "fl[]", value: "description"),
            .init(name: "fl[]", value: "language"),
            .init(name: "fl[]", value: "subject"),
            .init(name: "fl[]", value: "date"),
            .init(name: "fl[]", value: "year"),
            .init(name: "fl[]", value: "downloads"),
            .init(name: "rows", value: "100"),
            .init(name: "page", value: "1"),
            .init(name: "output", value: "json")
        ]
        guard let url = components.url else { throw AudioCatalogError.invalidSearch }
        let object = try await requestObject(url)
        return parseArchive(object)
    }

    static func parseArchive(_ object: [String: Any]) -> [AudioBook] {
        guard let result = object["response"] as? [String: Any] else { return [] }
        let docs = result["docs"] as? [[String: Any]] ?? []
        return docs.compactMap { item in
            guard let id = item["identifier"] as? String,
                  !id.isEmpty, id.count < 160,
                  let title = string(item["title"]) else { return nil }
            let author = string(item["creator"]) ?? "Неизвестный автор"
            return AudioBook(
                id: "archive:\(id)", source: .archive, sourceID: id,
                title: title, author: author, description: string(item["description"]) ?? "",
                coverURL: URL(string: "https://archive.org/services/img/\(id)"),
                language: string(item["language"]),
                genres: GenreTaxonomy.normalize((item["subject"] as? [String]) ?? string(item["subject"]).map { [$0] } ?? []),
                publicationDate: string(item["date"] ?? item["year"]),
                popularity: (item["downloads"] as? NSNumber)?.doubleValue,
                popularityBasis: "Количество прослушиваний в Internet Archive"
            )
        }
    }

    static func archiveSearchExpression(_ term: String, byAuthor: Bool) -> String? {
        let stopwords: Set<String> = ["и", "в", "во", "на", "с", "the", "a", "an", "and", "of"]
        let tokens = RecommendationProfile.normalized(term).split(separator: " ").map(String.init)
            .filter { !stopwords.contains($0) }
        guard !tokens.isEmpty else { return nil }
        let field = byAuthor ? "creator" : "title"
        return tokens.map { "\(field):\($0)*" }.joined(separator: " AND ")
    }

    static func audioGenreQuery(_ genre: String, archive: Bool) -> String? {
        let topics = ["detective":"mystery", "fantasy":"fantasy", "science_fiction":"science fiction", "psychology":"psychology", "business":"business", "historical_fiction":"historical fiction", "romance":"romance", "classics":"classics",
                      "adventure":"adventure", "history":"history", "biography":"biography",
                      "nonfiction":"non fiction", "children":"children", "thriller":"thriller"]
        guard let topic = topics[genre] else { return nil }
        if archive {
            let queries=["romance":"romance OR novel OR роман OR романы","fantasy":"fantasy OR фэнтези", "science_fiction":"science fiction OR фантастика","detective":"mystery OR detective OR детектив","classics":"classics OR classic OR классика","adventure":"adventure OR приключения","children":"children OR fairy tales OR сказки"]
            return " AND subject:(\(queries[genre] ?? topic))"
        }
        return topic
    }

    private static func languageQuery(_ language: String?) -> String {
        switch language {
        case "ru": return " AND language:(rus OR ru OR Russian)"
        case "en": return " AND language:(eng OR en OR English)"
        default: return ""
        }
    }

    private static func requestObject(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue("DarkReader/0.7 (iOS; audio catalog search)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw AudioCatalogError.unavailable }
            if response.statusCode == 404, url.host == "librivox.org" { return [:] }
            guard (200..<300).contains(response.statusCode) else { throw AudioCatalogError.unavailable }
            guard data.count < 4_000_000,
                  let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AudioCatalogError.invalidReply
            }
            return value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AudioCatalogError.unavailable
        }
    }

    private static func secureURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "http" || components.scheme == "https",
              components.host != nil else { return nil }
        components.scheme = "https"
        return components.url
    }

    private static func string(_ object: Any?) -> String? {
        if let value = object as? String { return value }
        if let number = object as? NSNumber { return number.stringValue }
        if let list = object as? [String] { return list.joined(separator: ", ") }
        return nil
    }
}
