import Foundation

/// Stored inside a user-selected directory. One manifest per installation avoids
/// competing writes to a single books.json from two different devices.
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

/// File-provider and iCloud Drive operations run off the main thread.
/// No CloudKit entitlements or shared Apple developer Team ID are required.
struct CloudFolderWorker: Sendable {
    let bookmark: Data
    let localBooksDirectory: URL
    let snapshots: CloudLibrarySnapshot

    func execute() throws -> CloudSyncResult {
        var stale = false
        let selectedFolder = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale else { throw CloudSyncError.expiredBookmark }
        let scoped=selectedFolder.startAccessingSecurityScopedResource()
        defer { if scoped {selectedFolder.stopAccessingSecurityScopedResource()} }

        let root = selectedFolder.lastPathComponent == "Dark Reader" ? selectedFolder : selectedFolder.appendingPathComponent("Dark Reader", isDirectory: true)
        let deviceFolder = root.appendingPathComponent("Devices", isDirectory: true)
        let cloudBooks = root.appendingPathComponent("Books", isDirectory: true)
        try makeCoordinatedDirectory(root)
        try makeCoordinatedDirectory(deviceFolder)
        try makeCoordinatedDirectory(cloudBooks)

        let fileManager = FileManager.default
        let manifestURLs = try fileManager.contentsOfDirectory(
            at: deviceFolder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        // Bound the amount of metadata we parse from a user-selected directory.
        guard manifestURLs.count <= 100 else { throw CloudSyncError.invalidSnapshot }

        var allSnapshots: [CloudLibrarySnapshot] = [snapshots]
        for manifest in manifestURLs {
            try Task.checkCancellation()
            let data = try coordinatedRead(manifest, limit: 5_000_000)
            let decoded = try JSONDecoder().decode(CloudLibrarySnapshot.self, from: data)
            guard decoded.schema == 1, UUID(uuidString: decoded.deviceID) != nil,
                  decoded.books.count <= 10_000 else {
                throw CloudSyncError.invalidSnapshot
            }
            allSnapshots.append(decoded)
        }

        var allBooks: [UUID: LocalBook] = [:]
        var tombstones: [String: Date] = [:]
        var newestSettings = snapshots.settings
        var settingsDate = snapshots.settingsChangedAt

        for manifest in allSnapshots {
            for book in manifest.books {
                if let current = allBooks[book.id] {
                    var latest = book.changeDate > current.changeDate ? book : current
                    latest.bookmarks = Array(Set((current.bookmarks ?? []) + (book.bookmarks ?? []))).sorted()
                    allBooks[book.id] = latest
                } else {
                    allBooks[book.id] = book
                }
            }
            for (id, deletion) in manifest.deletions {
                if deletion > (tombstones[id] ?? .distantPast) { tombstones[id] = deletion }
            }
            if manifest.settingsChangedAt > settingsDate {
                newestSettings = manifest.settings
                settingsDate = manifest.settingsChangedAt
            }
        }

        var locallyPresent: [UUID: LocalBook] = [:]
        for book in snapshots.books { locallyPresent[book.id] = book }
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("DarkReaderRestore-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        var staged: [String: URL] = [:]
        var kept: [LocalBook] = []
        var missing = 0

        for var book in allBooks.values {
            try Task.checkCancellation()
            if let deleted = tombstones[book.id.uuidString], deleted >= book.changeDate {
                continue
            }
            let cloudFile = cloudBooks.appendingPathComponent(book.id.uuidString + ".epub")
            if let local = locallyPresent[book.id],
               fileManager.fileExists(atPath: localBooksDirectory.appendingPathComponent(local.filename).path) {
                book.filename = local.filename
                if !fileManager.fileExists(atPath: cloudFile.path) {
                    let localURL = localBooksDirectory.appendingPathComponent(local.filename)
                    let bytes = try localEPUBData(localURL)
                    try coordinatedWrite(bytes, at: cloudFile)
                }
                kept.append(book)
            } else if fileManager.fileExists(atPath: cloudFile.path) {
                let bytes = try coordinatedRead(cloudFile, limit: 50 * 1024 * 1024)
                guard bytes.count > 4, bytes.starts(with: [0x50, 0x4B]) else {
                    throw CloudSyncError.badBook
                }
                let stagedURL = staging.appendingPathComponent(book.id.uuidString + ".epub")
                try bytes.write(to: stagedURL, options: .atomic)
                staged[book.id.uuidString] = stagedURL
                book.filename = book.id.uuidString + ".epub"
                kept.append(book)
            } else {
                // Never report a book as restored when its EPUB isn't available.
                missing += 1
            }
        }

        kept.sort { $0.addedAt > $1.addedAt }
        let saved = CloudLibrarySnapshot(
            schema: 1,
            deviceID: snapshots.deviceID,
            savedAt: Date(),
            books: kept,
            deletions: tombstones,
            settings: newestSettings,
            settingsChangedAt: settingsDate
        )
        let encoded = try JSONEncoder().encode(saved)
        guard encoded.count <= 5_000_000 else { throw CloudSyncError.invalidSnapshot }
        let ourManifest = deviceFolder.appendingPathComponent(snapshots.deviceID + ".json")
        try coordinatedWrite(encoded, at: ourManifest)

        return CloudSyncResult(
            books: kept, deletions: tombstones, staged: staged,
            settings: newestSettings, settingsChangedAt: settingsDate,
            missingFiles: missing, restoredCount: staged.count
        )
    }

    private func localEPUBData(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard data.count > 4, data.count <= 50 * 1024 * 1024,
              data.starts(with: [0x50, 0x4B]) else { throw CloudSyncError.badBook }
        return data
    }

    private func makeCoordinatedDirectory(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: parent, options: .forMerging, error: &coordinationError
        ) { _ in
            do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private func coordinatedRead(_ url: URL, limit: Int) throws -> Data {
        var coordinationError: NSError?
        var readError: Error?
        var bytes: Data?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [], error: &coordinationError
        ) { coordinatedURL in
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: coordinatedURL.path)
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                guard size <= limit else { throw CloudSyncError.invalidSnapshot }
                bytes = try Data(contentsOf: coordinatedURL)
                if (bytes?.count ?? 0) > limit { throw CloudSyncError.invalidSnapshot }
            } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let bytes else { throw CloudSyncError.unavailableData }
        return bytes
    }

    private func coordinatedWrite(_ data: Data, at url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { coordinatedURL in
            do { try data.write(to: coordinatedURL, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
