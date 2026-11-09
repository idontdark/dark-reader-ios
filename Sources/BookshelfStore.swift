import Foundation
import ImageIO

@MainActor
final class BookshelfStore: ObservableObject {
    @Published private(set) var books: [LocalBook] = []
    private(set) var deletions: [String: Date] = [:]

    /// Set by the sync manager. Cloud merges deliberately do not trigger this.
    var onLocalChange: (() -> Void)?

    private let fileManager = FileManager.default
    private var downloadSessions: [String: URLSession] = [:]

    private var directory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Books", isDirectory: true)
    }

    private var indexURL: URL { directory.appendingPathComponent("books.json") }
    private var deletionsURL: URL { directory.appendingPathComponent("deletions.json") }

    init() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([LocalBook].self, from: data) {
            books = decoded
        }
        if let data = try? Data(contentsOf: deletionsURL),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            deletions = decoded
        }
    }

    func fileURL(for book: LocalBook) -> URL {
        directory.appendingPathComponent(book.filename)
    }

    func addImportedFile(from source: URL, title: String, author: String = "Неизвестный автор") async throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let prepared = try await BookFormatConverter.prepare(source)
        try validateEPUB(prepared)
        try await BookFormatConverter.validateContainer(prepared)
        let filename = UUID().uuidString + "." + BookFileValidator.storedExtension(prepared.lastPathComponent)
        try fileManager.copyItem(at: prepared, to: directory.appendingPathComponent(filename))
        let metadata = try? await BookMetadata.read(prepared)
        var imported = LocalBook(title: metadata?.title ?? title, author: metadata?.author ?? author, filename: filename)
        imported.coverURL = saveCover(metadata?.cover, id: imported.id)
        books.insert(imported, at: 0)
        persist(localChange: true)
    }

    func download(_ book: CatalogBook, progress: (@MainActor (Double) -> Void)? = nil, resumeData: Data? = nil) async throws {
        guard !books.contains(where: { $0.catalogID == book.id }) else { return }
        guard let epubURL = book.epubURL, ["http", "https"].contains(epubURL.scheme ?? "") else { throw ReaderError.noEPUB }
        let delegate = ReaderDownloadDelegate { value in
            Task { @MainActor in progress?(value) }
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        downloadSessions[book.id] = session
        defer {
            if downloadSessions[book.id] === session { downloadSessions[book.id] = nil }
            session.finishTasksAndInvalidate()
        }
        let temporaryURL: URL
        let response: URLResponse
        if let resumeData {
            (temporaryURL, response) = try await session.download(resumeFrom: resumeData)
        } else {
            (temporaryURL, response) = try await session.download(from: epubURL)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ReaderError.invalidEPUB
        }
        // Some OPDS and direct links don't include a file extension.
        // Detect a supported format using the response and a short file signature.
        let accepted = BookFileValidator.importExtensions
        let declared = (book.downloadFormat ?? epubURL.pathExtension).lowercased()
        let mime = http.mimeType?.lowercased() ?? ""
        let type: String
        if accepted.contains(declared) {
            type = declared
        } else if mime == "application/pdf" { type = "pdf"
        } else if mime.contains("rtf") { type = "rtf"
        } else if mime == "text/plain" { type = "txt"
        } else if mime == "text/html", declared == "html" || declared == "htm" { type = "html"
        } else if mime.contains("epub") {
            type = "epub"
        } else if mime.contains("fictionbook") || mime.contains("fb2") {
            type = "fb2"
        } else if mime.contains("mobipocket") {
            type = "mobi"
        } else if mime == "application/zip" {
            type = "zip"
        } else {
            let handle = try FileHandle(forReadingFrom: temporaryURL)
            defer { try? handle.close() }
            let first = try handle.read(upToCount: 256) ?? Data()
            let header = String(decoding: first, as: UTF8.self).lowercased()
            if first.starts(with: Data("%PDF-".utf8)) { type = "pdf" }
            else if first.count >= 68 && String(decoding: first[60..<68], as: UTF8.self) == "BOOKMOBI" {
                type = "mobi"
            } else if first.starts(with: [0x50, 0x4B]) {
                type = header.contains("application/epub+zip") ? "epub" : "zip"
            } else if header.contains("fictionbook") {
                type = "fb2"
            } else {
                throw ImportFormatError.unsupported
            }
        }
        let length = (try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let totalLength = http.statusCode == 206
            ? http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) }
            : (response.expectedContentLength > 0 ? response.expectedContentLength : nil)
        if let totalLength, http.value(forHTTPHeaderField: "Content-Encoding") == nil,
           length != totalLength { throw ReaderError.invalidEPUB }
        guard length > 0 && length <= 50 * 1024 * 1024 else { throw ImportFormatError.oversized }
        let staging = fileManager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + "." + type
        )
        try fileManager.moveItem(at: temporaryURL, to: staging)
        defer { try? fileManager.removeItem(at: staging) }
        let prepared = try await BookFormatConverter.prepare(staging)
        try validateEPUB(prepared)
        try await BookFormatConverter.validateContainer(prepared)
        let filename = UUID().uuidString + "." + BookFileValidator.storedExtension(prepared.lastPathComponent)
        try fileManager.copyItem(at: prepared, to: directory.appendingPathComponent(filename))
        var imported = LocalBook(title: book.title, author: book.author, filename: filename)
        let metadata = try? await BookMetadata.read(prepared)
        imported.coverURL = saveCover(metadata?.cover, id: imported.id) ?? book.coverURL
        imported.catalogID = book.id
        imported.isFavorite = CatalogBookmarks.decode(UserDefaults.standard.string(forKey:CatalogBookmarks.favoritesKey) ?? "[]").contains {$0.id == book.id}
        RecommendationProfile.record(title: book.title, author: book.author, weight: 1, genre: book.genres?.first, series: book.series)
        books.insert(imported, at: 0)
        CatalogBookmarks.downloaded(book)
        progress?(1.0)
        persist(localChange: true)
    }

    func prepareForReading(_ book: LocalBook, explicitLocation: String?) async -> LocalBook {
        guard LegacyReaderUpgrade.canUpgrade(locatorJSON: book.locatorJSON, bookmarks: book.bookmarks, explicitLocation: explicitLocation),
              let prepared = try? await BookFormatConverter.optimizedLegacyCopy(fileURL(for: book), title: book.title, author: book.author) else { return book }
        defer { try? fileManager.removeItem(at: prepared) }
        guard let index = books.firstIndex(where: { $0.id == book.id && $0.filename == book.filename }),
              LegacyReaderUpgrade.canUpgrade(locatorJSON: books[index].locatorJSON, bookmarks: books[index].bookmarks, explicitLocation: explicitLocation) else { return book }
        do {
            let filename = UUID().uuidString + ".epub"
            try fileManager.copyItem(at: prepared, to: directory.appendingPathComponent(filename))
            // Keep the original EPUB on disk so the migration is reversible.
            books[index].filename = filename
            books[index].locatorJSON = nil
            persist(localChange: false)
            return books[index]
        } catch { return book }
    }

    /// Backfill existing imported EPUBs without a network request or a full Readium open.
    func recoverEmbeddedCovers() async {
        for book in books where book.coverURL == nil || (book.coverURL?.isFileURL == true && !fileManager.fileExists(atPath: book.coverURL!.path)) {
            guard !Task.isCancelled else { return }
            guard let metadata = try? await BookMetadata.read(fileURL(for: book)),
                  let url = saveCover(metadata.cover, id: book.id),
                  let index = books.firstIndex(where: { $0.id == book.id }) else { continue }
            books[index].coverURL = url
            persist(localChange: false)
        }
    }
    private func saveCover(_ data: Data?, id: UUID) -> URL? {
        guard let data, data.count <= 8_000_000, CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
        let covers = directory.deletingLastPathComponent().appendingPathComponent("BookCovers", isDirectory: true)
        let target = covers.appendingPathComponent(id.uuidString + ".img")
        do {
            try fileManager.createDirectory(at: covers, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            return target
        } catch { return nil }
    }

    func pauseDownload(_ id: String, saveResumeData: @escaping @MainActor (Data?) -> Void) {
        guard let session = downloadSessions[id] else { return }
        session.getAllTasks { tasks in
            for task in tasks {
                guard let download = task as? URLSessionDownloadTask else { continue }
                download.cancel(byProducingResumeData: { data in
                    Task { @MainActor in saveResumeData(data) }
                })
            }
        }
    }

    /// Import supported books from a direct HTTPS URL, including extensionless links.
    func downloadFromURL(_ url: URL, progress: (@MainActor (Double) -> Void)? = nil) async throws {
        guard ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw ReaderError.invalidCatalogURL }
        let name = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "Книга"
        let item = CatalogBook(id: url.absoluteString, title: name.isEmpty ? "Книга" : name,
                               author: "Неизвестный автор", epubURL: url)
        try await download(item, progress: progress)
    }

    func savePosition(bookID: UUID, locatorJSON: String?) {
        guard let i = books.firstIndex(where: { $0.id == bookID }),
              books[i].locatorJSON != locatorJSON else { return }
        RecommendationProfile.record(title: books[i].title, author: books[i].author, weight: 3)
        books[i].locatorJSON = locatorJSON
        books[i].updatedAt = Date()
        persist(localChange: true)
    }

    func toggleFavorite(_ book: LocalBook) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i].isFavorite = !(books[i].isFavorite ?? false)
        if books[i].isFavorite != true,let catalogID=books[i].catalogID {
            let items=CatalogBookmarks.decode(UserDefaults.standard.string(forKey:CatalogBookmarks.favoritesKey) ?? "[]")
            if let item=items.first(where:{$0.id == catalogID}) {CatalogBookmarks.set(item,key:CatalogBookmarks.favoritesKey,enabled:false)}
        }
        if books[i].isFavorite == true { RecommendationProfile.record(title: book.title, author: book.author, weight: 4) }
        books[i].updatedAt = Date()
        persist(localChange: true)
    }

    func saveBookmark(bookID: UUID, locatorJSON: String) {
        guard let i = books.firstIndex(where: { $0.id == bookID }) else { return }
        var all = books[i].bookmarks ?? []
        guard !all.contains(locatorJSON) else { return }
        all.append(locatorJSON)
        books[i].bookmarks = all
        books[i].updatedAt = Date()
        persist(localChange: true)
    }

    func renameBookmark(bookID:UUID,index:Int,name:String) {
        guard let i=books.firstIndex(where:{$0.id == bookID}),var marks=books[i].bookmarks,
              marks.indices.contains(index),let bytes=marks[index].data(using:.utf8),
              var json=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] else{return}
        json["title"]=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let data=try? JSONSerialization.data(withJSONObject:json) else{return}
        marks[index]=String(decoding:data,as:UTF8.self);books[i].bookmarks=marks
        books[i].updatedAt=Date();persist(localChange:true)
    }
    func deleteBookmark(bookID:UUID,index:Int) {
        guard let i=books.firstIndex(where:{$0.id == bookID}),var marks=books[i].bookmarks,marks.indices.contains(index) else{return}
        marks.remove(at:index);books[i].bookmarks=marks;books[i].updatedAt=Date();persist(localChange:true)
    }

    func delete(_ book: LocalBook) {
        deletions[book.id.uuidString] = Date()
        try? fileManager.removeItem(at: fileURL(for: book))
        books.removeAll { $0.id == book.id }
        persist(localChange: true)
    }

    /// Merge remote metadata with local state and move already-downloaded staged EPUBs
    /// into Documents/Books. Never remove an EPUB that has no newer tombstone.
    func mergeFromCloud(_ remote: [LocalBook], tombstones: [String: Date], staged: [String: URL]) throws {
        for (id, date) in tombstones {
            if date > (deletions[id] ?? .distantPast) { deletions[id] = date }
        }

        var winners: [UUID: LocalBook] = [:]
        for item in books {
            if let previous = winners[item.id], previous.changeDate >= item.changeDate { continue }
            winners[item.id] = item
        }
        for item in remote {
            if let local = winners[item.id] {
                if let stagedFile = staged[item.id.uuidString],
                   !fileManager.fileExists(atPath: fileURL(for: local).path) {
                    try validateEPUB(stagedFile)
                    try fileManager.moveItem(at: stagedFile, to: fileURL(for: local))
                }
                var newer = item.changeDate > local.changeDate ? item : local
                newer.filename = local.filename
                newer.bookmarks = Array(Set((local.bookmarks ?? []) + (item.bookmarks ?? []))).sorted()
                winners[item.id] = newer
            } else if let stagedFile = staged[item.id.uuidString] {
                try validateEPUB(stagedFile)
                let filename = UUID().uuidString + "." + BookFileValidator.storedExtension(item.filename)
                try fileManager.moveItem(at: stagedFile, to: directory.appendingPathComponent(filename))
                var incoming = item
                incoming.filename = filename
                winners[item.id] = incoming
            }
        }
        var merged: [LocalBook] = []
        for item in winners.values {
            if let deletedAt = deletions[item.id.uuidString], deletedAt >= item.changeDate {
                try? fileManager.removeItem(at: fileURL(for: item))
            } else {
                merged.append(item)
            }
        }
        books = merged.sorted { $0.addedAt > $1.addedAt }
        persist(localChange: false)
    }

    func restoreFromFile(_ remote:[LocalBook],staged:[String:URL]) throws {
        let previous=deletions
        for book in remote {deletions.removeValue(forKey:book.id.uuidString)}
        do {try mergeFromCloud(remote,tombstones:[:],staged:staged);restoreReadingMetadata(remote)}
        catch {deletions=previous;throw error}
    }
    /// Metadata-only restoration cannot create entries pointing to missing book files.
    func restoreReadingMetadata(_ remote: [LocalBook]) {
        for item in remote {
            guard let index = books.firstIndex(where: {
                $0.id == item.id || (item.catalogID != nil && $0.catalogID == item.catalogID)
            }) else { continue }
            books[index].locatorJSON = item.locatorJSON
            books[index].bookmarks = Array(Set((books[index].bookmarks ?? []) + (item.bookmarks ?? []))).sorted()
            books[index].updatedAt = Date()
        }
        persist(localChange: true)
    }
    private func persist(localChange: Bool) {
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: indexURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(deletions) {
            try? data.write(to: deletionsURL, options: .atomic)
        }
        if localChange { onLocalChange?() }
    }

    private func validateEPUB(_ url: URL) throws { try BookFileValidator.validate(url) }

}


/// Reports actual bytes received instead of simulating download percentages.
private final class ReaderDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let update: (Double) -> Void

    init(update: @escaping (Double) -> Void) {
        self.update = update
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { if totalBytesWritten>0 { update(0) };return }
        update(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
