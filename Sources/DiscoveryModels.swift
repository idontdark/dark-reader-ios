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
    /// Require a matching edition. A work's default title can be in another language.
    static func books(genres: [String], language: String, limit: Int = 24, sort: String = "readinglog", shelf explicitShelf: RecommendationShelf? = nil) async throws -> [DiscoveryBook] {
        let shelf: RecommendationShelf = explicitShelf ?? (sort == "new" ? .recent : (genres.isEmpty ? .popular : .personalized))
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

