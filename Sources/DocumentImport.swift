import Foundation
import SwiftSoup
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum BookFileValidator {
    static let importExtensions = ["epub", "fb2", "mobi", "zip", "pdf", "txt", "html", "htm", "rtf", "doc"]
    static func storedExtension(_ filename: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ["epub", "pdf", "doc"].contains(ext) ? ext : "epub"
    }
    static func validate(_ url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 4, size <= 50 * 1024 * 1024 else { throw ImportFormatError.oversized }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let data = try file.read(upToCount: 256) ?? Data()
        switch url.pathExtension.lowercased() {
        case "epub": guard data.starts(with: [0x50, 0x4B]) else { throw ImportFormatError.corrupt }
        case "pdf": guard data.starts(with: Data("%PDF-".utf8)) else { throw ImportFormatError.corrupt }
        case "doc":
            guard data.starts(with: [0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1]) else { throw ImportFormatError.corrupt }
        default: throw ImportFormatError.unsupported
        }
    }
}
enum DocumentImport {
    static func convert(_ source: URL) async throws -> URL {
        let data = try Data(contentsOf: source)
        guard data.count <= 50 * 1024 * 1024 else { throw ImportFormatError.oversized }
        var title = source.deletingPathExtension().lastPathComponent
        let text: String
        switch source.pathExtension.lowercased() {
        case "html", "htm":
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else { throw ImportFormatError.corrupt }
            let doc = try SwiftSoup.parse(html)
            try doc.select("script, style, iframe, object, form, nav").remove()
            if let value = try? doc.title(), !value.isEmpty { title = value }
            // Preserve paragraph boundaries before SwiftSoup normalizes whitespace.
            try doc.select("br").append("\n")
            try doc.select("p, div, h1, h2, h3, li").append("\n")
            text = (try? doc.body()?.text(trimAndNormaliseWhitespace: false)) ?? ""
        case "rtf":
            #if canImport(UIKit) || canImport(AppKit)
            text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
            #else
            throw ImportFormatError.unsupported
            #endif
        default:
            guard let decoded = String(data: data, encoding: .utf8) ?? ((data.starts(with: [0xFF,0xFE]) || data.starts(with: [0xFE,0xFF])) ? String(data: data, encoding: .utf16) : String(data: data, encoding: .windowsCP1251)) else { throw ImportFormatError.corrupt }
            text = decoded
        }
        let paragraphs = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { throw ImportFormatError.empty }
        return try await EPUBWriter.make(title: title, paragraphs: paragraphs)
    }
}
