import Foundation
import SwiftSoup

/// A shared DOM parser. Provider adapters own routes and capability decisions.
enum HTMLSourceParser {
    static func document(_ response: SourceResponse) throws -> Document {
        guard let html = SourceHTTPClient.html(response), !html.contains("cf-chl-") else { throw SourceError.unexpectedContent }
        return try SwiftSoup.parse(html, response.url.absoluteString)
    }
    static func searchForm(_ doc: Document, base: URL) throws -> SourceSearchForm? {
        for form in try doc.select("form") {
            let inputs = try form.select("input[name]")
            let text = try inputs.array().first { input in
                let name = try input.attr("name").lowercased()
                let type = try input.attr("type").lowercased()
                let role = try form.attr("role").lowercased()
                let action = try form.attr("action").lowercased()
                let known = ["q", "s", "req", "ask", "find", "search", "story", "query", "keyword"].contains(name)
                return ["text", "search", ""].contains(type) && (known || name.contains("search") || name.contains("sphinx") || role == "search" || action.contains("search"))
            }
            guard let text, let url = URL(string: try form.attr("action"), relativeTo: base)?.absoluteURL,
                  url.host == base.host, url.scheme == "https" else { continue }
            var hidden: [String: String] = [:]
            for input in try form.select("input[type=hidden][name]") { hidden[try input.attr("name")] = try input.attr("value") }
            return SourceSearchForm(url: url, method: try form.attr("method"), field: try text.attr("name"), hidden: hidden)
        }
        return nil
    }
    static func scalar(_ value: Any?) -> String? {
        if let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if let object = value as? [String: Any] { return scalar(object["name"] ?? object["@id"]) }
        if let list = value as? [Any] {
            let text = list.compactMap(scalar).joined(separator: ", ")
            return text.isEmpty ? nil : text
        }
        return nil
    }
    static func objects(_ value: Any) -> [[String: Any]] {
        if let list = value as? [Any] { return list.flatMap(objects) }
        guard let object = value as? [String: Any] else { return [] }
        var result = [object]
        for key in ["@graph", "itemListElement", "item", "mainEntity", "associatedMedia"] {
            if let nested = object[key] { result += objects(nested) }
        }
        return result
    }
    static func linkedData(_ doc: Document) -> [[String: Any]] {
        ((try? doc.select("script[type=application/ld+json]").array()) ?? []).flatMap { script in
            guard let data = (try? script.data())?.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
            return objects(object)
        }
    }
    static func value(_ selector: String, in doc: Document) -> String? {
        guard let element = try? doc.select(selector).first() else { return nil }
        return scalar((try? element.attr("content"))) ?? scalar(try? element.text())
    }
    static func url(_ value: String?, base: URL) -> URL? {
        guard let value, !value.isEmpty, let url = URL(string: value, relativeTo: base)?.absoluteURL, url.scheme == "https" else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.fragment = nil
        return parts?.url
    }
    static func field(_ labels: [String], in doc: Document) -> String? {
        for row in (try? doc.select("tr").array()) ?? [] {
            guard let cells = try? row.select("td, th").array(), cells.count >= 2,
                  let name = try? cells[0].text(), labels.contains(GenreTaxonomy.normalized(name)) else { continue }
            return scalar(try? cells[1].text())
        }
        return nil
    }
    static func duration(_ value: String?) -> Double? {
        guard let value else { return nil }
        if let number = Double(value), number > 0 { return number }
        let pattern = #"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        func number(_ index: Int) -> Double { Range(match.range(at: index), in: value).flatMap { Double(value[$0]) } ?? 0 }
        let result = number(1) * 3600 + number(2) * 60 + number(3)
        return result > 0 ? result : nil
    }
    static func bookLinks(_ doc: Document, base: URL) throws -> [(URL, String)] {
        let pattern = #"/(?:book|books|b|audiobook|kniga)/[^/?#]+|/\d{2,}[^/]*\.html|/lib/[^/]+/[^/]+\.html"#
        var seen = Set<URL>()
        return try doc.select("a[href]").array().compactMap { anchor in
            guard let address = url(try anchor.attr("href"), base: base), address.host == base.host,
                  address.path.range(of: pattern, options: .regularExpression) != nil,
                  let title = scalar(try anchor.text()), title.count >= 3, title.count <= 350, seen.insert(address).inserted else { return nil }
            return (address, title)
        }
    }
    static func book(_ doc: Document, url page: URL, source: SourceDescriptor, fallbackTitle: String? = nil) throws -> CatalogBook {
        let ld = linkedData(doc).first { (scalar($0["@type"]) ?? "").localizedCaseInsensitiveContains("book") } ?? [:]
        guard let title = scalar(ld["name"]) ?? value("h1", in: doc) ?? value("meta[property=og:title]", in: doc) ?? fallbackTitle else { throw SourceError.unexpectedContent }
        let author = scalar(ld["author"]) ?? field(["автор", "авторы", "author", "authors"], in: doc) ?? value("[itemprop=author] [itemprop=name], [itemprop=author], .book_author, .book-author, .book-info a[href*=author], .book_info a[href*=author]", in: doc) ?? "Неизвестный автор"
        let lang = scalar(ld["inLanguage"]) ?? field(["язык", "language"], in: doc) ?? value("[itemprop=inLanguage], meta[property='book:language']", in: doc)
        let subjects = (ld["genre"] as? [String]) ?? scalar(ld["genre"]).map { [$0] } ?? []
        let breadcrumbs = linkedData(doc).filter { object in
            guard scalar(object["@type"]) == "ListItem", let address = scalar(object["item"]) else { return false }
            return address.contains("/genre/") || address.contains("/section/")
        }.compactMap { scalar($0["name"]) }
        let genres = GenreTaxonomy.normalize(subjects + breadcrumbs + [field(["жанр", "жанры", "genre", "genres"], in: doc) ?? value("[itemprop=genre], .book-genre, .book_genre", in: doc) ?? ""])
        let image = scalar(ld["image"]) ?? (ld["image"] as? [String: Any]).flatMap { scalar($0["url"]) } ?? value("meta[property=og:image]", in: doc)
        var offers: [BookOffer] = []
        for link in try doc.select("a[href]") {
            guard let address = self.url(try link.attr("href"), base: page) else { continue }
            let path = address.path.lowercased()
            let format = ["epub", "fb2", "mobi", "pdf", "txt", "rtf", "doc"].first { path.hasSuffix("." + $0) || path.hasSuffix("." + $0 + ".zip") }
            guard let format else { continue }
            offers.append(BookOffer(sourceID: source.id, sourceName: source.name, pageURL: page, fileURL: address, format: path.hasSuffix(".zip") ? "zip" : format))
        }
        let priority = ["epub", "fb2", "zip", "mobi", "pdf", "txt", "rtf", "doc"]
        offers.sort { (priority.firstIndex(of: $0.format ?? "") ?? 99) < (priority.firstIndex(of: $1.format ?? "") ?? 99) }
        if offers.isEmpty { offers = [BookOffer(sourceID: source.id, sourceName: source.name, pageURL: page)] }
        let rating = ld["aggregateRating"] as? [String: Any] ?? [:]
        let ratingValue = scalar(rating["ratingValue"]).flatMap(Double.init)
        let ratingCount = scalar(rating["ratingCount"] ?? rating["reviewCount"]).flatMap(Double.init)
        let popularity = ratingValue.flatMap { value in ratingCount.map { value * $0 } }
        return CatalogBook(id: source.id + ":" + page.absoluteString, title: title, author: author,
                           epubURL: offers.first?.fileURL, navigationURL: page, coverURL: self.url(image, base: page),
                           summary: scalar(ld["description"]) ?? value("[itemprop=description], meta[property=og:description]", in: doc),
                           downloadFormat: offers.first?.format, sourceID: source.id, language: lang,
                           genres: genres, isbn: scalar(ld["isbn"]), publicationDate: scalar(ld["datePublished"]),
                           popularity: popularity, popularityBasis: popularity == nil ? nil : "Рейтинг и число оценок в источнике",
                           offers: offers, series: scalar(ld["isPartOf"]) ?? field(["серия", "цикл", "series"], in: doc),
                           seriesNumber: scalar(ld["position"]).flatMap(Double.init))
    }
    static func chapters(_ doc: Document, base: URL) throws -> [AudioChapter] {
        var result: [AudioChapter] = []; var seen = Set<URL>()
        // Aknigi24's ordinary web player uses the explicit chapterBase and chapter
        // numbers from this JSON. No private API, token synthesis or URL guessing.
        if base.host == "aknigi24.com", let node = try doc.select("script#player-data[type=application/json]").first(),
           let data = try node.data().data(using: .utf8),
           let player = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let prefix = scalar(player["chapterBase"]), let chapterBase = url(prefix, base: base), chapterBase.host == base.host {
            for chapter in player["chapters"] as? [[String: Any]] ?? [] {
                guard let number = chapter["n"] as? Int, number > 0 else { continue }
                let address = chapterBase.appendingPathComponent(String(number))
                if seen.insert(address).inserted {
                    result.append(AudioChapter(id: address.absoluteString, title: scalar(chapter["title"]) ?? String(number),
                        url: address, durationSeconds: (chapter["d"] as? NSNumber)?.doubleValue))
                }
            }
        }
        for object in linkedData(doc) {
            if let address = url(scalar(object["contentUrl"] ?? object["contentURL"]), base: base), seen.insert(address).inserted {
                result.append(AudioChapter(id: address.absoluteString, title: scalar(object["name"]) ?? "Аудиокнига", url: address, durationSeconds: nil))
            }
        }
        for node in try doc.select("audio[src], audio source[src]") {
            if let address = url(try node.attr("src"), base: base), seen.insert(address).inserted {
                result.append(AudioChapter(id: address.absoluteString, title: (try? node.attr("title")) ?? "Аудиокнига", url: address, durationSeconds: nil))
            }
        }
        return result
    }
}
