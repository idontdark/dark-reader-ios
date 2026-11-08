import Foundation
import SwiftUI
import BackgroundTasks

@MainActor
final class CloudSyncManager: ObservableObject {
    @Published private(set) var folderName: String?
    @Published private(set) var automatic: Bool
    @Published private(set) var enabled:Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var isConnecting=false
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
        if !UserDefaults.standard.bool(forKey:"cloudSync.explicitOptIn") {
            UserDefaults.standard.set(false,forKey:"cloudSync.automatic")
            UserDefaults.standard.set(false,forKey:"cloudSync.enabled")
            UserDefaults.standard.set(true,forKey:"cloudSync.explicitOptIn")
        }
        enabled=UserDefaults.standard.bool(forKey:"cloudSync.enabled")
        folderName = UserDefaults.standard.string(forKey: "cloudSync.folderName")
        automatic = UserDefaults.standard.bool(forKey: "cloudSync.automatic")
        lastSavedAt = UserDefaults.standard.object(forKey: "cloudSync.lastSaved") as? Date
        if enabled,folderName != nil {
            status = "Готово к синхронизации"
        }
        if !enabled {status="Сохранение в iCloud выключено"}
    }

    var isConnected: Bool { defaults.data(forKey: bookmarkKey) != nil }

    func attach(_ books: BookshelfStore) {
        bookStore = books
        GoogleDriveBackup.shared.attach(books,cloud:self)
        books.onLocalChange = { [weak self] in self?.requestSync() }
    }

    func chooseFolder(_ url: URL) async {
        guard !isConnecting,!isSyncing else{return}
        isConnecting=true
        defer {isConnecting=false}
        do {
            CloudConnectionDiagnostics.record("connection.begin")
            status="Подключаем папку Dark Reader…"
            let bookmark = try await Task.detached(priority:.utility) {
                try CloudFolderConnection.prepare(url)
            }.value
            guard await synchronize(using:bookmark) else{return}
            defaults.set(bookmark, forKey: bookmarkKey)
            defaults.set("Dark Reader", forKey: "cloudSync.folderName")
            defaults.set(true, forKey: "cloudSync.automatic")
            folderName = "Dark Reader"
            automatic = true
            enabled=true
            defaults.set(true,forKey:"cloudSync.enabled")
            CloudConnectionDiagnostics.record("connection.verified")
            CloudBackgroundSync.schedule()
        } catch {
            CloudConnectionDiagnostics.record("connection.failed",error:error)
            status = "Не удалось сохранить доступ: \(L10n.errorDescription(error))"
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

    func setEnabled(_ value:Bool) async -> Bool {
        if !value {
            enabled=false;automatic=false;queued?.cancel()
            defaults.set(false,forKey:"cloudSync.enabled")
            defaults.set(false,forKey:"cloudSync.automatic")
            status="Сохранение в iCloud выключено. Резервные копии в облаке сохранены."
            return true
        }
        if isConnected {
            guard let bookmark=defaults.data(forKey:bookmarkKey) else{return false}
            if await synchronize(using:bookmark) {
                enabled=true;automatic=true
                defaults.set(true,forKey:"cloudSync.enabled")
                defaults.set(true,forKey:"cloudSync.automatic")
                CloudBackgroundSync.schedule()
            }
            return true
        }
        return await connectDefaultFolder()
    }

    func forgetFolder() {
        queued?.cancel()
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: "cloudSync.folderName")
        defaults.set(false, forKey: "cloudSync.automatic")
        folderName = nil
        automatic = false
        enabled=false
        defaults.set(false,forKey:"cloudSync.enabled")
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
        GoogleDriveBackup.shared.requestBackup()
        guard enabled,automatic, isConnected else { return }
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
        guard enabled,let bookmark=defaults.data(forKey:bookmarkKey) else{return false}
        return await synchronize(using:bookmark)
    }

    private func synchronize(using bookmark:Data) async -> Bool {
        guard let store=bookStore else{return false}
        if isSyncing {
            retryAfterCurrentRun = true
            return false
        }

        isSyncing = true
        CloudConnectionDiagnostics.record("backup.begin")
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
            CloudConnectionDiagnostics.record(result.missingFiles == 0 ? "backup.saved":"backup.missing-files")
            return result.missingFiles == 0
        } catch {
            CloudConnectionDiagnostics.record("backup.failed",error:error)
            status = "Не удалось синхронизировать: \(L10n.errorDescription(error))"
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

    func makeSnapshot() -> CloudLibrarySnapshot? {
        guard let store=bookStore else{return nil}
        return CloudLibrarySnapshot(schema:1,deviceID:deviceID(),savedAt:Date(),books:store.books,
                                    deletions:store.deletions,settings:collectSettings(),
                                    settingsChangedAt:defaults.object(forKey:settingsDateKey) as? Date ?? .distantPast)
    }
    func restoreSettings(_ values:[String:String],changedAt:Date) {
        applySettings(values);defaults.set(changedAt,forKey:settingsDateKey)
    }
    /// A signed build with iCloud Documents can use its own container. Other
    /// signatures select iCloud Drive once through Files; no private path is used.
    func connectDefaultFolder() async -> Bool {
        let container=await Task.detached(priority:.utility) {
            FileManager.default.url(forUbiquityContainerIdentifier:nil)
        }.value
        guard let container else {CloudConnectionDiagnostics.record("container.unavailable");return false}
        let documents=container.appendingPathComponent("Documents",isDirectory:true)
        do {try await Task.detached(priority:.utility) {
            try FileManager.default.createDirectory(at:documents,withIntermediateDirectories:true)
        }.value}
        catch {status="Не удалось создать папку iCloud: \(L10n.errorDescription(error))";return false}
        await chooseFolder(documents)
        return true
    }

    private func collectSettings() -> [String: String] {
        let keys = [
            "readerTheme", "readerFont", "readerFontSize", "readerScroll", "readerProgressDisplay",
            "appTheme", "appAppearance", "accentHex", "readerBackgroundHex", "readerTextHex",
            "appLanguage", "preferredBookLanguage", "preferredGenresJSON",
            "preferredAuthorsJSON", "wantsBooks", "wantsAudiobooks", "savedOPDSCatalogs", "favoriteBooksJSON",
            "catalog.wishlistJSON", "catalog.favoritesJSON", "discovery.wishlistJSON"
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
                 "preferredBookLanguage", "preferredGenresJSON", "preferredAuthorsJSON", "savedOPDSCatalogs", "favoriteBooksJSON",
                 "catalog.wishlistJSON", "catalog.favoritesJSON", "discovery.wishlistJSON":
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
