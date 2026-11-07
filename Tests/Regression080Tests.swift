import XCTest
import AVFoundation
@testable import DarkReader

final class Regression080Tests: XCTestCase {
    func testHTTPAndRelativeFB2Acquisition() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom" xml:base="http://example.org/opds/">
          <link rel="search" type="application/atom+xml" href="search?q={searchTerms}"/>
          <entry><id>1</id><title>Книга</title><author><name>Автор</name></author>
          <link rel="http://opds-spec.org/acquisition/open-access" type="application/x-fictionbook+xml" href="../book/1"/>
          <link rel="http://opds-spec.org/image" type="image/jpeg" href="../cover/1.jpg"/></entry>
        </feed>
        """
        let feed = try OPDSClient.parse(Data(xml.utf8), baseURL: URL(string: "http://example.org/opds")!)
        XCTAssertEqual(feed.books.first?.epubURL?.absoluteString, "http://example.org/book/1")
        XCTAssertEqual(feed.books.first?.downloadFormat, "fb2")
        XCTAssertEqual(feed.books.first?.author, "Автор")
        XCTAssertEqual(feed.searchTemplate, "search?q={searchTerms}")
    }
    func testPaidAcquisitionIsNotTreatedAsFreeDownload() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Paid</title>
        <link rel="http://opds-spec.org/acquisition/buy" type="application/epub+zip" href="https://example.org/buy"/>
        </entry></feed>
        """
        XCTAssertTrue(try OPDSClient.parse(Data(xml.utf8), baseURL: URL(string: "https://example.org")!).books.isEmpty)
    }
    func testHTMLIsNotAnOPDSFeed() {
        XCTAssertThrowsError(try OPDSClient.parse(Data("<html><body>Blocked</body></html>".utf8), baseURL: URL(string:"https://example.org")!))
    }
    func testAudioLanguageNeverFallsBackToEnglish() {
        XCTAssertFalse(AudioCatalogService.matchesLanguage("English", choice: "ru"))
        XCTAssertFalse(AudioCatalogService.matchesLanguage(nil, choice: "ru"))
        XCTAssertTrue(AudioCatalogService.matchesLanguage("Russian", choice: "ru"))
        XCTAssertTrue(AudioCatalogService.matchesLanguage("rus", choice: "ru"))
        XCTAssertTrue(AudioCatalogService.matchesLanguage(nil, choice: nil))
    }
    func testRequiredSearchAliases() {
        XCTAssertTrue(AudioCatalogService.searchVariants("Богатый папа, бедный папа").contains("Rich Dad Poor Dad"))
        XCTAssertTrue(AudioCatalogService.searchVariants("Анна Каренина").contains("Anna Karenina"))
        XCTAssertEqual(RecommendationProfile.normalized("Лев — ТОЛСТОЙ!"), "лев толстой")
    }
    func testReadingSignalsExcludeKnownBooks() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        RecommendationProfile.record(title: "Знакомая книга", author: "Автор", weight: 3, defaults: defaults)
        let known = DiscoveryBook(id:"1", title:"Знакомая книга", author:"Автор", coverURL:URL(string:"https://example.org/1.jpg")!,
                                  detailURL:URL(string:"https://example.org/1")!, genre:"classics")
        XCTAssertTrue(RecommendationProfile.rank([known], excluding: [], defaults: defaults).isEmpty)
    }
    @MainActor func testQueueRestoresInterruptedJobsAndRetainsPause() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let book = CatalogBook(id:"a", title:"A", author:"B", epubURL:URL(string:"https://example.org/a.epub"))
        var active = BookDownload(book: book); active.state = .downloading
        var paused = BookDownload(book: CatalogBook(id:"b", title:"B", author:"C", epubURL:URL(string:"https://example.org/b.epub")))
        paused.state = .paused
        try JSONEncoder().encode([active,paused]).write(to:path)
        let queue = DownloadQueue(storage:path)
        XCTAssertEqual(queue.items[0].state, .queued)
        XCTAssertEqual(queue.items[1].state, .paused)
        queue.enqueue(book)
        XCTAssertEqual(queue.items.count, 2)
        queue.cancel("a")
        XCTAssertEqual(queue.items.map(\.id), ["b"])
    }
    func testOldLibraryDecodesWithoutNewFields() throws {
        let old = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"Old","author":"Author","filename":"a.epub","addedAt":0}
        """
        let book = try JSONDecoder().decode(LocalBook.self,from:Data(old.utf8))
        XCTAssertNil(book.catalogID)
        XCTAssertEqual(book.title,"Old")
    }
    @MainActor func testImportedM4APlaysAndSeeks() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at:file) }
        try Self.makeAudio(file)
        let book = try await AudioImportStore.importFiles([file], title: "Fixture", author: "QA")
        defer { try? FileManager.default.removeItem(at: AudioImportStore.directory(book.sourceID)) }
        let chapters = try AudioImportStore.chapters(for: book)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertGreaterThan(chapters[0].durationSeconds ?? 0, 7)
        let player = AudioPlayerModel()
        player.open(book, tracks: chapters)
        defer { player.pause() }
        for _ in 0..<50 {
            if player.canSeek { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(player.canSeek)
        player.seek(to: 4)
        try await Task.sleep(for: .milliseconds(600))
        player.pause()
        XCTAssertGreaterThanOrEqual(player.position, 3.8)
        XCTAssertLessThan(player.position, 5.5)
    }
    @MainActor func testRealMP3M4BAndZIPFixtures() async throws {
        let bundle = Bundle(for: Self.self)
        let mp3 = try XCTUnwrap(bundle.url(forResource:"sample",withExtension:"mp3"))
        let m4b = try XCTUnwrap(bundle.url(forResource:"chapters",withExtension:"m4b"))
        let zip = try XCTUnwrap(bundle.url(forResource:"combined",withExtension:"zip"))
        let first = try await AudioImportStore.importFiles([mp3])
        let segmented = try await AudioImportStore.importFiles([m4b])
        let combined = try await AudioImportStore.importFiles([zip])
        defer {
            for book in [first,segmented,combined] { try? FileManager.default.removeItem(at:AudioImportStore.directory(book.sourceID)) }
        }
        XCTAssertEqual(try AudioImportStore.chapters(for:first).count,1)
        let chapters = try AudioImportStore.chapters(for:segmented)
        XCTAssertEqual(chapters.count,2)
        XCTAssertEqual(chapters.last?.startSeconds ?? -1,2,accuracy:0.1)
        XCTAssertEqual(try AudioImportStore.chapters(for:combined).count,2)
        let player = AudioPlayerModel()
        player.open(segmented, tracks:chapters)
        defer { player.pause() }
        for _ in 0..<60 {
            if player.chapterIndex == 1 { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertEqual(player.chapterIndex,1,"Embedded M4B must automatically advance chapters")
        player.pause()
        player.seek(to:0.5)
        try await Task.sleep(for:.milliseconds(300))
        XCTAssertEqual(player.position,0.5,accuracy:0.2)
    }
    private static func makeAudio(_ file: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let output = try AVAudioFile(forWriting:file,settings:[
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey:44100, AVNumberOfChannelsKey:1, AVEncoderBitRateKey:64000])
        let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:44100)!
        buffer.frameLength = 44100
        for i in 0..<44100 { buffer.floatChannelData![0][i] = Float(sin(Double(i)*0.06))*0.05 }
        for _ in 0..<8 { try output.write(from:buffer) }
    }
}
