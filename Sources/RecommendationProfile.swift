import Foundation

enum RecommendationProfile {
    struct Signal: Codable {
        var title: String
        var author: String
        var genre: String?
        var weight: Int
        var date: Date
    }
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "ru"))
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func signals(_ defaults: UserDefaults = .standard) -> [Signal] {
        guard let data = defaults.data(forKey: "recommendation.signals") else { return [] }
        return (try? JSONDecoder().decode([Signal].self, from: data)) ?? []
    }
    static func record(title: String, author: String, weight: Int, genre explicitGenre: String? = nil, defaults: UserDefaults = .standard) {
        var values = signals(defaults)
        let key = normalized(title)
        let favorites = DiscoveryService.saved(defaults.string(forKey: "favoriteBooksJSON") ?? "[]")
        let genre = explicitGenre ?? favorites.first { normalized($0.title) == key }?.genre
        let old = values.first { normalized($0.title) == key }
        values.removeAll { normalized($0.title) == key }
        values.insert(Signal(title: title, author: author, genre: genre ?? old?.genre,
                             weight: max(weight, old?.weight ?? 0), date: Date()), at: 0)
        defaults.set(try? JSONEncoder().encode(Array(values.prefix(200))), forKey: "recommendation.signals")
    }
    static func genres(_ selected: [String], defaults: UserDefaults = .standard) -> [String] {
        var scores = Dictionary(selected.map { ($0, 5) }, uniquingKeysWith: max)
        for book in DiscoveryService.saved(defaults.string(forKey: "favoriteBooksJSON") ?? "[]") {
            scores[book.genre, default: 0] += 3
        }
        for signal in signals(defaults) {
            if let genre = signal.genre { scores[genre, default: 0] += signal.weight }
        }
        return scores.keys.sorted { scores[$0, default: 0] == scores[$1, default: 0] ? $0 < $1 : scores[$0, default: 0] > scores[$1, default: 0] }
    }
    static func classify(_ text: String) -> [String] {
        let value = normalized(text)
        let keywords: [String: [String]] = [
            "detective": ["detective", "mystery", "детектив"],
            "fantasy": ["fantasy", "science fiction", "fantastic", "фантаст", "фэнтези"],
            "romance": ["romance", "love", "любов", "роман"],
            "classics": ["classic", "классик"],
            "adventure": ["adventure", "приключен"],
            "history": ["history", "historical", "истор"],
            "biography": ["biography", "memoir", "биограф", "мемуар"],
            "nonfiction": ["nonfiction", "non fiction", "philosophy", "психолог", "философ"],
            "children": ["children", "juvenile", "fairy", "детск", "сказк"],
            "thriller": ["thriller", "horror", "триллер", "ужас"]
        ]
        return keywords.keys.filter { key in keywords[key]!.contains { value.contains($0) } }.sorted()
    }
    static func rankAudio(_ books: [AudioBook], genres selected: [String], defaults: UserDefaults = .standard) -> [AudioBook] {
        let history = signals(defaults)
        let excluded = Set(history.filter { $0.weight >= 2 }.map { normalized($0.title) })
        let authors = Set(history.map { normalized($0.author) } +
            DiscoveryService.saved(defaults.string(forKey:"favoriteBooksJSON") ?? "[]").map { normalized($0.author) })
        let preferred = Set(genres(selected, defaults: defaults).prefix(3))
        let previous = Set(defaults.stringArray(forKey:"recommendation.previousAudio") ?? [])
        let ranked = books.filter { !excluded.contains(normalized($0.title)) }.sorted {
            func score(_ book: AudioBook) -> Int {
                (authors.contains(normalized(book.author)) ? 10 : 0) +
                Set(book.genres ?? []).intersection(preferred).count * 5 +
                (previous.contains(book.id) ? 0 : 2)
            }
            return score($0) == score($1) ? $0.id < $1.id : score($0) > score($1)
        }
        defaults.set(Array(ranked.prefix(12)).map(\.id), forKey:"recommendation.previousAudio")
        return ranked
    }

    static func rank(_ books: [DiscoveryBook], excluding titles: [String], defaults: UserDefaults = .standard) -> [DiscoveryBook] {
        let excluded = Set(titles.map(normalized) + signals(defaults).filter { $0.weight >= 2 }.map { normalized($0.title) })
        let favorite = DiscoveryService.saved(defaults.string(forKey: "favoriteBooksJSON") ?? "[]")
        let authors = Set(favorite.map { normalized($0.author) } + signals(defaults).map { normalized($0.author) })
        let previous = Set(defaults.stringArray(forKey: "recommendation.previous") ?? [])
        let ranked = books.filter { !excluded.contains(normalized($0.title)) && !favorite.contains($0) }.sorted {
            func score(_ book: DiscoveryBook) -> Int {
                (authors.contains(normalized(book.author)) ? 10 : 0) + (previous.contains(book.id) ? 0 : 4)
            }
            return score($0) == score($1) ? $0.id < $1.id : score($0) > score($1)
        }
        defaults.set(Array(ranked.prefix(12)).map(\.id), forKey: "recommendation.previous")
        return Array(ranked.prefix(12))
    }
}
