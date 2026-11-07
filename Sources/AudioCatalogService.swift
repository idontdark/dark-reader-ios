import Foundation

enum AudioSource: String, CaseIterable, Identifiable, Codable {
    case librivox, archive
    var id: String { rawValue }
    var title: String { self == .librivox ? "LibriVox" : "Internet Archive" }
}

struct AudioBook: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let source: AudioSource
    let sourceID: String
    let title: String
    let author: String
    let description: String
    let coverURL: URL?
    let language: String?
}

struct AudioChapter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let url: URL
    let durationSeconds: Double?
}

enum AudioCatalogError: LocalizedError {
    case unavailable, invalidReply, noTracks, invalidSearch
    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Не удалось связаться с каталогом. Проверьте интернет или попробуйте VPN."
        case .invalidReply:
            "Каталог вернул неожиданные данные. Попробуйте другой источник."
        case .noTracks:
            "Для этой аудиокниги пока нет доступных глав."
        case .invalidSearch:
            "Введите название или имя автора."
        }
    }
}

/// Two independent public catalog APIs. Results are never synthesized.
enum AudioCatalogService {
    static func search(source: AudioSource, query: String, byAuthor: Bool = false) async throws -> [AudioBook] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw AudioCatalogError.invalidSearch }
        switch source {
        case .librivox:
            do {
                let found = try await searchLibriVox(term, byAuthor: byAuthor)
                if !found.isEmpty { return found }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // LibriVox currently returns HTTP 404 for many ordinary title
                // substrings. Its author lookup remains functional.
                if byAuthor { throw error }
            }
            // Internet Archive also hosts LibriVox recordings and searches
            // words in title/subject more reliably. Keep its source label.
            return try await searchArchive(term, byAuthor: byAuthor)
        case .archive:
            return try await searchArchive(term, byAuthor: byAuthor)
        }
    }

    static func featured(source: AudioSource) async throws -> [AudioBook] {
        switch source {
        case .librivox:
            var components = URLComponents(string: "https://librivox.org/api/feed/audiobooks/")!
            components.queryItems = [
                .init(name: "format", value: "json"),
                .init(name: "limit", value: "15"),
                .init(name: "sort_order", value: "desc"),
                .init(name: "coverart", value: "1")
            ]
            guard let url = components.url else { throw AudioCatalogError.invalidReply }
            let object = try await requestObject(url)
            return parseLibriVox(object)
        case .archive:
            var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
            components.queryItems = [
                .init(name: "q", value: "mediatype:audio AND collection:librivoxaudio"),
                .init(name: "fl[]", value: "identifier"),
                .init(name: "fl[]", value: "title"),
                .init(name: "fl[]", value: "creator"),
                .init(name: "rows", value: "15"),
                .init(name: "sort[]", value: "downloads desc"),
                .init(name: "output", value: "json")
            ]
            guard let url = components.url else { throw AudioCatalogError.invalidReply }
            let object = try await requestObject(url)
            return parseArchive(object)
        }
    }

    static func chapters(for book: AudioBook) async throws -> [AudioChapter] {
        let found: [AudioChapter]
        switch book.source {
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
            found = files.enumerated().compactMap { index, file in
                guard let name = file["name"] as? String,
                      (name.lowercased().hasSuffix(".mp3") || name.lowercased().hasSuffix(".m4b")),
                      name.count < 260,
                      file["private"] as? String != "true",
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
        return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func searchLibriVox(_ term: String, byAuthor: Bool) async throws -> [AudioBook] {
        var components = URLComponents(string: "https://librivox.org/api/feed/audiobooks/")!
        components.queryItems = [
            .init(name: byAuthor ? "author" : "title", value: term),
            .init(name: "format", value: "json"),
            .init(name: "limit", value: "20"),
            .init(name: "coverart", value: "1")
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
                language: string(entry["language"])
            )
        }
    }

    private static func searchArchive(_ term: String, byAuthor: Bool) async throws -> [AudioBook] {
        // Filter out the LibriVox collection so the second source provides separate recordings.
        let safeTerm = term.replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: ":", with: " ")
        let field = byAuthor ? "creator" : "title"
        let query = "mediatype:audio AND (subject:audiobooks OR subject:\"audio books\" OR collection:librivoxaudio OR collection:audio_bookspoetry) AND (\(field):\"\(safeTerm)\" OR subject:\"\(safeTerm)\") "
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "fl[]", value: "identifier"),
            .init(name: "fl[]", value: "title"),
            .init(name: "fl[]", value: "creator"),
            .init(name: "fl[]", value: "description"),
            .init(name: "rows", value: "20"),
            .init(name: "page", value: "1"),
            .init(name: "output", value: "json")
        ]
        guard let url = components.url else { throw AudioCatalogError.invalidSearch }
        let object = try await requestObject(url)
        return parseArchive(object)
    }

    private static func parseArchive(_ object: [String: Any]) -> [AudioBook] {
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
                language: nil
            )
        }
    }

    private static func requestObject(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue("DarkReader/0.7 (iOS; audio catalog search)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { throw AudioCatalogError.unavailable }
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
