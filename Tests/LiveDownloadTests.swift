import XCTest
@testable import DarkReader

final class LiveDownloadTests: XCTestCase {
    @MainActor func testLiveOPDSDownloadAndReadium() async throws {
        let found: [CatalogBook]
        do {
            found = try await OPDSClient(searchEndpoint:"http://flibusta.is/opds/search?searchType=books",
                                         queryParameter:"searchTerm").search("Преступление и наказание")
        } catch { throw XCTSkip("OPDS upstream unavailable: \(error)") }
        var candidate = found.first { $0.epubURL != nil }
        if candidate == nil, let navigation = found.first(where: { $0.navigationURL != nil })?.navigationURL {
            candidate = try await OPDSClient(searchEndpoint:"",queryParameter:"").browse(navigation).first { $0.epubURL != nil }
        }
        guard var item = candidate else { throw XCTSkip("OPDS returned no open acquisition") }
        item.id = "qa:" + UUID().uuidString
        let library = BookshelfStore()
        try await library.download(item)
        let book = try XCTUnwrap(library.books.first { $0.catalogID == item.id })
        defer { library.delete(book) }
        _ = try await ReaderSession.open(fileURL:library.fileURL(for:book),previousLocation:nil)
        print("LIVE_OPDS_OPENED \(item.title) format=\(item.downloadFormat ?? "unknown")")
    }

    @MainActor func testRemoteAudioPlaybackAndSeek() async throws {
        let book = AudioBook(id:"librivox:52",source:.librivox,sourceID:"52",title:"Letters of Two Brides",
                             author:"Honoré de Balzac",description:"",coverURL:nil,language:"English")
        let tracks: [AudioChapter]
        do { tracks = try await AudioCatalogService.chapters(for:book) }
        catch { throw XCTSkip("Remote audio upstream unavailable: \(error)") }
        let player = AudioPlayerModel()
        player.open(book,tracks:tracks)
        defer { player.pause() }
        for _ in 0..<150 {
            if player.canSeek && player.position > 0.5 { break }
            if player.error != nil { break }
            try await Task.sleep(for:.milliseconds(200))
        }
        XCTAssertNil(player.error)
        XCTAssertTrue(player.canSeek,"Remote audio must advertise a seekable range")
        XCTAssertGreaterThan(player.position,0.5)
        player.seek(to:30)
        try await Task.sleep(for:.seconds(2))
        player.pause()
        XCTAssertGreaterThanOrEqual(player.position,29)
        print("LIVE_AUDIO_PLAYED Letters of Two Brides position=\(player.position)")
    }

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
