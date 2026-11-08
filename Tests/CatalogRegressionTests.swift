import XCTest
@testable import DarkReader

final class CatalogRegressionTests: XCTestCase {
    func testArchivePreservesMultilingualMetadata() {
        let data: [String:Any] = ["response":["docs":[["identifier":"real-id","title":"Роман","creator":["Автор"],"language":["rus","eng"]]]]]
        let books = AudioCatalogService.parseArchive(data)
        XCTAssertEqual(books.count, 1)
        XCTAssertTrue(AudioCatalogService.matchesLanguage(books.first?.language, choice:"ru"))
        XCTAssertTrue(AudioCatalogService.matchesLanguage(books.first?.language, choice:"en"))
        XCTAssertEqual(books.first?.author, "Автор")
    }
    func testRomanceQueryIncludesCatalogSynonyms() {
        let query=AudioCatalogService.audioGenreQuery("romance",archive:true) ?? ""
        XCTAssertTrue(query.contains("novel"))
        XCTAssertTrue(query.contains("роман"))
    }
    func testUnknownLanguageDoesNotLeakIntoRussianResults() {
        XCTAssertFalse(AudioCatalogService.matchesLanguage("English",choice:"ru"))
        XCTAssertTrue(AudioCatalogService.matchesLanguage("rus; eng",choice:"ru"))
    }
}
