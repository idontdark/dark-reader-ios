import SwiftUI
import PDFKit
import QuickLook

struct NativeDocumentReader: View {
    let bookID: UUID
    let initialLocation: String?
    @EnvironmentObject private var library: BookshelfStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("readerTheme") private var theme = "system"
    @AppStorage("readerPersistentProgress") private var persistentProgress = false
    @AppStorage("readerProgressDisplay") private var format = "percent"
    @State private var chrome = false
    @State private var page = 0
    @State private var count = 1
    private var book: LocalBook? { library.books.first { $0.id == bookID } }
    private var paper: ReaderPaper { ReaderPaper(theme: theme == "system" ? (colorScheme == .dark ? "dark" : "light") : theme) }
    var body: some View {
        ZStack {
            paper.background.ignoresSafeArea()
            if let book {
                if book.filename.lowercased().hasSuffix(".pdf") {
                    PDFReadingView(url: library.fileURL(for: book), startingPage: startingPage(book), background: paper.background) { page, count in
                        self.page = page; self.count = count; persist(book, bookmark: false)
                    }.simultaneousGesture(TapGesture().onEnded { chrome.toggle() })
                    if chrome || persistentProgress {
                        VStack { Spacer(); Text(verbatim: progressText).font(.caption).padding(8).frame(maxWidth: .infinity).background(paper.background) }.allowsHitTesting(false)
                    }
                } else { DocumentPreview(url: library.fileURL(for: book)) }
                if chrome || !book.filename.lowercased().hasSuffix(".pdf") { controls(book) }
            }
        }.foregroundStyle(paper.text).statusBarHidden(!chrome)
    }
    private var progressText: String {
        ReadingProgressDisplay.stored(format).text(fraction: count > 1 ? Double(page) / Double(count - 1) : 1,
            position: page + 1, total: count, language: L10n.language)
    }
    private func controls(_ book: LocalBook) -> some View {
        VStack {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1); Spacer()
                if book.filename.lowercased().hasSuffix(".pdf") {
                    Button { persist(book, bookmark: true) } label: { Image(systemName: "bookmark").frame(width: 44, height: 44) }
                        .accessibilityLabel(Text(verbatim: L10n.text("Добавить закладку")))
                }
            }.padding(8).background(paper.background, in: RoundedRectangle(cornerRadius: 16)).padding(12)
            Spacer()
        }
    }
    private func startingPage(_ book: LocalBook) -> Int {
        guard let raw = (initialLocation ?? book.locatorJSON)?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return 0 }
        return object["pdfPage"] as? Int ?? 0
    }
    private func persist(_ book: LocalBook, bookmark: Bool) {
        let object: [String: Any] = ["href": book.filename, "type": "application/pdf", "pdfPage": page,
            "title": L10n.text("Страница") + " \(page + 1)",
            "locations": ["position": page + 1, "totalProgression": count > 1 ? Double(page) / Double(count - 1) : 1]]
        guard let bytes = try? JSONSerialization.data(withJSONObject: object) else { return }
        let raw = String(decoding: bytes, as: UTF8.self)
        library.savePosition(bookID: book.id, locatorJSON: raw)
        if bookmark { library.saveBookmark(bookID: book.id, locatorJSON: raw) }
    }
}
private struct PDFReadingView: UIViewRepresentable {
    let url: URL
    let startingPage: Int
    let background: SwiftUI.Color
    let onPage: (Int, Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPage: onPage) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical; view.document = PDFDocument(url: url)
        if let doc = view.document, let page = doc.page(at: max(0, min(startingPage, doc.pageCount - 1))) { view.go(to: page) }
        context.coordinator.observe(view)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { view.backgroundColor = UIColor(background) }
    @MainActor final class Coordinator {
        let onPage: (Int, Int) -> Void
        var observer: NSObjectProtocol?
        init(onPage: @escaping (Int, Int) -> Void) { self.onPage = onPage }
        func observe(_ view: PDFView) {
            observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let self, let doc = view?.document, let page = view?.currentPage else { return }
                let index = doc.index(for: page)
                DispatchQueue.main.async { self.onPage(index, doc.pageCount) }
            }
            if let doc = view.document, let page = view.currentPage {
                let index = doc.index(for: page); DispatchQueue.main.async { self.onPage(index, doc.pageCount) }
            }
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
private struct DocumentPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let view = QLPreviewController(); view.dataSource = context.coordinator; return view
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) { }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
