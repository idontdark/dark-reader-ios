import Foundation

/// Public-domain discovery metadata. Items are *real works*, never AI-generated titles or covers.
/// Open Library does not guarantee the linked work has a downloadable file.
struct DiscoveryBook: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let coverURL: URL?
    let detailURL: URL
    let genre: String
    var firstPublishYear:Int? = nil
    var catalogBook: CatalogBook? = nil
}

enum DiscoveryService {
    private static let genreSlugs: [String: String] = [
        "detective": "mystery",
        "fantasy": "science_fiction",
        "romance": "romance",
        "classics": "classic_literature",
        "adventure": "adventure",
        "history": "history",
        "biography": "biography",
        "nonfiction": "nonfiction",
        "children": "juvenile_fiction",
        "thriller": "thrillers"
    ]

    private struct SearchFeed: Decodable { let docs: [Work] }
    private struct Editions: Decodable { let docs: [Edition] }
    private struct Edition: Decodable {
        let key: String
        let title: String
        let language: [String]?
        let cover_i: Int?
    }
    private struct Work: Decodable {
        let key: String
        let first_publish_year:Int?
        let author_name: [String]?
        let cover_i: Int?
        let editions: Editions?
    }

    /// Require a matching edition. A work's default title can be in another language.
    static func books(genres: [String], language: String, limit: Int = 24, sort: String = "readinglog") async throws -> [DiscoveryBook] {
        let shelf: RecommendationShelf = sort == "new" ? .recent : (genres.isEmpty ? .popular : .personalized)
        let books = try await UnifiedDiscoveryService.books(genres: genres, language: language, shelf: shelf, limit: limit)
        return books.compactMap { book in
            guard let page = book.navigationURL ?? book.offers?.first?.pageURL else { return nil }
            return DiscoveryBook(id: book.id, title: book.title, author: book.author, coverURL: book.coverURL,
                detailURL: page, genre: book.genres?.first ?? "", firstPublishYear: PublicationDate.year(book.publicationDate), catalogBook: book)
        }
    }

    static func saved(_ value: String) -> [DiscoveryBook] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DiscoveryBook].self, from: data)) ?? []
    }

    static func encode(_ books: [DiscoveryBook]) -> String {
        guard let data = try? JSONEncoder().encode(books) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

