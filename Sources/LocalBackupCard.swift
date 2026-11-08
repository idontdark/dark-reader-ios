import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .json] }
    var url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CloudSyncError.invalidSnapshot }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
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
            Text(verbatim: L10n.text("Книги, закладки, прогресс и настройки в одном файле. Аудиофайлы сохраняются отдельно.", language: language))
                .font(.footnote).foregroundStyle(ReaderStyle.secondary).padding(.vertical, 12)
            PurpleAction(title: "Создать копию", icon: "square.and.arrow.up") { Task { await export() } }.disabled(busy || importing)
            Button("Восстановить из файла") { cleanupRestore(); status = ""; importing = true }
                .frame(maxWidth: .infinity, minHeight: 44).padding(.top, 4).disabled(busy || importing)
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
            .fileExporter(isPresented: $exporting, document: document, contentType: .zip, defaultFilename: "DarkReader-backup") { result in
                switch result {
                case .failure(let error): status = L10n.errorDescription(error)
                case .success: status = L10n.text("Копия сохранена в файл.")
                }
                cleanupExport()
            }
            .background {
                BackupFilePicker(isPresented: $importing) { result in
                    switch result {
                    case .success(let url): pendingImport = url; readPendingImport()
                    case .failure(let error): status = L10n.errorDescription(error)
                    }
                }.frame(width: 0, height: 0)
            }
    }

    private func readPendingImport() {
        guard let url=pendingImport else{return}
        pendingImport=nil
        cleanupRestore()
        Task { @MainActor in
            busy=true;status=L10n.text("Проверяем копию…");defer {busy=false}
            defer { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
            do {restore=try await LocalLibraryBackup.read(url);status="";confirming=true}
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
            if restore.metadataOnly { library.restoreReadingMetadata(restore.snapshot.books) }
            else { try library.restoreFromFile(restore.snapshot.books, staged: restore.files) }
            settings.restoreSettings(restore.snapshot.settings, changedAt: restore.snapshot.settingsChangedAt)
            status = L10n.text(restore.metadataOnly ? "Настройки, прогресс и закладки восстановлены для книг в библиотеке." : "Копия восстановлена. Книги доступны в библиотеке.")
        } catch { status = L10n.errorDescription(error) }
    }
    private func cleanupRestore() { if let restore { try? FileManager.default.removeItem(at: restore.directory) }; restore = nil; confirming=false }
    private func cleanupExport() { if let document { try? FileManager.default.removeItem(at: document.url.deletingLastPathComponent()) }; document = nil }
}
