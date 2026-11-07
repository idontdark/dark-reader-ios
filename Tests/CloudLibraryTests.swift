import XCTest
@testable import DarkReader

final class CloudLibraryTests: XCTestCase {
    func testOlderBooksJSONRemainsReadable() throws {
        let raw = """
        {"id":"5B74BF62-92DA-4DD3-A653-019DC2365BF7",
         "title":"Старая книга","author":"Автор","filename":"old.epub",
         "locatorJSON":null,"addedAt":0}
        """
        let book = try JSONDecoder().decode(LocalBook.self, from: Data(raw.utf8))
        XCTAssertEqual(book.title, "Старая книга")
        XCTAssertNil(book.updatedAt)
        XCTAssertNil(book.isFavorite)
        XCTAssertNil(book.bookmarks)
    }

    @MainActor
    func testCloudRestoreCopiesFileAndPreservesBookmarks() throws {
        let store = BookshelfStore()
        var book = LocalBook(title: "Проверка восстановления", author: "Тест", filename: "remote.epub")
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".epub")
        // This tests the store's quick ZIP signature check, not full EPUB validity.
        try Data([0x50, 0x4B, 0x03, 0x04, 0x00]).write(to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }

        try store.mergeFromCloud([book], tombstones: [:], staged: [book.id.uuidString: staged])
        guard let imported = store.books.first(where: { $0.id == book.id }) else {
            return XCTFail("Restored book not present")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: imported).path))

        store.saveBookmark(bookID: book.id, locatorJSON: "bookmark-a")
        book.bookmarks = ["bookmark-b"]
        book.updatedAt = Date(timeIntervalSinceNow: 2)
        try store.mergeFromCloud([book], tombstones: [:], staged: [:])
        let marks = store.books.first(where: { $0.id == book.id })?.bookmarks ?? []
        XCTAssertEqual(Set(marks), Set(["bookmark-a", "bookmark-b"]))

        // A newer cloud deletion must not resurrect a book from older snapshots.
        try store.mergeFromCloud([book], tombstones: [book.id.uuidString: .distantFuture], staged: [:])
        XCTAssertFalse(store.books.contains(where: { $0.id == book.id }))
    }

    func testSnapshotEncodesAllRequiredData() throws {
        let snapshot = CloudLibrarySnapshot(
            schema: 1,
            deviceID: UUID().uuidString,
            savedAt: Date(),
            books: [LocalBook(title: "EPUB", author: "Writer", filename: "test.epub")],
            deletions: [:],
            settings: ["readerTheme": "sepia", "readerFontSize": "1.4"],
            settingsChangedAt: Date()
        )
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CloudLibrarySnapshot.self, from: encoded)
        XCTAssertEqual(decoded.schema, 1)
        XCTAssertEqual(decoded.books.count, 1)
        XCTAssertEqual(decoded.settings["readerTheme"], "sepia")
    }
}
