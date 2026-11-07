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
    static func prepare(_ input: URL) throws -> URL {
        let ext = input.pathExtension.lowercased()
        switch ext {
        case "epub":
            return input
        case "fb2":
            return try fromFB2(input)
        case "mobi":
            return try fromMOBI(input)
        case "zip":
            return try fromZIP(input)
        default:
            throw ImportFormatError.unsupported
        }
    }

    private static func fromZIP(_ file: URL) throws -> URL {
        let archive = try Archive(url: file, accessMode: .read)
        let choices = archive.filter { entry in
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
        try archive.extract(selected, to: destination)
        let prepared = try prepare(destination)
        return prepared
    }

    private static func fromFB2(_ source: URL) throws -> URL {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count <= 50 * 1024 * 1024 else { throw ImportFormatError.oversized }
        let parser = FB2Parser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldResolveExternalEntities = false
        guard xml.parse(), !parser.paragraphs.isEmpty else { throw ImportFormatError.corrupt }
        return try EPUBWriter.make(
            title: parser.bookTitle.isEmpty ? source.deletingPathExtension().lastPathComponent : parser.bookTitle,
            paragraphs: parser.paragraphs
        )
    }

    private static func fromMOBI(_ source: URL) throws -> URL {
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
        return try EPUBWriter.make(title: name, paragraphs: paragraphs)
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

private final class FB2Parser: NSObject, XMLParserDelegate {
    var bookTitle = ""
    var paragraphs: [String] = []
    private var withinBody = false
    private var withinBookTitle = false
    private var withinParagraph = false
    private var buffer = ""
    private var binaryDepth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        if tag == "binary" { binaryDepth += 1 }
        if binaryDepth > 0 { return }
        if tag == "body" { withinBody = true }
        if tag == "book-title" { withinBookTitle = true; buffer = "" }
        if tag == "p" && withinBody { withinParagraph = true; buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if binaryDepth == 0 && (withinBookTitle || withinParagraph) { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        if tag == "binary" { binaryDepth = max(0, binaryDepth - 1); return }
        if binaryDepth > 0 { return }
        if tag == "book-title" {
            bookTitle = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            withinBookTitle = false
            buffer = ""
        }
        if tag == "p" && withinParagraph {
            let line = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { paragraphs.append(line) }
            withinParagraph = false
            buffer = ""
        }
        if tag == "body" { withinBody = false }
    }
}

private enum EPUBWriter {
    static func make(title: String, paragraphs: [String]) throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".epub")
        let archive = try Archive(url: output, accessMode: .create)
        let uuid = UUID().uuidString
        let text = paragraphs.map { "<p>\(escape($0))</p>" }.joined(separator: "\n")
        let xhtml = """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(escape(title))</title>
        <style>body{font-family:serif;line-height:1.5}p{margin:0 0 0.8em}</style>
        </head><body><h1>\(escape(title))</h1>\(text)</body></html>
        """
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
        <dc:language>und</dc:language><dc:identifier id="bookid">urn:uuid:\(uuid)</dc:identifier>
        </metadata><manifest>
        <item id="chapter" href="book.xhtml" media-type="application/xhtml+xml"/>
        </manifest><spine><itemref idref="chapter"/></spine></package>
        """
        try add(Data("application/epub+zip".utf8), path: "mimetype", archive: archive, compress: false)
        try add(Data(container.utf8), path: "META-INF/container.xml", archive: archive)
        try add(Data(opf.utf8), path: "OEBPS/content.opf", archive: archive)
        try add(Data(xhtml.utf8), path: "OEBPS/book.xhtml", archive: archive)
        return output
    }

    private static func add(_ data: Data, path: String, archive: Archive, compress: Bool = true) throws {
        try archive.addEntry(
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
