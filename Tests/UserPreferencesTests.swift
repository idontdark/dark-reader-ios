import XCTest
@testable import DarkReader

final class UserPreferencesTests: XCTestCase {
    func testSelectedGenresAndFavoriteAuthorsRoundTrip() {
        let names = ["Артур Конан Дойл", "Jane Austen", "Агата Кристи"]
        let encoded = ReaderPreferences.encode(names)
        XCTAssertEqual(ReaderPreferences.array(encoded), names)
        XCTAssertEqual(ReaderPreferences.array("bad json"), [])
    }

    func testBookLanguageIsIndependentFromInterfaceLanguage() {
        XCTAssertEqual(ReaderPreferences.effectiveLanguage("auto", appLanguage: "en"), "en")
        XCTAssertEqual(ReaderPreferences.effectiveLanguage("auto", appLanguage: "ru"), "ru")
        XCTAssertEqual(ReaderPreferences.effectiveLanguage("ru", appLanguage: "en"), "ru")
        XCTAssertNil(ReaderPreferences.effectiveLanguage("all", appLanguage: "en"))
    }

    func testGenreLabelsFollowInterfaceLanguage() {
        XCTAssertEqual(ReaderPreferences.genreName("detective", language: "ru"), "Детективы")
        XCTAssertEqual(ReaderPreferences.genreName("detective", language: "en"), "Mystery")
    }
}
