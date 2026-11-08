import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Text and embedded metadata only; never resolves remote XML entities.
struct FB2Document: Sendable {
    var title = ""
    var author = ""
    var language = "und"
    var paragraphs: [String] = []
    var cover: Data?
    var coverMIME = "image/jpeg"
    static func parse(_ data: Data) throws -> FB2Document {
        let delegate = FB2DocumentParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.document.paragraphs.isEmpty else { throw ImportFormatError.corrupt }
        return delegate.document
    }
}

private final class FB2DocumentParser: NSObject, XMLParserDelegate {
    var document = FB2Document()
    private var body = false
    private var titleInfo = false
    private var coverPage = false
    private var author = false
    private var field: String?
    private var buffer = ""
    private var authorParts: [String] = []
    private var coverID: String?
    private var binary = false
    private var captureBinary = false
    private var encoded = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let tag = name.split(separator: ":").last.map(String.init) ?? name
        if tag == "binary" {
            binary = true
            let mime = attributes["content-type"]?.lowercased() ?? ""
            captureBinary = coverID != nil && attributes["id"] == coverID && ["image/jpeg", "image/png", "image/webp"].contains(mime)
            if captureBinary { document.coverMIME = mime; encoded = "" }
            return
        }
        guard !binary else { return }
        switch tag {
        case "body": body = true
        case "title-info": titleInfo = true
        case "coverpage": coverPage = titleInfo
        case "image" where coverPage:
            if let ref = attributes.first(where: { $0.key.split(separator: ":").last == "href" })?.value, ref.hasPrefix("#") { coverID = String(ref.dropFirst()) }
        case "author" where titleInfo: author = true; authorParts = []
        case let tag where titleInfo && ["book-title", "lang"].contains(tag): field = tag; buffer = ""
        case let tag where author && ["first-name", "middle-name", "last-name", "nickname"].contains(tag): field = tag; buffer = ""
        case "p" where body: field = "p"; buffer = ""
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if binary {
            if captureBinary {
                guard encoded.utf8.count + string.utf8.count <= 12_000_000 else { captureBinary = false; encoded = ""; return }
                encoded += string
            }
        } else if field != nil { buffer += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let tag = name.split(separator: ":").last.map(String.init) ?? name
        if tag == "binary" {
            if captureBinary, let bytes = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), bytes.count <= 8_000_000 { document.cover = bytes }
            binary = false; captureBinary = false; encoded = ""; return
        }
        guard !binary else { return }
        if field == tag {
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                switch tag {
                case "book-title": document.title = value
                case "lang": document.language = value
                case "p": document.paragraphs.append(value)
                default: authorParts.append(value)
                }
            }
            field = nil; buffer = ""
        }
        if tag == "author" && author { if document.author.isEmpty { document.author = authorParts.joined(separator: " ") }; author = false }
        if tag == "title-info" { titleInfo = false }
        if tag == "coverpage" { coverPage = false }
        if tag == "body" { body = false }
    }
}

/// Bound each reading-order resource so changing font size does not lay out an
/// entire compilation. A single unusually long paragraph is kept intact.
enum EPUBTextChunks {
    static func make(_ paragraphs: [String], byteLimit: Int = 64 * 1024) -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []
        var bytes = 0
        for paragraph in paragraphs {
            let size = escape(paragraph).utf8.count + 8
            if !current.isEmpty && bytes + size > byteLimit { chunks.append(current); current = []; bytes = 0 }
            current.append(paragraph); bytes += size
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
