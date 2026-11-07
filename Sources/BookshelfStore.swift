import Foundation

@MainActor
final class BookshelfStore: ObservableObject {
    @Published private(set) var books: [LocalBook] = []

    private let fileManager = FileManager.default

    private var directory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Books", isDirectory: true)
    }

    private var indexURL: URL {
        directory.appendingPathComponent("books.json")
    }

    init() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([LocalBook].self, from: data) {
            books = decoded
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
        let destination = directory.appendingPathComponent(filename)
        try fileManager.copyItem(at: source, to: destination)
        books.insert(LocalBook(title: title, author: author, filename: filename), at: 0)
        persist()
    }

    func download(_ book: CatalogBook) async throws {
        guard let epubURL = book.epubURL, epubURL.scheme == "https" else { throw ReaderError.noEPUB }
        let (temporaryURL, response) = try await URLSession.shared.download(from: epubURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ReaderError.invalidEPUB
        }
        try validateEPUB(temporaryURL)
        let filename = UUID().uuidString + ".epub"
        let destination = directory.appendingPathComponent(filename)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        books.insert(LocalBook(title: book.title, author: book.author, filename: filename), at: 0)
        persist()
    }

    func savePosition(bookID: UUID, locatorJSON: String?) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].locatorJSON = locatorJSON
        persist()
    }

    func delete(_ book: LocalBook) {
        try? fileManager.removeItem(at: fileURL(for: book))
        books.removeAll { $0.id == book.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: indexURL, options: .atomic)
        }
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
