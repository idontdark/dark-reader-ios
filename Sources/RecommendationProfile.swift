import Foundation

/// Local interaction history, kept separately for reading and listening.
enum RecommendationProfile {
    struct Signal: Codable, Sendable {
        var title: String
        var author: String
        var genre: String?
        var weight: Int
        var date: Date
        var kind: SourceKind? = nil
        var series: String? = nil
    }
    static func normalized(_ value: String) -> String { GenreTaxonomy.normalized(value) }
    static func signals(_ defaults: UserDefaults = .standard) -> [Signal] {
        guard let data = defaults.data(forKey: "recommendation.signals") else { return [] }
        return (try? JSONDecoder().decode([Signal].self, from: data)) ?? []
    }
    static func record(title: String, author: String, weight: Int, genre: String? = nil,
                       kind: SourceKind = .books, series: String? = nil, defaults: UserDefaults = .standard) {
        var values = signals(defaults)
        let key = normalized(title)
        let old = values.first { normalized($0.title) == key && ($0.kind ?? .books) == kind }
        values.removeAll { normalized($0.title) == key && ($0.kind ?? .books) == kind }
        values.insert(Signal(title: title, author: author, genre: genre ?? old?.genre,
                             weight: max(weight, old?.weight ?? 0), date: Date(), kind: kind,
                             series: series ?? old?.series), at: 0)
        defaults.set(try? JSONEncoder().encode(Array(values.prefix(400))), forKey: "recommendation.signals")
    }
    static func genres(_ selected: [String], kind: SourceKind = .books, defaults: UserDefaults = .standard) -> [String] {
        let explicit = GenreTaxonomy.normalize(selected)
        if !explicit.isEmpty { return explicit }
        var scores: [String: Int] = [:]
        for signal in signals(defaults) where (signal.kind ?? .books) == kind {
            for genre in GenreTaxonomy.normalize(signal.genre.map { [$0] } ?? []) { scores[genre, default: 0] += signal.weight }
        }
        return scores.keys.sorted { scores[$0, default: 0] == scores[$1, default: 0] ? $0 < $1 : scores[$0, default: 0] > scores[$1, default: 0] }
    }
}
