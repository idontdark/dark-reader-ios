import Foundation

enum RecommendationShelf: String, Sendable { case personalized, popular, recent, genre }
struct RecommendationContext: Sendable {
    var genres: [String]
    var authors: Set<String> = []
    var excludedTitles: Set<String> = []
    var previousIDs: Set<String> = []
    var language: String
    var searches: [String] = []
    var series: Set<String> = []
    var authorWeights: [String: Double] = [:]
    var now = Date()
}
struct RecommendationDecision: Sendable { let accepted: Bool; let score: Double; let reason: String; let genres: [String] }

/// Deterministic, metadata-based and explainable. Missing evidence produces fewer
/// results, never a random fill. Work title is used for exclusion, not genre inference.
enum RecommendationEngine {
    static func evaluate(id: String, title: String, author: String, language: String?, genres: [String],
                         publicationDate: String?, popularity: Double?, popularityBasis: String?,
                         series: String? = nil, context: RecommendationContext, shelf: RecommendationShelf) -> RecommendationDecision {
        let normalizedGenres = GenreTaxonomy.normalize(genres)
        let rejected = RecommendationDecision(accepted: false, score: 0, reason: "", genres: normalizedGenres)
        guard GenreTaxonomy.matchesLanguage(language, requested: context.language),
              !context.excludedTitles.contains(GenreTaxonomy.normalized(title)) else { return rejected }
        let matches = Set(normalizedGenres).intersection(context.genres)
        if !context.genres.isEmpty && matches.isEmpty { return rejected }
        var reason = ""
        var score = Double(matches.count * 20)
        switch shelf {
        case .recent:
            guard PublicationDate.isRecent(publicationDate, now: context.now) else { return rejected }
            reason = "Новое издание"; score += Double(PublicationDate.year(publicationDate) ?? 0)
        case .popular:
            guard let popularity, popularity > 0, let basis = popularityBasis, !basis.isEmpty else { return rejected }
            reason = basis; score += log1p(popularity)
        case .genre:
            guard !matches.isEmpty else { return rejected }
            reason = "Соответствует выбранному жанру"
        case .personalized:
            let authorMatch = context.authors.contains(GenreTaxonomy.normalized(author))
            let searchable = GenreTaxonomy.normalized(title + " " + author)
            let historyMatch = context.searches.contains { query in
                query.count >= 4 && searchable.contains(GenreTaxonomy.normalized(query))
            }
            let seriesMatch = series.map { context.series.contains(GenreTaxonomy.normalized($0)) } ?? false
            guard !matches.isEmpty || authorMatch || historyMatch || seriesMatch else { return rejected }
            reason = seriesMatch ? "Продолжение знакомой серии" : authorMatch ? "Ваш любимый автор" : historyMatch ? "На основе ваших поисков" : "По вашим любимым жанрам"
            if authorMatch { score += 15 }
            if seriesMatch { score += 18 }
            if historyMatch { score += 10 }
            score += context.authorWeights[GenreTaxonomy.normalized(author), default: 0]
            if context.previousIDs.contains(id) { score -= 8 }
        }
        if popularityBasis != nil { score += min(5, log1p(max(0, popularity ?? 0))) }
        return RecommendationDecision(accepted: true, score: score, reason: reason, genres: normalizedGenres)
    }
    static func rank(_ candidates: [CatalogBook], context: RecommendationContext, shelf: RecommendationShelf, limit: Int = 24) -> [CatalogBook] {
        var seen = Set<String>()
        var scored: [(CatalogBook, RecommendationDecision)] = []
        for var book in candidates {
            let key = GenreTaxonomy.normalized(book.title) + ":" + GenreTaxonomy.normalized(book.author)
            let decision = evaluate(id: book.id, title: book.title, author: book.author, language: book.language,
                                    genres: book.genres ?? [], publicationDate: book.publicationDate,
                                    popularity: book.popularity, popularityBasis: book.popularityBasis,
                                    series: book.series, context: context, shelf: shelf)
            guard decision.accepted, seen.insert(key).inserted else { continue }
            book.recommendationReason = decision.reason; scored.append((book, decision))
        }
        scored.sort { $0.1.score == $1.1.score ? $0.0.id < $1.0.id : $0.1.score > $1.1.score }
        // Round-robin all selected genres, while bounding repeated authors.
        var result: [CatalogBook] = []; var selected = Set<String>(); var authorCounts: [String: Int] = [:]
        let groups = context.genres.isEmpty ? [""] : context.genres
        for _ in 0..<limit {
            for genre in groups {
                guard result.count < limit, let item = scored.first(where: {
                    !selected.contains($0.0.id) && (genre.isEmpty || $0.1.genres.contains(genre)) && authorCounts[GenreTaxonomy.normalized($0.0.author), default: 0] < 3
                }) else { continue }
                result.append(item.0); selected.insert(item.0.id); authorCounts[GenreTaxonomy.normalized(item.0.author), default: 0] += 1
            }
        }
        return result
    }
}
