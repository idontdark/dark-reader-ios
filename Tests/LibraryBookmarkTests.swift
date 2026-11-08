import XCTest
@testable import DarkReader

@MainActor
final class LibraryBookmarkTests: XCTestCase {
    private let raw = #"{"href":"chapter-2.xhtml","type":"application/xhtml+xml","title":"Моя цитата","locations":{"position":42,"totalProgression":0.18}}"#

    func testEnglishInterfacePreservesUserBookmarkName() {
        let mark = BookmarkedLocation(raw: raw, index: 0, language: "en")
        XCTAssertTrue(mark.valid)
        XCTAssertEqual(mark.title, "Моя цитата")
        XCTAssertEqual(mark.detail, "Page 42 · 18%")
    }

    func testOldUnnamedBookmarkGetsLocalizedFallback() {
        let mark = BookmarkedLocation(raw: #"{"href":"chapter.xhtml","type":"application/xhtml+xml","locations":{}}"#, index: 1, language: "en")
        XCTAssertEqual(mark.title, "Bookmark 2")
        XCTAssertEqual(mark.detail, "Location in book")
    }

    func testInvalidBookmarkDoesNotPretendToHaveAPage() {
        let mark = BookmarkedLocation(raw: "invalid-json", index: 0, language: "en")
        XCTAssertFalse(mark.valid)
        XCTAssertEqual(mark.detail, "Bookmark unavailable")
    }

    func testLegacyAudioBookmarkDecodesWithoutTitle() throws {
        let raw = #"{"id":"1262C93F-360D-4707-884B-F846F2031A7A","chapterID":"track:4","position":123.5}"#
        let mark = try JSONDecoder().decode(AudioPlayerModel.Bookmark.self, from: Data(raw.utf8))
        XCTAssertEqual(mark.chapterID, "track:4")
        XCTAssertEqual(mark.position, 123.5)
        XCTAssertNil(mark.title)
    }

    func testBookmarkCountUsesBothLanguages() {
        XCTAssertEqual(L10n.bookmarkCount(1, language: "en"), "1 bookmark")
        XCTAssertEqual(L10n.bookmarkCount(2, language: "en"), "2 bookmarks")
        XCTAssertEqual(L10n.bookmarkCount(1, language: "ru"), "1 закладка")
        XCTAssertEqual(L10n.bookmarkCount(2, language: "ru"), "2 закладки")
        XCTAssertEqual(L10n.bookmarkCount(12, language: "ru"), "12 закладок")
        XCTAssertEqual(L10n.bookmarkCount(21, language: "ru"), "21 закладка")
    }
}
