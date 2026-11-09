import Foundation
import AVFoundation
import ReadiumZIPFoundation

enum AudioImportStore {
    struct Manifest: Codable { var book: AudioBook; var chapters: [AudioChapter] }
    static let extensions = ["mp3", "m4a", "m4b", "zip"]
    static func directory(_ id: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioImports", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }
    static func chapters(for book: AudioBook) throws -> [AudioChapter] {
        let manifest = try read(book)
        return manifest.chapters.map {
            var track = $0
            track = AudioChapter(id: track.id, title: track.title,
                                 url: directory(book.sourceID).appendingPathComponent(track.url.lastPathComponent),
                                 durationSeconds: track.durationSeconds, startSeconds: track.startSeconds)
            return track
        }
    }
    static func read(_ book: AudioBook) throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory(book.sourceID).appendingPathComponent("manifest.json")))
    }
    static func save(_ manifest: Manifest) throws {
        try JSONEncoder().encode(manifest).write(to: directory(manifest.book.sourceID).appendingPathComponent("manifest.json"), options: .atomic)
        var history = (UserDefaults.standard.string(forKey: "audio.historyJSON")?.data(using: .utf8)).flatMap {
            try? JSONDecoder().decode([AudioBook].self, from: $0)
        } ?? []
        history.removeAll { $0.id == manifest.book.id }
        history.insert(manifest.book, at: 0)
        UserDefaults.standard.set(String(decoding: try JSONEncoder().encode(history), as: UTF8.self), forKey: "audio.historyJSON")
    }
    static func importFiles(_ urls: [URL], title: String = "", author: String = "", language: String? = nil, narrator: String? = nil, series: String? = nil) async throws -> AudioBook {
        let id = UUID().uuidString
        let folder = directory(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: folder) } }
        var files: [URL] = []
        var sourceNames: [URL: String] = [:]
        var total: UInt64 = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if url.pathExtension.lowercased() == "zip" {
                let archive = try await Archive(url: url, accessMode: .read)
                let ordered = try await archive.entries().sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                for entry in ordered {
                    let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
                    guard entry.type == .file, ["mp3", "m4a", "m4b"].contains(ext) else { continue }
                    total += UInt64(entry.uncompressedSize)
                    guard total <= 2_000_000_000, files.count < 1000 else { throw ImportFormatError.oversized }
                    let destination = folder.appendingPathComponent(String(format: "%04d-", files.count) + UUID().uuidString + "." + ext)
                    try await archive.extract(entry, to: destination)
                    files.append(destination)
                    sourceNames[destination] = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
                }
            } else {
                let ext = url.pathExtension.lowercased()
                guard ["mp3", "m4a", "m4b"].contains(ext) else { throw ImportFormatError.unsupported }
                let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += UInt64(max(0, size))
                guard total <= 2_000_000_000 else { throw ImportFormatError.oversized }
                let target = folder.appendingPathComponent(UUID().uuidString + "." + ext)
                try FileManager.default.copyItem(at: url, to: target)
                files.append(target)
                sourceNames[target] = url.deletingPathExtension().lastPathComponent
            }
        }
        guard !files.isEmpty else { throw AudioCatalogError.noTracks }
        var tracks: [AudioChapter] = []
        var foundTitle = ""
        var foundAuthor = ""
        var cover: URL?
        for (index, file) in files.enumerated() {
            let asset = AVURLAsset(url: file)
            guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw ImportFormatError.corrupt }
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw ImportFormatError.corrupt }
            let metadata = try await asset.load(.commonMetadata)
            func text(_ identifier: AVMetadataIdentifier) async -> String? {
                guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first else { return nil }
                return try? await item.load(.stringValue)
            }
            let trackTitle = await text(.commonIdentifierTitle) ?? sourceNames[file] ?? String(index + 1)
            if index == 0 {
                foundTitle = await text(.commonIdentifierAlbumName) ?? urls.first?.deletingPathExtension().lastPathComponent ?? trackTitle
                foundAuthor = await text(.commonIdentifierArtist) ?? ""
                if let artwork = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
                   let bytes = try? await artwork.load(.dataValue), bytes.count < 10_000_000 {
                    let target = folder.appendingPathComponent("cover.jpg")
                    try bytes.write(to: target, options: .atomic)
                    cover = target
                }
            }
            var groups = (try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: ["ru", "en"])) ?? []
            if groups.isEmpty {
                // Many M4B containers tag chapter titles as "und" rather than ru/en.
                let locales = (try? await asset.load(.availableChapterLocales)) ?? []
                for locale in locales {
                    groups = (try? await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [])) ?? []
                    if !groups.isEmpty { break }
                }
                print("IMPORT_CHAPTERS locales=\(locales.map(\.identifier)) count=\(groups.count)")
            }
            if groups.isEmpty {
                tracks.append(AudioChapter(id: "\(id):\(tracks.count)", title: trackTitle,
                                           url: file, durationSeconds: duration))
            } else {
                for group in groups {
                    let item = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first
                    let name = try? await item?.load(.stringValue)
                    tracks.append(AudioChapter(id: "\(id):\(tracks.count)", title: name ?? "Глава \(tracks.count + 1)",
                                               url: file, durationSeconds: group.timeRange.duration.seconds,
                                               startSeconds: group.timeRange.start.seconds))
                }
            }
        }
        let fallback = urls.first?.deletingPathExtension().lastPathComponent ?? "Аудиокнига"
        let book = AudioBook(id: "local:\(id)", source: .local, sourceID: id,
                             title: title.isEmpty ? (foundTitle.isEmpty ? fallback : foundTitle) : title,
                             author: author.isEmpty ? (foundAuthor.isEmpty ? "Автор не указан" : foundAuthor) : author,
                             description: "", coverURL: cover, language: language, narrator: narrator, durationSeconds: tracks.reduce(0) { $0 + ($1.durationSeconds ?? 0) }, series: series)
        try save(Manifest(book: book, chapters: tracks))
        committed = true
        return book
    }
    static func importURL(_ url: URL, title: String, author: String) async throws -> AudioBook {
        guard url.scheme == "https", url.host != nil else {
            throw ReaderError.invalidCatalogURL
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AudioCatalogError.unavailable }
        let mime = http.mimeType?.lowercased() ?? ""
        let ext: String
        if extensions.contains(url.pathExtension.lowercased()) { ext = url.pathExtension.lowercased() }
        else if mime.contains("mpeg") { ext = "mp3" }
        else if mime.contains("mp4") || mime.contains("m4a") { ext = "m4a" }
        else if mime.contains("zip") { ext = "zip" }
        else { throw ImportFormatError.unsupported }
        let file = temporary.appendingPathExtension(ext)
        try FileManager.default.moveItem(at: temporary, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        return try await importFiles([file], title: title, author: author)
    }
}
