import Foundation
import ReadiumZIPFoundation

enum ImportFormatError: LocalizedError {
    case unsupported, corrupt, protected, oversized, empty, noBookInArchive

    var errorDescription: String? {
        switch self {
        case .unsupported: "Этот формат книги пока не поддерживается."
        case .corrupt: "Файл повреждён или имеет неверный формат."
        case .protected: "Эта книга защищена DRM или использует неподдерживаемое сжатие MOBI."
        case .oversized: "Файл слишком большой. Ограничение: 50 МБ."
        case .empty: "В книге не удалось найти текст."
        case .noBookInArchive: "В архиве не найден EPUB, FB2 или MOBI."
        }
    }
}

/// Produces an EPUB file that can be opened by the existing Readium navigator.
/// For DRM-free classic MOBI and FB2, text is converted into a standards-based EPUB.
enum BookFormatConverter {
    static func prepare(_ input: URL) async throws -> URL {
        let ext = input.pathExtension.lowercased()
        switch ext {
        case "epub":
            return input
        case "fb2":
            return try await fromFB2(input)
        case "mobi":
            return try await fromMOBI(input)
        case "zip":
            return try await fromZIP(input)
        default:
            throw ImportFormatError.unsupported
        }
    }

    static func validateContainer(_ url: URL) async throws {
        let archive = try await Archive(url: url, accessMode: .read)
        let entries = try await archive.entries()
        guard entries.contains(where: { $0.path == "META-INF/container.xml" }),
              let mimetype = entries.first(where: { $0.path == "mimetype" }),
              mimetype.uncompressedSize < 100 else { throw ReaderError.invalidEPUB }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await archive.extract(mimetype, to: temporary)
        guard String(data: try Data(contentsOf: temporary), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip" else {
            throw ReaderError.invalidEPUB
        }
    }

    /// Upgrade only our old four-entry converter output. Originals remain untouched.
    static func optimizedLegacyCopy(_ source: URL, title: String, author: String) async throws -> URL? {
        let archive = try await Archive(url: source, accessMode: .read)
        let entries = try await archive.entries()
        guard Set(entries.map(\.path)) == Set(["mimetype", "META-INF/container.xml", "OEBPS/content.opf", "OEBPS/book.xhtml"]),
              let text = entries.first(where: { $0.path == "OEBPS/book.xhtml" }),
              text.type == .file, text.uncompressedSize > 512 * 1024, text.uncompressedSize <= 50 * 1024 * 1024 else { return nil }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await archive.extract(text, to: temporary)
        let data = try Data(contentsOf: temporary)
        guard data.range(of: Data("<style>body{font-family:serif;line-height:1.5}p{margin:0 0 0.8em}</style>".utf8)) != nil else { return nil }
        let content = try FB2Document.parse(data)
        return try await EPUBWriter.make(title: title, paragraphs: content.paragraphs, author: author)
    }

    private static func fromZIP(_ file: URL) async throws -> URL {
        let archive = try await Archive(url: file, accessMode: .read)
        let entries = try await archive.entries()
        let choices = entries.filter { entry in
            let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
            return ["epub", "fb2", "mobi"].contains(ext)
                && entry.type == .file
                && entry.uncompressedSize > 0
                && entry.uncompressedSize <= 50 * 1024 * 1024
        }
        guard let selected = choices.first else { throw ImportFormatError.noBookInArchive }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." +
                                    URL(fileURLWithPath: selected.path).pathExtension.lowercased())
        try await archive.extract(selected, to: destination)
        let prepared = try await prepare(destination)
        return prepared
    }

    private static func fromFB2(_ source: URL) async throws -> URL {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count <= 50 * 1024 * 1024 else { throw ImportFormatError.oversized }
        let book = try FB2Document.parse(data)
        return try await EPUBWriter.make(
            title: book.title.isEmpty ? source.deletingPathExtension().lastPathComponent : book.title,
            paragraphs: book.paragraphs, author: book.author, language: book.language,
            cover: book.cover, coverMIME: book.coverMIME
        )
    }

    private static func fromMOBI(_ source: URL) async throws -> URL {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count >= 128, data.count <= 50 * 1024 * 1024 else { throw ImportFormatError.corrupt }
        guard String(data: data.subdata(in: 60..<68), encoding: .ascii) == "BOOKMOBI" else {
            throw ImportFormatError.unsupported
        }
        let recordTotal = Int(be16(data, 76))
        guard recordTotal >= 2, recordTotal <= 10000, data.count >= 78 + recordTotal * 8 else {
            throw ImportFormatError.corrupt
        }
        let offsets = (0..<recordTotal).map { Int(be32(data, 78 + $0 * 8)) }
        guard offsets.allSatisfy({ $0 >= 78 && $0 < data.count }),
              offsets == offsets.sorted() else { throw ImportFormatError.corrupt }
        let record0 = offsets[0]
        guard record0 + 32 < data.count else { throw ImportFormatError.corrupt }
        let compression = be16(data, record0)
        let textLength = Int(be32(data, record0 + 4))
        let textRecords = Int(be16(data, record0 + 8))
        guard textLength > 0, textLength < 50 * 1024 * 1024,
              textRecords > 0, textRecords < recordTotal else { throw ImportFormatError.corrupt }
        guard compression == 1 || compression == 2 else { throw ImportFormatError.protected }
        var text = Data()
        for idx in 1...textRecords {
            let start = offsets[idx]
            let end = idx + 1 < offsets.count ? offsets[idx + 1] : data.count
            guard start < end, end <= data.count else { throw ImportFormatError.corrupt }
            let chunk = data.subdata(in: start..<end)
            let decoded = try compression == 2 ? palmDOC(chunk) : chunk
            text.append(decoded)
            if text.count >= textLength { break }
        }
        let bytes = text.prefix(textLength)
        let decodedText = String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: .windowsCP1252)
            ?? String(decoding: bytes, as: UTF8.self)
        let withoutScripts = decodedText.replacingOccurrences(
            of: "(?is)<script[^>]*>.*?</script>", with: "", options: .regularExpression
        )
        let paragraphHTML = withoutScripts.replacingOccurrences(
            of: "(?i)</p>|<br\\s*/?>|</div>", with: "\n", options: .regularExpression
        )
        let plain = paragraphHTML.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        let paragraphs = plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { throw ImportFormatError.empty }
        let name = source.deletingPathExtension().lastPathComponent
        return try await EPUBWriter.make(title: name, paragraphs: paragraphs)
    }

    private static func be16(_ data: Data, _ offset: Int) -> UInt16 {
        (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }
    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16)
        | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }

    /// PalmDOC LZ77, formats 1 and 2 only. DRM/HuffDic are rejected.
    private static func palmDOC(_ input: Data) throws -> Data {
        let bytes = Array(input)
        var output: [UInt8] = []
        output.reserveCapacity(min(bytes.count * 2, 2_000_000))
        var index = 0
        while index < bytes.count {
            let marker = bytes[index]; index += 1
            switch marker {
            case 0...8:
                let count = Int(marker)
                guard index + count <= bytes.count else { throw ImportFormatError.corrupt }
                output.append(contentsOf: bytes[index..<(index + count)])
                index += count
            case 9...127:
                output.append(marker)
            case 128...191:
                guard index < bytes.count else { throw ImportFormatError.corrupt }
                let second = bytes[index]; index += 1
                let distance = (Int(marker & 0x3F) << 5) | (Int(second) >> 3)
                let count = Int(second & 7) + 3
                guard distance > 0 && distance <= output.count else { throw ImportFormatError.corrupt }
                for _ in 0..<count { output.append(output[output.count - distance]) }
            default:
                output.append(32)
                output.append(marker ^ 0x80)
            }
            if output.count > 55 * 1024 * 1024 { throw ImportFormatError.oversized }
        }
        return Data(output)
    }
}

enum EPUBWriter {
    static func make(title: String, paragraphs: [String], author: String = "", language: String = "und", cover: Data? = nil, coverMIME: String = "image/jpeg") async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".epub")
        let archive = try await Archive(url: output, accessMode: .create)
        let uuid = UUID().uuidString
        let chunks = EPUBTextChunks.make(paragraphs)
        let manifest = chunks.indices.map { "<item id=\"chapter\($0)\" href=\"chapter-\($0).xhtml\" media-type=\"application/xhtml+xml\"/>" }.joined()
        let spine = chunks.indices.map { "<itemref idref=\"chapter\($0)\"/>" }.joined()
        let hasCover = cover != nil && (cover?.count ?? 0) <= 8_000_000 && ["image/jpeg", "image/png", "image/webp"].contains(coverMIME)
        let coverMeta = hasCover ? "<meta name=\"cover\" content=\"cover-image\"/>" : ""
        let coverItem = hasCover ? "<item id=\"cover-image\" href=\"cover.img\" media-type=\"\(coverMIME)\"/>" : ""
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf"
        media-type="application/oebps-package+xml"/></rootfiles></container>
        """
        let opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package version="2.0" unique-identifier="bookid" xmlns="http://www.idpf.org/2007/opf">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>\(escape(title))</dc:title>
        <dc:creator>\(escape(author))</dc:creator><dc:language>\(escape(language))</dc:language><dc:identifier id="bookid">urn:uuid:\(uuid)</dc:identifier>
        \(coverMeta)</metadata><manifest>\(manifest)\(coverItem)</manifest><spine>\(spine)</spine></package>
        """
        try await add(Data("application/epub+zip".utf8), path: "mimetype", archive: archive, compress: false)
        try await add(Data(container.utf8), path: "META-INF/container.xml", archive: archive)
        try await add(Data(opf.utf8), path: "OEBPS/content.opf", archive: archive)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let text = chunk.map { "<p>\(escape($0))</p>" }.joined(separator: "\n")
            let heading = index == 0 ? "<h1>\(escape(title))</h1>" : ""
            let xhtml = """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(escape(title))</title>
            <style>p{margin:0 0 0.8em}</style></head><body>\(heading)\(text)</body></html>
            """
            try await add(Data(xhtml.utf8), path: "OEBPS/chapter-\(index).xhtml", archive: archive)
        }
        if hasCover, let cover { try await add(cover, path: "OEBPS/cover.img", archive: archive, compress: false) }
        return output
    }

    private static func add(_ data: Data, path: String, archive: Archive, compress: Bool = true) async throws {
        try await archive.addEntry(
            with: path, type: .file, uncompressedSize: Int64(data.count),
            compressionMethod: compress ? .deflate : .none,
            provider: { position, count in
                guard position >= 0, position <= data.count else { return Data() }
                let offset = Int(position)
                return data.subdata(in: offset..<min(data.count, offset + count))
            }
        )
    }

    private static func escape(_ source: String) -> String {
        source.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
