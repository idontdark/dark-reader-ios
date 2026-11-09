import Foundation
import ReadiumZIPFoundation

enum DocumentRegressionChecks {
    static func run(in folder: URL, epub: URL) async throws {
        func check(_ value: Bool, _ label: String) { ReaderCoreRegressions.check(value, label) }
        let fixtures: [(String, String, String)] = [
            ("txt", "First paragraph\nSecond paragraph", "Second paragraph"),
            ("html", "<html><head><title>HTML fixture</title></head><body><p>First paragraph</p><script>UNSAFE_SCRIPT</script><p>Second paragraph</p></body></html>", "Second paragraph"),
            ("rtf", #"{\rtf1\ansi First paragraph\par Second paragraph}"#, "Second paragraph")
        ]
        for (ext, content, expected) in fixtures {
            let input = folder.appendingPathComponent("sample." + ext)
            try Data(content.utf8).write(to: input)
            let converted = try await BookFormatConverter.prepare(input)
            defer { try? FileManager.default.removeItem(at: converted) }
            try await BookFormatConverter.validateContainer(converted)
            let archive = try await Archive(url: converted, accessMode: .read)
            let entries = try await archive.entries()
            var text = ""
            for entry in entries where entry.path.hasSuffix(".xhtml") {
                let target = folder.appendingPathComponent(UUID().uuidString)
                try await archive.extract(entry, to: target)
                text += try String(contentsOf: target, encoding: .utf8)
            }
            check(text.contains("First paragraph") && text.contains(expected) && !text.contains("UNSAFE_SCRIPT"), ext.uppercased() + " converts to readable EPUB without losing paragraphs or retaining scripts")
        }
        let cp = folder.appendingPathComponent("cp1251.txt")
        let original = "Русский текст без UTF-8 BOM"
        try original.data(using: .windowsCP1251)!.write(to: cp)
        let converted = try await BookFormatConverter.prepare(cp)
        defer { try? FileManager.default.removeItem(at: converted) }
        try await BookFormatConverter.validateContainer(converted)
        check(true, "Windows-1251 text imports without accidental UTF-16 decoding")
        let pdf = folder.appendingPathComponent("readable.pdf")
        let bytes = samplePDF()
        try bytes.write(to: pdf)
        let preparedPDF = try await BookFormatConverter.prepare(pdf)
        let metadata = try await BookMetadata.read(preparedPDF)
        check(preparedPDF == pdf && metadata.cover != nil, "PDF retains original fixed layout and generates a cover from its first page")
        var pdfBook = LocalBook(title: "PDF", author: "Author", filename: "readable.pdf")
        pdfBook.locatorJSON = #"{"pdfPage":0,"locations":{"position":1,"totalProgression":0}}"#
        pdfBook.bookmarks = [pdfBook.locatorJSON!]
        let epubBook = LocalBook(title: "EPUB", author: "Author", filename: "readable.epub")
        let snapshot = CloudLibrarySnapshot(schema: 2, deviceID: "test", savedAt: Date(), books: [pdfBook, epubBook], deletions: [:], settings: [:], settingsChangedAt: Date())
        let backup = try await LocalLibraryBackup.create(snapshot, files: [pdfBook.id: pdf, epubBook.id: epub])
        defer { try? FileManager.default.removeItem(at: backup.deletingLastPathComponent()) }
        let restored = try await LocalLibraryBackup.read(backup)
        defer { try? FileManager.default.removeItem(at: restored.directory) }
        let restoredPDF = try Data(contentsOf: restored.files[pdfBook.id.uuidString]!)
        check(restored.snapshot.books == [pdfBook, epubBook] && restoredPDF == bytes, "mixed PDF/EPUB backup restores exact documents, progress and PDF bookmarks")
        let corrupt = folder.appendingPathComponent("corrupt.pdf")
        try Data("%PDF-1.4\nthis is not a PDF document".utf8).write(to: corrupt)
        do { _ = try await BookFormatConverter.prepare(corrupt); fatalError("corrupt PDF accepted") }
        catch { print("PASS: PDF header alone cannot pass document validation") }
    }
    static func samplePDF() -> Data {
        let content = "BT /F1 12 Tf 20 120 Td (Backup fixture) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        ]
        var pdf = "%PDF-1.4\n"; var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 6\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}
