import SwiftUI
import WebKit

struct SourceWebScreen: View {
    let source: SourceDescriptor
    let url: URL
    var title = ""
    var author = ""
    var language: String? = nil
    var narrator: String? = nil
    var series: String? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: BookshelfStore
    @EnvironmentObject private var navigation: ReaderNavigation
    @State private var error: String?
    var body: some View {
        NavigationStack {
            SourceWebBrowser(url: url, source: source, title: title, author: author, language: language, narrator: narrator, series: series, library: library, navigation: navigation, error: $error)
                .readerNavigationTitle(source.name, localized: false).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }.readerError($error, title: "Не удалось импортировать файл").readerNotice()
    }
}
private struct SourceWebBrowser: UIViewRepresentable {
    let url: URL
    let source: SourceDescriptor
    let title: String
    let author: String
    let language: String?
    let narrator: String?
    let series: String?
    let library: BookshelfStore
    let navigation: ReaderNavigation
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        var parent: SourceWebBrowser
        var targets: [ObjectIdentifier: URL] = [:]
        init(parent: SourceWebBrowser) { self.parent = parent }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let mime = navigationResponse.response.mimeType?.lowercased() ?? ""
            let bookFile = ["application/pdf", "text/plain", "application/rtf", "application/msword", "application/epub+zip", "application/fb2", "application/x-fictionbook+xml", "application/zip", "application/x-mobipocket-ebook"].contains(mime)
            decisionHandler(bookFile || !navigationResponse.canShowMIMEType ? .download : .allow)
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SourceDownload-" + UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = URL(fileURLWithPath: suggestedFilename).lastPathComponent
                let target = folder.appendingPathComponent(name.isEmpty ? "download" : name)
                targets[ObjectIdentifier(download)] = target; completionHandler(target)
            } catch { parent.error = L10n.errorDescription(error); completionHandler(nil) }
        }
        func downloadDidFinish(_ download: WKDownload) {
            guard let file = targets.removeValue(forKey: ObjectIdentifier(download)) else { return }
            let library = parent.library; let navigation = parent.navigation
            let title = parent.title; let author = parent.author; let audio = parent.source.kind == .audio
            let language = parent.language; let narrator = parent.narrator; let series = parent.series
            Task { @MainActor in
                defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
                do {
                    if audio { _ = try await AudioImportStore.importFiles([file], title: title, author: author, language: language, narrator: narrator, series: series) }
                    else { try await library.addImportedFile(from: file, title: title.isEmpty ? file.deletingPathExtension().lastPathComponent : title, author: author.isEmpty ? "Неизвестный автор" : author) }
                    navigation.notice = ReaderNotice(title: "Импорт завершён", message: L10n.text("Произведение добавлено в библиотеку."), audio: audio)
                } catch { self.parent.error = L10n.errorDescription(error) }
            }
        }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            if let file = targets.removeValue(forKey: ObjectIdentifier(download)) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            parent.error = L10n.errorDescription(error)
        }
    }
}
