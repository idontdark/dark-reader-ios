import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ReadiumZIPFoundation

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CloudSyncError.invalidSnapshot }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}

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
    }
    static func read(_ url: URL) async throws -> Restored {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
            Button("Восстановить из файла") { importing = true }.frame(minHeight: 44).padding(.top, 8).disabled(busy)
            if busy { ProgressView().padding(.top, 8) }
            if !status.isEmpty { Text(verbatim: status).font(.footnote).foregroundStyle(ReaderStyle.secondary).padding(.top, 8) }
        }
            .fileExporter(isPresented: $exporting, document: document, contentType: .zip, defaultFilename: "DarkReader-backup") { result in
                switch result {
                case .failure(let error): status = L10n.errorDescription(error)
                case .success: status = L10n.text("Копия сохранена в файл.")
                }
                cleanupExport()
            }
            .sheet(isPresented:$importing,onDismiss:readPendingImport) {
                BackupFilePicker {url in pendingImport=url;importing=false}
            }
            .alert("Восстановить библиотеку из файла?", isPresented: $confirming) {
                Button("Восстановить") { applyRestore() }
                Button("Отмена", role: .cancel) { cleanupRestore() }
            } message: { Text("Книги будут добавлены к библиотеке. Существующие книги не удаляются. Настройки будут восстановлены из копии.") }
    }
    private func readPendingImport() {
        guard let url=pendingImport else{return}
        pendingImport=nil
        Task { @MainActor in
            busy=true;status="";defer {busy=false}
            do {restore=try await LocalLibraryBackup.read(url);confirming=true}
            catch {status=L10n.errorDescription(error)}
        }
    }
    private func export() async {
        busy = true; status = ""; defer { busy = false }
        do {
            guard let snapshot = settings.makeSnapshot() else { throw CloudSyncError.invalidSnapshot }
            let files = Dictionary(uniqueKeysWithValues: library.books.map { ($0.id, library.fileURL(for: $0)) })
            let url = try await LocalLibraryBackup.create(snapshot, files: files)
            document = BackupDocument(url: url); exporting = true
        } catch { status = L10n.errorDescription(error) }
    }
    private func applyRestore() {
        guard let restore else { return }
        defer { cleanupRestore() }
        do {
            // File restore is additive: backup tombstones must not delete current books.
            try library.restoreFromFile(restore.snapshot.books, staged: restore.files)
            settings.restoreSettings(restore.snapshot.settings, changedAt: restore.snapshot.settingsChangedAt)
            status = L10n.text("Копия восстановлена. Книги доступны в библиотеке.")
        } catch { status = L10n.errorDescription(error) }
    }
    private func cleanupRestore() { if let restore { try? FileManager.default.removeItem(at: restore.directory) }; restore = nil }
    private func cleanupExport() { if let document { try? FileManager.default.removeItem(at: document.url.deletingLastPathComponent()) }; document = nil }
}
