import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ReadiumZIPFoundation

struct BookMetadata: Sendable {
    var title: String?
    var author: String?
    var cover: Data?
    static func read(_ url: URL) async throws -> BookMetadata {
        let archive = try await Archive(url: url, accessMode: .read)
        let entries = try await archive.entries()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        func bytes(_ path: String, limit: UInt64) async throws -> Data? {
            guard let entry = entries.first(where: { $0.path == path }), entry.type == .file, UInt64(entry.uncompressedSize) <= limit else { return nil }
            let target = temporary.appendingPathComponent(UUID().uuidString)
            try await archive.extract(entry, to: target)
            return try Data(contentsOf: target)
        }
        guard let container = try await bytes("META-INF/container.xml", limit: 256_000) else { return BookMetadata() }
        let root = EPUBMetadataParser()
        guard root.parse(container), let package = root.package,
              let opf = try await bytes(package, limit: 2_000_000) else { return BookMetadata() }
        let metadata = EPUBMetadataParser()
        guard metadata.parse(opf) else { return BookMetadata() }
        var result = BookMetadata(title: metadata.title, author: metadata.author)
        if let href = metadata.coverHref, let path = resourcePath(href, relativeTo: package) {
            result.cover = try await bytes(path, limit: 8_000_000)
        }
        return result
    }
    static func resourcePath(_ href: String, relativeTo package: String) -> String? {
        let reference = String(href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        guard let decoded = reference.removingPercentEncoding,
              !decoded.contains(":"), !decoded.hasPrefix("/"), !decoded.contains("\\"),
              !package.hasPrefix("/"), !package.contains("\\") else { return nil }
        // NSString.standardizingPath can discard leading parent components on
        // Darwin. Resolve archive names lexically, without filesystem expansion.
        var components: [String] = []
        for part in package.split(separator: "/").dropLast() + decoded.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !components.isEmpty else { return nil }
                components.removeLast()
            } else { components.append(String(part)) }
        }
        return components.isEmpty ? nil : components.joined(separator: "/")
    }
}

private final class EPUBMetadataParser: NSObject, XMLParserDelegate {
    var package: String?
    var title: String?
    var author: String?
    private var items: [(String, String, String)] = []
    private var coverID: String?
    private var explicitCover: String?
    private var field: String?
    private var text = ""
    var coverHref: String? {
        explicitCover ?? items.first(where: { $0.0 == coverID })?.1 ?? items.first(where: {
            $0.2.hasPrefix("image/") && ($0.0.lowercased().contains("cover") || $0.1.lowercased().contains("cover"))
        })?.1
    }
    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = self
        return parser.parse()
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let tag = name.split(separator: ":").last.map(String.init) ?? name
        switch tag {
        case "rootfile": if package == nil { package = attributes["full-path"] }
        case "title", "creator": field = tag; text = ""
        case "meta" where attributes["name"] == "cover": coverID = attributes["content"]
        case "item":
            if let id = attributes["id"], let href = attributes["href"], let type = attributes["media-type"] {
                items.append((id, href, type))
                if type.hasPrefix("image/"), (attributes["properties"] ?? "").split(separator: " ").contains("cover-image") { explicitCover = href }
            }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if field != nil && text.count < 4096 { text += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let tag = name.split(separator: ":").last.map(String.init) ?? name
        guard field == tag else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { if tag == "title" && title == nil { title = value }; if tag == "creator" && author == nil { author = value } }
        field = nil; text = ""
    }
}
