import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Import a copy, then read it after the system picker has dismissed.
/// Accept file-provider data UTIs; the archive reader validates the actual bytes.
struct BackupFilePicker: UIViewControllerRepresentable {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    let selected: (Result<URL?, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Accept all regular files. Validate archive/JSON bytes after selection rather
        // than relying on the file provider's sometimes incomplete ZIP type metadata.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        picker.view.tintColor=UIColor(Color(hex:accentHex))
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {controller.view.tintColor=UIColor(Color(hex:accentHex))}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (Result<URL?, Error>) -> Void
        init(selected: @escaping (Result<URL?, Error>) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { selected(.success(nil)); return }
            // Materialize a private copy while the provider's access grant is alive.
            // SwiftUI reads it only after the picker has finished dismissing.
            Task { @MainActor in
                do {
                    let copy = try await Task.detached(priority: .userInitiated) {
                        try Self.materialize(url)
                    }.value
                    selected(.success(copy))
                } catch { selected(.failure(error)) }
            }
        }
        nonisolated private static func materialize(_ url: URL) throws -> URL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BackupImport-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("backup").appendingPathExtension(url.pathExtension)
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
                do {
                    let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard attributes.isRegularFile == true, (attributes.fileSize ?? 0) <= 2_100_000_000 else {
                        throw CloudSyncError.invalidSnapshot
                    }
                    try FileManager.default.copyItem(at: source, to: target)
                } catch { copyError = error }
            }
            if let error = coordinationError ?? copyError.map({ $0 as NSError }) {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
            return target
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selected(.success(nil)) }
    }
}
