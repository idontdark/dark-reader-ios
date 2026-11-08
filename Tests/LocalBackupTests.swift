import XCTest
@testable import DarkReader

final class LocalBackupTests: XCTestCase {
    func testMetadataJSONRoundTripContainsBookmarksWithoutCreatingBookFiles() async throws {
        var book=LocalBook(title:"Тест",author:"Автор",filename:"missing.epub")
        book.locatorJSON="{\"locations\":{\"totalProgression\":0.42}}"
        book.bookmarks=["named-bookmark"]
        let snapshot=CloudLibrarySnapshot(schema:1,deviceID:"test",savedAt:Date(),books:[book],deletions:[:],
                                          settings:["readerProgressDisplay":"percent"],settingsChangedAt:Date())
        let url=try LocalLibraryBackup.createMetadata(snapshot)
        defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
        let restored=try await LocalLibraryBackup.read(url)
        defer {try? FileManager.default.removeItem(at:restored.directory)}
        XCTAssertTrue(restored.metadataOnly)
        XCTAssertTrue(restored.files.isEmpty)
        XCTAssertEqual(restored.snapshot.books.first?.locatorJSON,book.locatorJSON)
        XCTAssertEqual(restored.snapshot.books.first?.bookmarks,book.bookmarks)
        XCTAssertEqual(restored.snapshot.settings["readerProgressDisplay"],"percent")
    }
    func testInvalidJSONDoesNotBecomeAnEmptySuccessfulRestore() async throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
        try Data("{\"unrelated\":true}".utf8).write(to:url)
        defer {try? FileManager.default.removeItem(at:url)}
        do { _=try await LocalLibraryBackup.read(url);XCTFail("Invalid backup accepted") }
        catch { }
    }
    @MainActor func testMetadataRestoreDoesNotCreateMissingBookEntries() {
        let store=BookshelfStore()
        let before=store.books.map(\.id)
        let missing=LocalBook(title:"Нет файла",author:"Автор",filename:"absent.epub")
        store.restoreReadingMetadata([missing])
        XCTAssertEqual(store.books.map(\.id),before)
        XCTAssertFalse(store.books.contains(where:{$0.id == missing.id}))
    }
}
