import Foundation

enum EditionIdentity {
    static func isbn(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.uppercased().filter { $0.isNumber || $0 == "X" }
        if text.count == 10 {
            let digits = text.map { $0 == "X" ? 10 : $0.wholeNumberValue ?? -100 }
            guard !text.dropLast().contains("X"), zip(digits, (1...10).reversed()).reduce(0, { $0 + $1.0 * $1.1 }) % 11 == 0 else { return nil }
            let prefix = "978" + text.prefix(9)
            let sum = prefix.enumerated().reduce(0) { $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset % 2 == 0 ? 1 : 3) }
            return prefix + String((10 - sum % 10) % 10)
        }
        guard text.count == 13, !text.contains("X") else { return nil }
        let sum = text.enumerated().reduce(0) { $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset % 2 == 0 ? 1 : 3) }
        return sum % 10 == 0 ? text : nil
    }
    static func book(_ book: CatalogBook) -> String {
        let language = GenreTaxonomy.language(book.language) ?? "unknown"
        if let isbn = isbn(book.isbn) { return "isbn:" + isbn + ":" + language }
        // Unknown author must not merge unrelated editions with the same title.
        let author = GenreTaxonomy.normalized(book.author)
        if author.isEmpty || ["неизвестный автор", "автор не указан", "unknown author"].contains(author) { return book.id }
        return [GenreTaxonomy.normalized(book.title), author, language, PublicationDate.year(book.publicationDate).map(String.init) ?? "undated"].joined(separator: ":")
    }
    static func audioWork(_ book: AudioBook) -> String {
        let author = GenreTaxonomy.normalized(book.author)
        guard !author.isEmpty, author != "неизвестный автор" else { return book.id }
        return [GenreTaxonomy.normalized(book.title), author, GenreTaxonomy.language(book.language) ?? "unknown"].joined(separator: ":")
    }
    static func mergeBooks(_ entries: [CatalogBook], query: String, byAuthor: Bool, language: String?) -> [CatalogBook] {
        var values: [String: CatalogBook] = [:]; var order: [String] = []
        for book in entries where SearchQueryPolicy.matchesSearchLanguage(book.language, requested: language) {
            let key = self.book(book)
            if var existing = values[key] {
                var seen = Set<String>()
                existing.offers = ((existing.offers ?? []) + (book.offers ?? [])).filter { seen.insert($0.id).inserted }
                if existing.coverURL == nil { existing.coverURL = book.coverURL }
                if existing.summary?.isEmpty != false { existing.summary = book.summary }
                if existing.epubURL == nil { existing.epubURL = book.epubURL; existing.downloadFormat = book.downloadFormat }
                if existing.publicationDate == nil { existing.publicationDate = book.publicationDate }
                if existing.popularity == nil { existing.popularity = book.popularity; existing.popularityBasis = book.popularityBasis }
                if existing.series == nil { existing.series = book.series; existing.seriesNumber = book.seriesNumber }
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
