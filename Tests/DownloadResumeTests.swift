import XCTest
@testable import DarkReader

final class DownloadResumeTests: XCTestCase {
    @MainActor func testPausePersistsResumeDataAndRestartUsesRange() async throws {
        let library = BookshelfStore()
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:storage) }
        let book = CatalogBook(id:"resume:"+UUID().uuidString,title:"Resume QA",author:"QA",
                               epubURL:URL(string:"http://127.0.0.1:8765/book.epub"),downloadFormat:"epub")
        let queue = DownloadQueue(storage:storage)
        queue.attach(library);queue.enqueue(book)
        for _ in 0..<100 {
            if (queue.items.first?.progress ?? 0) > 0.08 { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        queue.pause(book.id)
        for _ in 0..<60 {
            if queue.items.first?.resumeData != nil { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertEqual(queue.items.first?.state,.paused)
        XCTAssertNotNil(queue.items.first?.resumeData,"Range-capable server must produce resume data")
        for _ in 0..<100 {
            if queue.activeDownloadCount == 0 { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertEqual(queue.activeDownloadCount,0,"Paused session must release its queue slot")
        let restored = DownloadQueue(storage:storage)
        XCTAssertEqual(restored.items.first?.state,.paused)
        XCTAssertNotNil(restored.items.first?.resumeData)
        let restartedLibrary = BookshelfStore()
        restored.attach(restartedLibrary);restored.retry(book.id)
        for _ in 0..<1200 {
            if restored.items.first?.state == .downloaded || restored.items.first?.state == .failed { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertEqual(restored.items.first?.state,.downloaded)
        let imported = try XCTUnwrap(restartedLibrary.books.first { $0.catalogID == book.id })
        defer { restartedLibrary.delete(imported) }
        _ = try await ReaderSession.open(fileURL:restartedLibrary.fileURL(for:imported),previousLocation:nil)
        let (data,_) = try await URLSession.shared.data(from:URL(string:"http://127.0.0.1:8765/stats")!)
        let stats = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertTrue((stats["ranges"] as? [Int] ?? []).contains { $0 > 0 },"Restart must request remaining bytes")
        print("DOWNLOAD_RESUME_VERIFIED \(stats)")
    }
}
