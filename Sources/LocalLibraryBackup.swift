import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ReadiumZIPFoundation

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .json] }
    var url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CloudSyncError.invalidSnapshot }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}

/// A portable ZIP containing a JSON manifest and EPUBs. No folder permissions are retained.
enum LocalLibraryBackup {
    /// A light export intentionally excludes book files. ZIP remains the complete EPUB backup.
    static func createMetadata(_ snapshot: CloudLibrarySnapshot) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("DarkReader-settings.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= 10_000_000 else { throw CloudSyncError.invalidSnapshot }
        try data.write(to: url, options: .atomic)
        return url
    }
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
        let prefix = try handle.read(upToCount: 64) ?? Data()
        try handle.close()
        if let first = prefix.first(where: { ![9,10,13,32].contains($0) }), first == 123 {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10_000_000 else { throw CloudSyncError.invalidSnapshot }
            let snapshot = try JSONDecoder().decode(CloudLibrarySnapshot.self, from: Data(contentsOf: url))
            guard snapshot.schema == 1, snapshot.books.count <= 10_000,
                  Set(snapshot.books.map(\.id)).count == snapshot.books.count else { throw CloudSyncError.invalidSnapshot }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return Restored(snapshot: snapshot, files: [:], directory: directory, metadataOnly: true)
        }
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

struct LocalBackupCard: View {
    @EnvironmentObject private var library: BookshelfStore
    @EnvironmentObject private var settings: CloudSyncManager
    @AppStorage("appLanguage") private var language = "ru"
    @State private var document: BackupDocument?
    @State private var exportType: UTType = .zip
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport:URL?
    @State private var confirming = false
    @State private var restore: LocalLibraryBackup.Restored?
    @State private var busy = false
    @State private var status = ""
    var body: some View {
        ReaderCard {
            Label("Копия в файле", systemImage: "externaldrive").font(.headline)
            Text(verbatim: L10n.text("Архив ZIP: электронные книги, закладки, прогресс и настройки. Аудиофайлы не включаются.", language: language))
                .font(.footnote).foregroundStyle(ReaderStyle.secondary).padding(.vertical, 12)
            PurpleAction(title: "Сохранить в файл", icon: "square.and.arrow.up") { Task { await export() } }.disabled(busy)
            Button("Экспортировать настройки и прогресс (JSON)") { Task { await export(metadataOnly: true) } }
                .font(.footnote).frame(minHeight: 44).disabled(busy)
            Text(verbatim: L10n.text("JSON сохраняет настройки, прогресс и закладки. Файлы книг в него не входят.", language: language))
                .font(.caption).foregroundStyle(ReaderStyle.secondary)
            Button("Восстановить из файла") { importing = true }.frame(minHeight: 44).padding(.top, 8).disabled(busy)
            if confirming {
                Text(verbatim: L10n.text(restore?.metadataOnly == true ? "Восстановить настройки и прогресс?" : "Восстановить библиотеку из файла?"))
                    .font(.subheadline.weight(.semibold)).padding(.top, 12)
                Text(verbatim: L10n.text(restore?.metadataOnly == true ? "Прогресс и закладки восстановятся для книг, которые уже есть в библиотеке. Настройки будут заменены." : "Книги будут добавлены к библиотеке. Существующие книги не удаляются. Настройки будут восстановлены из копии."))
                    .font(.footnote).foregroundStyle(ReaderStyle.secondary).padding(.vertical, 8)
                HStack {
                    Button("Отмена", role: .cancel) { cleanupRestore() }
                    Spacer()
                    Button("Восстановить") { applyRestore() }.fontWeight(.semibold)
                }.frame(minHeight: 44)
            }
            if busy { ProgressView().padding(.top, 8) }
            if !status.isEmpty { Text(verbatim: status).font(.footnote).foregroundStyle(ReaderStyle.secondary).padding(.top, 8) }
        }
            .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: exportType == .json ? "DarkReader-settings" : "DarkReader-backup") { result in
                switch result {
                case .failure(let error): status = L10n.errorDescription(error)
                case .success: status = L10n.text("Копия сохранена в файл.")
                }
                cleanupExport()
            }
            .sheet(isPresented:$importing) {
                BackupFilePicker { result in
                    importing=false
                    switch result {
                    case .success(let url): pendingImport=url;readPendingImport()
                    case .failure(let error): status=L10n.errorDescription(error)
                    }
                }
            }
    }
    private func readPendingImport() {
        guard let url=pendingImport else{return}
        pendingImport=nil
        cleanupRestore()
        Task { @MainActor in
            busy=true;status="";defer {busy=false}
            defer { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
            do {restore=try await LocalLibraryBackup.read(url);confirming=true}
            catch {status=L10n.errorDescription(error)}
        }
    }
    private func export(metadataOnly: Bool = false) async {
        busy = true; status = ""; defer { busy = false }
        do {
            guard let snapshot = settings.makeSnapshot() else { throw CloudSyncError.invalidSnapshot }
            let files = Dictionary(uniqueKeysWithValues: library.books.map { ($0.id, library.fileURL(for: $0)) })
            let url: URL
            if metadataOnly { url = try LocalLibraryBackup.createMetadata(snapshot) }
            else { url = try await LocalLibraryBackup.create(snapshot, files: files) }
            exportType = metadataOnly ? .json : .zip
            document = BackupDocument(url: url); exporting = true
        } catch { status = L10n.errorDescription(error) }
    }
    private func applyRestore() {
        guard let restore else { return }
        defer { cleanupRestore() }
        do {
            // File restore is additive: backup tombstones must not delete current books.
            if restore.metadataOnly { library.restoreReadingMetadata(restore.snapshot.books) }
            else { try library.restoreFromFile(restore.snapshot.books, staged: restore.files) }
            settings.restoreSettings(restore.snapshot.settings, changedAt: restore.snapshot.settingsChangedAt)
            status = L10n.text("Копия восстановлена. Книги доступны в библиотеке.")
        } catch { status = L10n.errorDescription(error) }
    }
    private func cleanupRestore() { if let restore { try? FileManager.default.removeItem(at: restore.directory) }; restore = nil; confirming=false }
    private func cleanupExport() { if let document { try? FileManager.default.removeItem(at: document.url.deletingLastPathComponent()) }; document = nil }
}
