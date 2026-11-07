import Foundation
import SwiftUI
import BackgroundTasks

@MainActor
final class CloudSyncManager: ObservableObject {
    @Published private(set) var folderName: String?
    @Published private(set) var automatic: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var status = "Выберите папку в iCloud Drive"
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var restoredBooks = 0

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "cloudSync.folderBookmark"
    private let deviceKey = "cloudSync.deviceID"
    private let settingsDateKey = "cloudSync.settingsDate"
    private var bookStore: BookshelfStore?
    private var queued: Task<Void, Never>?
    private var retryAfterCurrentRun = false
    private var remotelyAppliedSettings: [String: String] = [:]
    private var remotelyAppliedUntil = Date.distantPast

    init() {
        folderName = UserDefaults.standard.string(forKey: "cloudSync.folderName")
        automatic = UserDefaults.standard.bool(forKey: "cloudSync.automatic")
        lastSavedAt = UserDefaults.standard.object(forKey: "cloudSync.lastSaved") as? Date
        if folderName != nil {
            status = "Готово к синхронизации"
        }
    }

    var isConnected: Bool { defaults.data(forKey: bookmarkKey) != nil }

    func attach(_ books: BookshelfStore) {
        bookStore = books
        books.onLocalChange = { [weak self] in self?.requestSync() }
    }

    func chooseFolder(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        guard accessed else {
            status = "Не удалось получить доступ к папке"
            return
        }
        do {
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil
            )
            url.stopAccessingSecurityScopedResource()
            defaults.set(bookmark, forKey: bookmarkKey)
            defaults.set(url.lastPathComponent, forKey: "cloudSync.folderName")
            defaults.set(true, forKey: "cloudSync.automatic")
            folderName = url.lastPathComponent
            automatic = true
            status = "Папка подключена"
            _ = await syncNow()
            CloudBackgroundSync.schedule()
        } catch {
            url.stopAccessingSecurityScopedResource()
            status = "Не удалось сохранить доступ: \(error.localizedDescription)"
        }
    }

    func setAutomatic(_ value: Bool) {
        guard isConnected else { return }
        automatic = value
        defaults.set(value, forKey: "cloudSync.automatic")
        if value {
            requestSync()
            CloudBackgroundSync.schedule()
        } else {
            queued?.cancel()
            status = "Автоматическое сохранение выключено"
        }
    }

    func forgetFolder() {
        queued?.cancel()
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: "cloudSync.folderName")
        defaults.set(false, forKey: "cloudSync.automatic")
        folderName = nil
        automatic = false
        status = "Выберите папку в iCloud Drive"
        // Files already saved in iCloud Drive are never deleted here.
    }

    func settingsChanged(key: String, value: String) {
        // @AppStorage also emits change events when a remote setting is restored.
        // Ignore those echoes, otherwise devices can keep re-uploading identical values.
        if Date() < remotelyAppliedUntil, let expected = remotelyAppliedSettings[key] {
            let matches: Bool
            if key == "readerScroll" {
                matches = (expected == "1" || expected.lowercased() == "true") ==
                          (value == "1" || value.lowercased() == "true")
            } else if key == "readerFontSize", let a = Double(expected), let b = Double(value) {
                matches = abs(a - b) < 0.001
            } else {
                matches = expected == value
            }
            if matches { return }
        }
        defaults.set(Date(), forKey: settingsDateKey)
        requestSync()
    }

    func requestSync() {
        guard automatic, isConnected else { return }
        if isSyncing {
            retryAfterCurrentRun = true
            return
        }
        queued?.cancel()
        queued = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_500_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            _ = await self?.syncNow()
        }
    }

    @discardableResult
    func syncNow() async -> Bool {
        guard let bookmark = defaults.data(forKey: bookmarkKey),
              let store = bookStore else { return false }
        if isSyncing {
            retryAfterCurrentRun = true
            return false
        }

        isSyncing = true
        status = "Сохраняем и проверяем библиотеку…"
        defer {
            isSyncing = false
            if retryAfterCurrentRun {
                retryAfterCurrentRun = false
                requestSync()
            }
        }

        let snapshot = CloudLibrarySnapshot(
            schema: 1,
            deviceID: deviceID(),
            savedAt: Date(),
            books: store.books,
            deletions: store.deletions,
            settings: collectSettings(),
            settingsChangedAt: defaults.object(forKey: settingsDateKey) as? Date ?? .distantPast
        )
        let localBooks = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Books", isDirectory: true)

        do {
            let result = try await Task.detached(priority: .utility) {
                try CloudFolderWorker(
                    bookmark: bookmark,
                    localBooksDirectory: localBooks,
                    snapshots: snapshot
                ).execute()
            }.value

            try store.mergeFromCloud(
                result.books, tombstones: result.deletions, staged: result.staged
            )
            if result.settingsChangedAt >
                (defaults.object(forKey: settingsDateKey) as? Date ?? .distantPast) {
                applySettings(result.settings)
                defaults.set(result.settingsChangedAt, forKey: settingsDateKey)
            }

            restoredBooks = result.restoredCount
            lastSavedAt = Date()
            defaults.set(lastSavedAt, forKey: "cloudSync.lastSaved")
            if result.missingFiles > 0 {
                status = "Сохранено, но \(result.missingFiles) файлов пока недоступны"
            } else if result.restoredCount > 0 {
                status = "Библиотека восстановлена: \(result.restoredCount) книг"
            } else {
                status = "Данные сохранены в выбранной папке"
            }
            return result.missingFiles == 0
        } catch {
            status = "Не удалось синхронизировать: \(error.localizedDescription)"
            return false
        }
    }

    private func deviceID() -> String {
        if let known = defaults.string(forKey: deviceKey), UUID(uuidString: known) != nil {
            return known
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: deviceKey)
        return id
    }

    private func collectSettings() -> [String: String] {
        let keys = [
            "readerTheme", "readerFont", "readerFontSize", "readerScroll", "readerProgressDisplay",
            "appTheme", "appAppearance", "accentHex", "readerBackgroundHex", "readerTextHex",
            "appLanguage", "preferredBookLanguage", "preferredGenresJSON",
            "preferredAuthorsJSON", "wantsBooks", "wantsAudiobooks", "savedOPDSCatalogs", "favoriteBooksJSON"
        ]
        var values: [String: String] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                values[key] = String(describing: value)
            }
        }
        return values
    }

    private func applySettings(_ values: [String: String]) {
        remotelyAppliedSettings = values
        remotelyAppliedUntil = Date(timeIntervalSinceNow: 5)
        for (key, value) in values {
            switch key {
            case "readerProgressDisplay":
                if ["percent","pages"].contains(value) { defaults.set(value,forKey:key) }
            case "readerFontSize":
                if let size = Double(value), size >= 0.7, size <= 3.0 {
                    defaults.set(size, forKey: key)
                }
            case "readerScroll", "wantsBooks", "wantsAudiobooks":
                defaults.set(value == "1" || value.lowercased() == "true", forKey: key)
            case "readerTheme", "readerFont", "appTheme", "appAppearance", "accentHex",
                 "readerBackgroundHex", "readerTextHex", "appLanguage",
                 "preferredBookLanguage", "preferredGenresJSON", "preferredAuthorsJSON", "savedOPDSCatalogs", "favoriteBooksJSON":
                defaults.set(value, forKey: key)
            default:
                break
            }
        }
    }
}

/// Best-effort background refresh. iOS decides whether and when to run it.
enum CloudBackgroundSync {
    static let identifier = "com.ipadark.reader.sync"

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            let work = Task { @MainActor in
                let success = await DarkReaderAppState.shared.sync.syncNow()
                refresh.setTaskCompleted(success: success)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Keep a single consistent store when the app is launched for background tasks.
@MainActor
final class DarkReaderAppState {
    static let shared = DarkReaderAppState()
    let books = BookshelfStore()
    let sync = CloudSyncManager()

    private init() {
        sync.attach(books)
    }
}
