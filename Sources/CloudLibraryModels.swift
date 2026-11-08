import Foundation

/// Versioned manifest shared by portable file backups and Google Drive.
struct CloudLibrarySnapshot: Codable, Sendable {
    let schema: Int
    let deviceID: String
    let savedAt: Date
    let books: [LocalBook]
    let deletions: [String: Date]
    let settings: [String: String]
    let settingsChangedAt: Date
}

struct CloudSyncResult: Sendable {
    let books: [LocalBook]
    let deletions: [String: Date]
    let staged: [String: URL]
    let settings: [String: String]
    let settingsChangedAt: Date
    let missingFiles: Int
    let restoredCount: Int
}

enum CloudSyncError: LocalizedError {
    case accessDenied, expiredBookmark, invalidSnapshot, unavailableData, badBook

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Нет доступа к выбранной папке. Выберите её повторно."
        case .expiredBookmark: "Доступ к папке устарел. Выберите её повторно."
        case .invalidSnapshot: "Не удалось прочитать данные резервной копии."
        case .unavailableData: "Файлы iCloud Drive пока недоступны. Повторите синхронизацию позже."
        case .badBook: "Один из EPUB-файлов в резервной копии повреждён."
        }
    }
}

