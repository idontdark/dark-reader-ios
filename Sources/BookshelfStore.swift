import Foundation

@MainActor
final class BookshelfStore: ObservableObject {
    @Published private(set) var books: [LocalBook] = []
    private(set) var deletions: [String: Date] = [:]

    /// Set by the sync manager. Cloud merges deliberately do not trigger this.
    var onLocalChange: (() -> Void)?

    private let fileManager = FileManager.default

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

    func addImportedFile(from source: URL, title: String, author: String = "Неизвестный автор") throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard source.pathExtension.lowercased() == "epub" else { throw ReaderError.noEPUB }
        try validateEPUB(source)
        let filename = UUID().uuidString + ".epub"
        try fileManager.copyItem(at: source, to: directory.appendingPathComponent(filename))
        books.insert(LocalBook(title: title, author: author, filename: filename), at: 0)
        persist(localChange: true)
    }

    func download(_ book: CatalogBook) async throws {
        guard let epubURL = book.epubURL, epubURL.scheme == "https" else { throw ReaderError.noEPUB }
        let (temporaryURL, response) = try await URLSession.shared.download(from: epubURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ReaderError.invalidEPUB
        }
        try validateEPUB(temporaryURL)
        let filename = UUID().uuidString + ".epub"
        try fileManager.moveItem(at: temporaryURL, to: directory.appendingPathComponent(filename))
        books.insert(LocalBook(title: book.title, author: book.author, filename: filename), at: 0)
        persist(localChange: true)
    }

    func savePosition(bookID: UUID, locatorJSON: String?) {
        guard let i = books.firstIndex(where: { $0.id == bookID }),
              books[i].locatorJSON != locatorJSON else { return }
        books[i].locatorJSON = locatorJSON
        books[i].updatedAt = Date()
        persist(localChange: true)
    }

    func toggleFavorite(_ book: LocalBook) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i].isFavorite = !(books[i].isFavorite ?? false)
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

        let existing = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        var winners = existing
        for item in remote {
            if let local = winners[item.id] {
                if item.changeDate > local.changeDate {
                    var newer = item
                    newer.filename = local.filename
                    winners[item.id] = newer
                }
            } else if let stagedFile = staged[item.id.uuidString] {
                try validateEPUB(stagedFile)
                let filename = UUID().uuidString + ".epub"
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

    private func persist(localChange: Bool) {
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: indexURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(deletions) {
            try? data.write(to: deletionsURL, options: .atomic)
        }
        if localChange { onLocalChange?() }
    }

    private func validateEPUB(_ url: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard byteSize > 4, byteSize <= 50 * 1024 * 1024 else { throw ReaderError.fileTooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let magic = try handle.read(upToCount: 4) ?? Data()
        guard magic.starts(with: [0x50, 0x4B]) else { throw ReaderError.invalidEPUB }
    }
}
