import Foundation
import ReadiumZIPFoundation

/// A portable ZIP containing a JSON manifest and EPUBs. No folder permissions are retained.
enum LocalLibraryBackup {
    static func create(_ snapshot: CloudLibrarySnapshot, files: [UUID: URL]) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: folder) } }
        guard snapshot.books.count <= 10_000 else {throw ImportFormatError.oversized}
        var total:Int64=0
        for file in files.values {
            let size=Int64(try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
            guard size <= 50*1024*1024 else {throw ImportFormatError.oversized}
            total += size
        }
        guard total <= 2_000_000_000 else {throw ImportFormatError.oversized}
        let manifest = folder.appendingPathComponent("library.json")
        let metadata=try JSONEncoder().encode(snapshot)
        guard metadata.count<=10_000_000 else {throw CloudSyncError.invalidSnapshot}
        try metadata.write(to: manifest, options: .atomic)
        let url = folder.appendingPathComponent("DarkReader-backup.zip")
        let archive = try await Archive(url: url, accessMode: .create)
        try await archive.addEntry(with: "library.json", fileURL: manifest)
        for book in snapshot.books {
            try Task.checkCancellation()
            guard let file = files[book.id] else { throw CloudSyncError.unavailableData }
            try await archive.addEntry(with: "Books/\(book.id.uuidString).epub", fileURL: file)
        }
        success = true
        return url
    }

    struct Restored {
        let snapshot: CloudLibrarySnapshot
        let files: [String: URL]
        let directory: URL
        var metadataOnly = false
    }
    static func read(_ url: URL) async throws -> Restored {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        let prefix = try handle.read(upToCount: 4096) ?? Data()
        try handle.close()
        let content = prefix.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(prefix.dropFirst(3)) : prefix
        if let first = content.first(where: { ![9,10,13,32].contains($0) }), first == 123 {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10_000_000 else { throw CloudSyncError.invalidSnapshot }
            let raw = try Data(contentsOf: url)
            let json = raw.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(raw.dropFirst(3)) : raw
            let snapshot = try JSONDecoder().decode(CloudLibrarySnapshot.self, from: json)
            guard snapshot.schema == 1, snapshot.books.count <= 10_000,
                  Set(snapshot.books.map(\.id)).count == snapshot.books.count else { throw CloudSyncError.invalidSnapshot }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return Restored(snapshot: snapshot, files: [:], directory: directory, metadataOnly: true)
        }
        guard prefix.starts(with: [0x50, 0x4B]) else { throw CloudSyncError.invalidSnapshot }
        let archive = try await Archive(url: url, accessMode: .read)
        let entries = try await archive.entries()
        guard entries.count <= 10_001, Set(entries.map(\.path)).count == entries.count,
              let manifest = entries.first(where: { $0.path == "library.json" }),
              manifest.type == .file, manifest.uncompressedSize <= 10_000_000 else { throw CloudSyncError.invalidSnapshot }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: folder) } }
        let json = folder.appendingPathComponent("library.json")
        try await archive.extract(manifest, to: json)
        let snapshot = try JSONDecoder().decode(CloudLibrarySnapshot.self, from: Data(contentsOf: json))
        guard snapshot.schema == 1, snapshot.books.count <= 10_000,
              Set(snapshot.books.map(\.id)).count == snapshot.books.count else { throw CloudSyncError.invalidSnapshot }
        var staged: [String: URL] = [:]
        var total: UInt64 = 0
        for book in snapshot.books {
            try Task.checkCancellation()
            guard let entry = entries.first(where: { $0.path == "Books/\(book.id.uuidString).epub" }),
                  entry.type == .file, entry.uncompressedSize <= 50 * 1024 * 1024 else { throw CloudSyncError.badBook }
            total += UInt64(entry.uncompressedSize)
            guard total <= 2_000_000_000 else { throw ImportFormatError.oversized }
            let target = folder.appendingPathComponent(book.id.uuidString + ".epub")
            try await archive.extract(entry, to: target)
            try await BookFormatConverter.validateContainer(target)
            staged[book.id.uuidString] = target
        }
        success = true
        return Restored(snapshot: snapshot, files: staged, directory: folder)
    }
}

