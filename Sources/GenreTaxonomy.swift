import Foundation

/// Classify catalog subject metadata, never a title, query, or description.
enum GenreTaxonomy {
    static let aliases: [String: [String]] = [
        "history": ["история", "историческая литература", "history", "historical studies"],
        "historical_fiction": ["исторический роман", "исторические романы", "historical fiction", "historical romance"],
        "fantasy": ["фэнтези", "fantasy", "fantasy fiction", "magic", "wizards"],
        "science_fiction": ["научная фантастика", "фантастика", "science fiction", "space opera"],
        "detective": ["детектив", "детективы", "detective", "mystery", "detective and mystery stories"],
        "romance": ["любовные романы", "любовный роман", "romance", "romance fiction"],
        "biography": ["биографии", "биография", "мемуары", "biography", "autobiography", "memoirs"],
        "psychology": ["психология", "psychology", "mental health"],
        "business": ["бизнес", "предпринимательство", "экономика", "business", "economics", "management", "entrepreneurship"],
        "nonfiction": ["научно-популярная литература", "документальная литература", "nonfiction", "non fiction", "philosophy"],
        "adventure": ["приключения", "adventure", "adventure stories"],
        "children": ["детская литература", "для детей", "children", "juvenile fiction", "fairy tales"],
        "classics": ["классика", "классическая литература", "classics", "classic literature"],
        "thriller": ["триллер", "триллеры", "ужасы", "thriller", "horror"]
    ]
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru"))
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func normalize(_ subjects: [String]) -> [String] {
        var found = Set<String>()
        for subject in subjects {
            let codes: [String: String] = ["sf_history": "science_fiction", "sf_fantasy": "fantasy", "sf": "science_fiction", "sf_space": "science_fiction", "love_history": "historical_fiction", "prose_history": "historical_fiction", "sci_history": "history", "sci_psychology": "psychology", "sci_economy": "business", "nonf_biography": "biography"]
            if let genre = codes[subject] { found.insert(genre); continue }
            if aliases[subject] != nil { found.insert(subject); continue }
            let text = normalized(subject)
            guard !text.isEmpty else { continue }
            if text.contains("history and criticism") || text.contains("история и критика") { continue }
            if text.contains("historical fiction") || text.contains("historical romance") || text.contains("историческ") && text.contains("роман") {
                found.insert("historical_fiction"); continue
            }
            for (id, terms) in aliases where terms.contains(where: {
                let term = normalized($0)
                return text == term || text.hasPrefix(term + " ") || text.hasSuffix(" " + term)
            }) { found.insert(id) }
        }
        return found.sorted()
    }
    static func language(_ value: String?) -> String? {
        guard let value else { return nil }
        let values = normalized(value).split(separator: " ").map(String.init)
        if values.contains(where: { ["ru", "rus", "russian", "русский"].contains($0) }) { return "ru" }
        if values.contains(where: { ["en", "eng", "english", "английский"].contains($0) }) { return "en" }
        return nil
    }
    static func matchesLanguage(_ actual: String?, requested: String?) -> Bool {
        guard let requested, requested != "all" else { return true }
        return language(actual) == language(requested)
    }
}

enum PublicationDate {
    static func year(_ value: String?) -> Int? {
        guard let value, value.count >= 4, let year = Int(value.prefix(4)), (1000...3000).contains(year) else { return nil }
        return year
    }
    static func isRecent(_ value: String?, now: Date = Date()) -> Bool {
        guard let year = year(value) else { return false }
        let current = Calendar(identifier: .gregorian).component(.year, from: now)
        return (current - 1...current).contains(year)
    }
}
