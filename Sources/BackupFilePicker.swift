import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Own the UIKit presentation separately from SwiftUI's export sheet. A document
/// provider supplies an imported copy; validation never depends on its ZIP UTI.
struct BackupFilePicker: UIViewControllerRepresentable {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    @Binding var isPresented: Bool
    let selected: (Result<URL?, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> PickerHost {
        let host = PickerHost()
        host.onAppear = { [weak coordinator = context.coordinator, weak host] in
            if let host { coordinator?.presentIfNeeded(from: host) }
        }
        return host
    }
    func updateUIViewController(_ controller: PickerHost, context: Context) {
        context.coordinator.parent = self
        context.coordinator.presentIfNeeded(from: controller)
    }
    final class PickerHost: UIViewController {
        var onAppear: (() -> Void)?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onAppear?() }
    }
    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: BackupFilePicker
        private var active = false
        init(parent: BackupFilePicker) { self.parent = parent }
        func presentIfNeeded(from host: UIViewController) {
            guard parent.isPresented, !active, host.viewIfLoaded?.window != nil,
                  host.presentedViewController == nil else { return }
            active = true
            // .data accepts regular files, including ZIPs described as generic
            // data by Files providers, without entering folder-selection mode.
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
            picker.allowsMultipleSelection = false
            picker.shouldShowFileExtensions = true
            picker.delegate = self
            picker.view.tintColor = UIColor(Color(hex: parent.accentHex))
            host.present(picker, animated: true)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { finish(.success(nil), controller: controller); return }
            Task { @MainActor in
                do {
                    let copy = try await Task.detached(priority: .userInitiated) {
                        try Self.materialize(url)
                    }.value
                    finish(.success(copy), controller: controller)
                } catch { finish(.failure(error), controller: controller) }
            }
        }
        private func finish(_ result: Result<URL?, Error>, controller: UIDocumentPickerViewController) {
            guard active else { return }
            parent.isPresented = false
            controller.dismiss(animated: true) { [self] in
                active = false
                parent.selected(result)
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
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(.success(nil), controller: controller) }
    }
}
