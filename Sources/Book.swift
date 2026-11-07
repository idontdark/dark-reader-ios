import Foundation

struct LocalBook: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var author: String
    var filename: String
    var locatorJSON: String?
    var addedAt: Date

    init(title: String, author: String, filename: String) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.filename = filename
        self.addedAt = Date()
    }
}

struct CatalogBook: Identifiable, Hashable {
    var id: String
    var title: String
    var author: String
    var epubURL: URL
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
