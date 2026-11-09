import Foundation

enum AudioSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case librivox, archive, knigavuhe, akniga, local, opds
    var id: String { rawValue }
    var title: String { switch self { case .librivox: "LibriVox"; case .archive: "Internet Archive"; case .knigavuhe:"Книга в ухе"; case .akniga:"Аудиокниги Клуб"; case .local: "Импортированные";case .opds:"Веб-источник" } }
    static var online: [AudioSource] { [.librivox, .archive, .knigavuhe, .akniga] }
}

struct AudioBook: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let source: AudioSource
    let sourceID: String
    let title: String
    let author: String
    let description: String
    let coverURL: URL?
    let language: String?
    var genres: [String]? = nil
    var streamURL:URL? = nil
    var feedURL:URL? = nil
    var providerID: String? = nil
    var pageURL: URL? = nil
    var narrator: String? = nil
    var durationSeconds: Double? = nil
    var publicationDate: String? = nil
    var popularity: Double? = nil
    var popularityBasis: String? = nil
    var editions: [AudioEdition]? = nil
    var recommendationReason: String? = nil
    var series: String? = nil
    var seriesNumber: Double? = nil
    var archiveURL: URL? = nil
    var sourceTitle: String { providerID.flatMap(SourceCatalog.source)?.name ?? source.title }
}

struct AudioChapter: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let url: URL
    let durationSeconds: Double?
    var startSeconds: Double? = nil
}

enum AudioCatalogError: LocalizedError {
    case unavailable, invalidReply, noTracks, invalidSearch
    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Не удалось связаться с каталогом. Проверьте интернет или попробуйте VPN."
        case .invalidReply:
            "Каталог вернул неожиданные данные. Попробуйте другой источник."
        case .noTracks:
            "Для этой аудиокниги пока нет доступных глав."
        case .invalidSearch:
            "Введите название или имя автора."
        }
    }
}

