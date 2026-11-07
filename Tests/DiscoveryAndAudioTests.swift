import Foundation
import XCTest
@testable import DarkReader

final class DiscoveryAndAudioTests: XCTestCase {
    func testSelectedBooksSurviveJSONRoundTrip() throws {
        let book = DiscoveryBook(
            id: "openlibrary:/works/OL123W",
            title: "A real example",
            author: "Test Author",
            coverURL: try XCTUnwrap(URL(string: "https://covers.openlibrary.org/b/id/123-M.jpg")),
            detailURL: try XCTUnwrap(URL(string: "https://openlibrary.org/works/OL123W")),
            genre: "fantasy"
        )
        XCTAssertEqual(DiscoveryService.saved(DiscoveryService.encode([book])), [book])
        XCTAssertEqual(DiscoveryService.saved("bad value"), [])
    }

    func testAudioBookHistoryJSONRoundTrip() throws {
        let item = AudioBook(
            id: "librivox:52",
            source: .librivox, sourceID: "52",
            title: "Letters of Two Brides", author: "Honoré de Balzac",
            description: "", coverURL: nil, language: "English"
        )
        let encoded = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode([AudioBook].self, from: encoded)
        XCTAssertEqual(decoded, [item])
    }

    func testExactlyTwoBuiltInAudioSources() {
        XCTAssertEqual(Set(AudioSource.online.map(\.rawValue)), Set(["librivox","archive"]))
    }
}
