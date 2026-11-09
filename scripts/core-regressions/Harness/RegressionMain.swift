import Foundation
import ReadiumZIPFoundation

@main struct ReaderCoreRegressions {
    static func check(_ value: @autoclosure () -> Bool, _ name: String) {
        guard value() else { fatalError("FAIL: " + name) }
        print("PASS: " + name)
    }
    static func main() async throws {
        try await SourceRegressionChecks.run()
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jF9sAAAAASUVORK5CYII=")!
        let paragraphs = (0..<5000).map { "Абзац \($0): Текст & <проверка> — кириллица. " + String(repeating: "слово ", count: 30).trimmingCharacters(in: .whitespaces) }
        let fb2 = """
        <?xml version="1.0"?><FictionBook xmlns:l="http://www.w3.org/1999/xlink">
        <description><title-info><author><first-name>Имя</first-name><last-name>Автора</last-name></author><book-title>Обложка &amp; текст</book-title><lang>ru</lang><coverpage><image l:href="#cover"/></coverpage></title-info></description>
        <body>\(paragraphs.map { "<p>\(EPUBTextChunks.escape($0))</p>" }.joined())</body>
        <binary id="cover" content-type="image/png">\(image.base64EncodedString())</binary></FictionBook>
        """
        let input = folder.appendingPathComponent("unhelpful-filename.fb2")
        try Data(fb2.utf8).write(to: input)
        let parsed = try FB2Document.parse(Data(fb2.utf8))
        check(parsed.cover == image && parsed.author == "Имя Автора", "FB2 cover reference and author retained")
        check(parsed.paragraphs == paragraphs, "all FB2 text retained in original order")
        let chunks = EPUBTextChunks.make(parsed.paragraphs)
        check(chunks.count > 10 && chunks.flatMap { $0 } == paragraphs, "large compilation split without text loss")
        check(chunks.allSatisfy { $0.reduce(0) { $0 + EPUBTextChunks.escape($1).utf8.count + 8 } <= 65_536 }, "reading-order chunks stay below 64 KiB")
        let epub = try await BookFormatConverter.prepare(input)
        defer { try? fm.removeItem(at: epub) }
        try await BookFormatConverter.validateContainer(epub)
        let metadata = try await BookMetadata.read(epub)
        check(metadata.title == "Обложка & текст" && metadata.author == "Имя Автора" && metadata.cover == image, "FB2 to EPUB round trip preserves metadata and cover")
        check(BookMetadata.resourcePath("../../outside.jpg", relativeTo: "OEBPS/content.opf") == nil, "cover paths cannot escape archive")
        let archive = try await Archive(url: epub, accessMode: .read)
        let entries = try await archive.entries()
        check(entries.filter { $0.path.hasSuffix(".xhtml") }.count == chunks.count, "all text chunks present in EPUB spine resources")
        let opfEntry = entries.first { $0.path == "OEBPS/content.opf" }!
        let opfFile = folder.appendingPathComponent("content.opf")
        try await archive.extract(opfEntry, to: opfFile)
        let opf = try String(contentsOf: opfFile, encoding: .utf8)
        check(opf.components(separatedBy: "<itemref ").count - 1 == chunks.count, "every chunk is reachable in reading order")
        var book = LocalBook(title: "Тест", author: "Автор", filename: "book.epub")
        book.locatorJSON = "{\"locations\":{\"totalProgression\":0.42}}"; book.bookmarks = ["bookmark"]
        let snapshot = CloudLibrarySnapshot(schema: 1, deviceID: "test", savedAt: Date(), books: [book], deletions: [:], settings: ["readerFontSize": "1.5"], settingsChangedAt: Date())
        let backup = try await LocalLibraryBackup.create(snapshot, files: [book.id: epub])
        defer { try? fm.removeItem(at: backup.deletingLastPathComponent()) }
        // No extension/type metadata: validate the actual bytes supplied by Files.
        let unknownType = folder.appendingPathComponent("provider-data")
        try fm.copyItem(at: backup, to: unknownType)
        let restored = try await LocalLibraryBackup.read(unknownType)
        defer { try? fm.removeItem(at: restored.directory) }
        check(!restored.metadataOnly && restored.snapshot.books == [book], "ZIP without extension restores progress and bookmarks")
        let restoredBytes = try Data(contentsOf: restored.files[book.id.uuidString]!)
        let originalBytes = try Data(contentsOf: epub)
        check(restoredBytes == originalBytes, "backup restores exact EPUB bytes")
        let json = folder.appendingPathComponent("legacy.json")
        try (Data([0xEF, 0xBB, 0xBF]) + JSONEncoder().encode(snapshot)).write(to: json)
        let legacy = try await LocalLibraryBackup.read(json)
        defer { try? fm.removeItem(at: legacy.directory) }
        check(legacy.metadataOnly && legacy.files.isEmpty && legacy.snapshot.books == [book], "older JSON backup remains restorable without pretending to contain books")
        let invalid = folder.appendingPathComponent("invalid.zip")
        try Data("not a backup".utf8).write(to: invalid)
        do { _ = try await LocalLibraryBackup.read(invalid); fatalError("Accepted invalid backup") }
        catch { print("PASS: invalid file rejected before restoring") }
        let future = CloudLibrarySnapshot(schema: 99, deviceID: "test", savedAt: Date(), books: [], deletions: [:], settings: [:], settingsChangedAt: Date())
        try JSONEncoder().encode(future).write(to: json)
        do { _ = try await LocalLibraryBackup.read(json); fatalError("Accepted future schema") }
        catch { print("PASS: unsupported backup version rejected") }
        let setting = ReaderOptions(fontSize: 1.8, font: "sans", theme: "sepia", scroll: false, animated: true)
        check(setting.fontSize == 1.8 && setting.theme == "sepia", "reader keeps font multiplier and selected theme together")
        check(ReaderOptions(fontSize: .nan, font: "unknown", theme: "unknown", scroll: true, animated: true).fontSize == 1.1, "invalid stored font size has a safe default")
        check(!LegacyReaderUpgrade.canUpgrade(locatorJSON: book.locatorJSON, bookmarks: [], explicitLocation: nil), "legacy optimization preserves nonzero progress")
        check(!LegacyReaderUpgrade.canUpgrade(locatorJSON: nil, bookmarks: ["bookmark"], explicitLocation: nil), "legacy optimization preserves saved bookmarks")
        check(LegacyReaderUpgrade.canUpgrade(locatorJSON: "{\"locations\":{\"totalProgression\":0,\"position\":1}}", bookmarks: [], explicitLocation: nil), "unread legacy compilation may be optimized")
        print("Reader core regressions completed")
    }
}
