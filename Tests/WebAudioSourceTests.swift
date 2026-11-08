import XCTest
@testable import DarkReader

final class WebAudioSourceTests:XCTestCase {
    func testSearchPreservesHighlightedTitleAndStablePageIdentity() {
        let html=#"<div class="bookkitem"><a href="/book/test/" class="bookkitem_name"><span>Любовь</span> &amp; жизнь</a><a href="/author/test/">Автор</a><img class="bookkitem_cover_img" src="https://example.invalid/cover.jpg"><div class="bookkitem_about">Описание</div>"#
        let books=WebAudioSourceService.parse(html,source:.knigavuhe)
        XCTAssertEqual(books.count,1)
        XCTAssertEqual(books.first?.title,"Любовь & жизнь")
        XCTAssertEqual(books.first?.feedURL?.absoluteString,"https://knigavuhe.org/book/test/")
        XCTAssertEqual(books.first?.author,"Автор")
    }
    func testPlaylistBracketsInsideTitlesDoNotTruncateJSON() throws {
        let book=AudioBook(id:"test",source:.knigavuhe,sourceID:"test",title:"Книга",author:"Автор",description:"",coverURL:nil,language:"ru")
        let html=#"new BookPlayer(123, [{"id":12,"title":"Глава [10]","url":"https://example.invalid/10.mp3","error":0,"duration_float":60.5},{"id":2,"title":"Глава 2","url":"https://example.invalid/2.mp3","error":0}], false)"#
        let tracks=try WebAudioSourceService.parseChapters(html,book:book)
        XCTAssertEqual(tracks.map(\.id),["test:12","test:2"])
        XCTAssertEqual(tracks.first?.title,"Глава [10]")
        XCTAssertEqual(tracks.first?.durationSeconds,60.5)
    }
    func testReaderPaperUsesSamePaletteForViewportAndChrome() {
        XCTAssertEqual(ReaderPaper(theme:"sepia").backgroundHex,"#F5EAD1")
        XCTAssertEqual(ReaderPaper(theme:"oled").backgroundHex,"#000000")
        XCTAssertTrue(ReaderPaper(theme:"dark").dark)
        XCTAssertFalse(ReaderPaper(theme:"light").dark)
    }
}
