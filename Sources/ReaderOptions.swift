import Foundation

struct ReaderOptions: Equatable, Sendable {
    let fontSize: Double
    let font: String
    let theme: String
    let scroll: Bool
    let animated: Bool
    init(fontSize: Double, font: String, theme: String, scroll: Bool, animated: Bool) {
        self.fontSize = fontSize.isFinite ? min(3, max(0.7, fontSize)) : 1.1
        self.font = font == "sans" ? "sans" : "serif"
        self.theme = ["light", "sepia", "dark", "oled"].contains(theme) ? theme : "light"
        self.scroll = scroll
        self.animated = animated && !scroll
    }
}

/// Re-chunking changes resource hrefs. Never invalidate a saved bookmark or a
/// reading position beyond the start of a book; no approximate locator migration.
enum LegacyReaderUpgrade {
    static func canUpgrade(locatorJSON: String?, bookmarks: [String]?, explicitLocation: String?) -> Bool {
        guard explicitLocation == nil, (bookmarks ?? []).isEmpty else { return false }
        guard let locatorJSON else { return true }
        guard let bytes = locatorJSON.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let locations = object["locations"] as? [String: Any],
              let progress = (locations["totalProgression"] ?? locations["progression"]) as? Double,
              progress == 0 else { return false }
        return (locations["position"] as? Int ?? 1) <= 1
    }
}
