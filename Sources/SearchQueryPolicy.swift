import Foundation

/// Verified edition names supplement a literal search; they never fabricate catalog entries.
enum SearchQueryPolicy {
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }
    static func variants(_ query: String, byAuthor: Bool = false) -> [String] {
        let literal = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalized(literal)
        var values = [literal]
        let aliases: [String: [String]] = byAuthor ? [
            "шантель тессье": ["Тессье", "Тессье Шанталь"],
            "шанталь тессье": ["Тессье"],
            "sara cate": ["Сара Кейт"], "сара кейт": ["Sara Cate"],
            "navessa allen": ["Навесса Аллен"], "навесса аллен": ["Navessa Allen"]
        ] : [
            "praise": ["Похвали меня"], "похвали меня": ["Praise"],
            "поцелуй с тенью": ["Lights Out"], "lights out": ["Поцелуй с тенью"],
            "ритуал шантель тессье": ["Лорд и Избранная", "Ритуал"],
            "ритуал шанталь тессье": ["Лорд и Избранная", "Ритуал"],
            "the ritual": ["Лорд и Избранная"],
            "лондонский туман здесь нет места любви": ["Здесь нет места любви"],
            "лондонский туман без любви здесь не выжить": ["Без любви здесь не выжить"]
        ]
        values += aliases[key] ?? []
        if literal.contains("ё") { values.append(literal.replacingOccurrences(of: "ё", with: "е")) }
        let unpunctuated = literal.replacingOccurrences(of: "[«»\".,:;!?—–]+", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if normalized(unpunctuated) == key && unpunctuated != literal { values.append(unpunctuated) }
        var seen = Set<String>()
        return Array(values.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(3))
    }
    static func score(title: String, author: String, query: String, byAuthor: Bool = false) -> Int {
        let value = normalized(byAuthor ? author : title.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression))
        let keys = variants(query, byAuthor: byAuthor).map(normalized)
        if keys.contains(value) { return 10_000 }
        let tokens = normalized(query).split(separator: " ")
        let haystack = normalized(title + " " + author)
        let matches = tokens.filter { haystack.contains($0) }.count
        return matches * 100 + (keys.contains(where: { !$0.isEmpty && value.contains($0) }) ? 1000 : 0)
    }
}
