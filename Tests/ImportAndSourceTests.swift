import XCTest
@testable import DarkReader

final class ImportAndSourceTests: XCTestCase {
    func testMultipleNamedCatalogsRoundTrip() {
        let entries = [
            NamedOPDSCatalog(name: "Библиотека А", url: "https://example.org/opds"),
            NamedOPDSCatalog(name: "Библиотека Б", url: "https://books.example.com/catalog",
                             searchParameter: "q")
        ]
        let restored = OPDSSources.decode(OPDSSources.encode(entries))
        XCTAssertEqual(restored, entries)
        XCTAssertTrue(restored.allSatisfy(OPDSSources.isValid))
        XCTAssertFalse(OPDSSources.isValid(NamedOPDSCatalog(
            name: "Небезопасный каталог", url: "http://example.org/opds"
        )))
    }

    func testFB2ConvertedToEPUBContainer() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".fb2")
        defer { try? FileManager.default.removeItem(at: file) }
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook><description><title-info><book-title>Тестовая книга</book-title>
        </title-info></description><body><section><p>Первый абзац.</p>
        <p>Второй абзац.</p></section></body></FictionBook>
        """
        try Data(xml.utf8).write(to: file)
        let epub = try BookFormatConverter.prepare(file)
        XCTAssertEqual(epub.pathExtension, "epub")
        let bytes = try Data(contentsOf: epub)
        XCTAssertTrue(bytes.starts(with: [0x50, 0x4B]))
        XCTAssertGreaterThan(bytes.count, 100)
    }

    func testInvalidMOBIIsNotImportedAsValidBook() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mobi")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 0, count: 150).write(to: file)
        XCTAssertThrowsError(try BookFormatConverter.prepare(file))
    }

    func testBothAudioSourcesConfigured() {
        XCTAssertEqual(Set(AudioSource.allCases.map(\.rawValue)),
                       Set(["librivox", "archive"]))
    }
}
