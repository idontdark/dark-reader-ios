import Foundation

/// The optional synchronization fields keep books.json from older app versions readable.
struct LocalBook: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var author: String
    var filename: String
    var locatorJSON: String?
    var addedAt: Date
    var updatedAt: Date?
    var isFavorite: Bool?
    var bookmarks: [String]?
    var coverURL: URL?
    var catalogID: String?

    var changeDate: Date { updatedAt ?? addedAt }

    init(title: String, author: String, filename: String) {
        id = UUID()
        self.title = title
        self.author = author
        self.filename = filename
        locatorJSON = nil
        addedAt = Date()
        updatedAt = addedAt
        isFavorite = false
        bookmarks = []
        coverURL = nil
    }
}

struct CatalogBook: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var title: String
    var author: String
    var epubURL: URL?
    var navigationURL: URL? = nil
    var coverURL: URL? = nil
    var summary: String? = nil
    var downloadFormat: String? = nil
    var audioURL:URL? = nil
    var sourceID: String? = nil
    var language: String? = nil
    var genres: [String]? = nil
    var isbn: String? = nil
    var publicationDate: String? = nil
    var popularity: Double? = nil
    var popularityBasis: String? = nil
    var offers: [BookOffer]? = nil
    var recommendationReason: String? = nil
}

enum ReaderError: LocalizedError {
    case noEPUB, fileTooLarge, invalidEPUB, invalidCatalogURL, noResults, unsupportedPublication

    var errorDescription: String? {
        switch self {
        case .noEPUB: return "Источник не предоставляет EPUB-файл."
        case .fileTooLarge: return "Файл превышает ограничение 50 МБ."
        case .invalidEPUB: return "Получен неверный файл вместо EPUB."
        case .invalidCatalogURL: return "Проверьте адрес каталога в настройках."
        case .noResults: return "Поиск ничего не нашёл."
        case .unsupportedPublication: return "Этот EPUB не удалось открыть."
        }
    }
}
