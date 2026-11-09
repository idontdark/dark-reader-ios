import Foundation
import SwiftUI
import BackgroundTasks

/// Shared snapshot/settings bridge for local files and Google Drive. No iCloud connection.
@MainActor
final class CloudSyncManager: ObservableObject {
    private let defaults=UserDefaults.standard
    private let settingsDateKey="cloudSync.settingsDate"
    private var bookStore:BookshelfStore?
    private var remotelyAppliedSettings:[String:String]=[:]
    private var remotelyAppliedUntil=Date.distantPast
    let automatic=false
    init() {
        defaults.set(false,forKey:"cloudSync.enabled")
        defaults.set(false,forKey:"cloudSync.automatic")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:"com.ipadark.reader.sync")
    }
    func attach(_ books:BookshelfStore) {
        SourcePreferences.migrate()
        bookStore=books
        GoogleDriveBackup.shared.attach(books,cloud:self)
        books.onLocalChange = {GoogleDriveBackup.shared.requestBackup()}
    }
    func settingsChanged(key:String,value:String) {
        if Date()<remotelyAppliedUntil,remotelyAppliedSettings[key] == value {return}
        defaults.set(Date(),forKey:settingsDateKey)
        GoogleDriveBackup.shared.requestBackup()
    }
    func requestSync() {GoogleDriveBackup.shared.requestBackup()}
    func syncNow() async -> Bool {false}
    func makeSnapshot()->CloudLibrarySnapshot? {
        guard let bookStore else{return nil}
        return CloudLibrarySnapshot(schema:1,deviceID:"local",savedAt:Date(),books:bookStore.books,deletions:bookStore.deletions,settings:collectSettings(),settingsChangedAt:defaults.object(forKey:settingsDateKey) as? Date ?? .distantPast)
    }
    func restoreSettings(_ values:[String:String],changedAt:Date) {
        applySettings(values);defaults.set(changedAt,forKey:settingsDateKey)
    }
    private func collectSettings() -> [String: String] {
        let keys = [
            "readerTheme", "readerFont", "readerFontSize", "readerScroll", "readerProgressDisplay", "readerPageAnimation", "readerPersistentProgress",
            "appTheme", "appAppearance", "accentHex", "readerBackgroundHex", "readerTextHex",
            "appLanguage", "preferredBookLanguage", "preferredGenresJSON",
            "preferredAuthorsJSON", "wantsBooks", "wantsAudiobooks", "favoriteBooksJSON",
            "catalog.wishlistJSON", "catalog.favoritesJSON", "discovery.wishlistJSON"
        ]
        var values: [String: String] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                values[key] = String(describing: value)
            }
        }
        if let data = defaults.data(forKey: SourcePreferences.key), let value = String(data: data, encoding: .utf8) { values[SourcePreferences.key] = value }
        if let value = defaults.string(forKey: "preferredAudioGenresJSON") { values["preferredAudioGenresJSON"] = value }
        return values
    }

    private func applySettings(_ values: [String: String]) {
        remotelyAppliedSettings = values
        remotelyAppliedUntil = Date(timeIntervalSinceNow: 5)
        for (key, value) in values {
            switch key {
            case "sources.enabled.v1":
                if let data = value.data(using: .utf8), (try? JSONDecoder().decode([String: Bool].self, from: data)) != nil { defaults.set(data, forKey: key) }
            case "preferredAudioGenresJSON":
                if let data = value.data(using: .utf8), (try? JSONDecoder().decode([String].self, from: data)) != nil { defaults.set(value, forKey: key) }
            case "readerProgressDisplay":
                if ["percent","pages"].contains(value) { defaults.set(value,forKey:key) }
            case "readerFontSize":
                if let size = Double(value), size >= 0.7, size <= 3.0 {
                    defaults.set(size, forKey: key)
                }
            case "readerScroll", "readerPageAnimation", "readerPersistentProgress", "wantsBooks", "wantsAudiobooks":
                defaults.set(value == "1" || value.lowercased() == "true", forKey: key)
            case "readerTheme", "readerFont", "appTheme", "appAppearance", "accentHex",
                 "readerBackgroundHex", "readerTextHex", "appLanguage",
                 "preferredBookLanguage", "preferredGenresJSON", "preferredAuthorsJSON", "favoriteBooksJSON",
                 "catalog.wishlistJSON", "catalog.favoritesJSON", "discovery.wishlistJSON":
                defaults.set(value, forKey: key)
            default:
                break
            }
        }
    }
}

enum CloudBackgroundSync { static func register() {}
 static func schedule() {} }
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
