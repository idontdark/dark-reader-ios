import Foundation

actor CatalogSearchAccumulator {
    private var entries: [CatalogBook] = []
    private var seen = Set<String>()
    private let query: String
    private let byAuthor: Bool
    init(query: String, byAuthor: Bool) { self.query=query;self.byAuthor=byAuthor }
    func merge(_ page: [CatalogBook]) -> [CatalogBook] {
        for book in page where seen.insert(book.id).inserted { entries.append(book) }
        return entries.enumerated().sorted { lhs,rhs in
            let a=SearchQueryPolicy.score(title:lhs.element.title,author:lhs.element.author,query:query,byAuthor:byAuthor)
            let b=SearchQueryPolicy.score(title:rhs.element.title,author:rhs.element.author,query:query,byAuthor:byAuthor)
            return a == b ? lhs.offset < rhs.offset : a > b
        }.map(\.element)
    }
}
