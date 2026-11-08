import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Import a copy, then read it after the system picker has dismissed.
/// Accept file-provider data UTIs; the archive reader validates the actual bytes.
struct BackupFilePicker: UIViewControllerRepresentable {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    let selected: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        picker.view.tintColor=UIColor(Color(hex:accentHex))
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {controller.view.tintColor=UIColor(Color(hex:accentHex))}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL?) -> Void
        init(selected: @escaping (URL?) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { selected(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selected(nil) }
    }
}
