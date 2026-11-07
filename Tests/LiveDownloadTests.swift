import XCTest
@testable import DarkReader

final class LiveDownloadTests: XCTestCase {
    @MainActor func testThreeLiveEPUBDownloadsAndOpenInReadium() async throws {
        let candidates: [CatalogBook]
        do {
            candidates = try await CatalogProviders.search(query:"Doyle", mode:"author", provider:"gutendex",
                                                          customURL:"", customParameter:"", language:"en")
        } catch { throw XCTSkip("Gutendex upstream unavailable: \(error)") }
        guard candidates.count >= 3 else { throw XCTSkip("Gutendex returned fewer than three downloadable EPUBs") }
        let library = BookshelfStore()
        // Use isolated catalog IDs so existing tester data cannot satisfy this test.
        let books = candidates.prefix(3).map { item -> CatalogBook in
            var copy = item
            copy.id = "qa:" + UUID().uuidString
            return copy
        }
        let queue = DownloadQueue(storage: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        queue.attach(library)
        for item in books { queue.enqueue(item) }
        XCTAssertEqual(queue.items.filter { $0.state == .connecting }.count, 3)
        for _ in 0..<120 {
            if queue.items.allSatisfy({ [.downloaded, .failed].contains($0.state) }) { break }
            try await Task.sleep(for: .seconds(1))
        }
        defer {
            for book in library.books.filter({ books.map(\.id).contains($0.catalogID ?? "") }) { library.delete(book) }
        }
        XCTAssertTrue(queue.items.allSatisfy { $0.state == .downloaded }, "All three queued real EPUBs must finish")
        for candidate in books {
            let book = try XCTUnwrap(library.books.first { $0.catalogID == candidate.id })
            let session = try await ReaderSession.open(fileURL: library.fileURL(for: book), previousLocation: nil)
            XCTAssertNotNil(session.navigator)
            print("LIVE_EPUB_OPENED \(candidate.title)")
        }
    }
}
