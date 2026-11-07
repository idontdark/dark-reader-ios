import SwiftUI
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

@MainActor
final class ReaderSession: ObservableObject {
    let navigator: EPUBNavigatorViewController

    private init(navigator: EPUBNavigatorViewController) {
        self.navigator = navigator
    }

    static func open(fileURL: URL, previousLocation: String?) async throws -> ReaderSession {
        let httpClient = DefaultHTTPClient()
        let retriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: retriever,
            pdfFactory: DefaultPDFDocumentFactory()
        ))
        guard let readiumURL = fileURL.anyURL.absoluteURL else { throw ReaderError.invalidEPUB }
        let asset = try await retriever.retrieve(url: readiumURL).get()
        let publication = try await opener.open(asset: asset, allowUserInteraction: true).get()
        guard publication.conforms(to: .epub) else { throw ReaderError.unsupportedPublication }
        let locator = previousLocation.flatMap { try? Locator(jsonString: $0) }
        let navigator = try EPUBNavigatorViewController(publication: publication, initialLocation: locator)
        return ReaderSession(navigator: navigator)
    }

    func applyPreferences(fontSize: Double, font: String, theme: String, scroll: Bool) {
        var preferences = EPUBPreferences(
            fontFamily: font == "sans" ? .sansSerif : .serif,
            fontSize: fontSize,
            publisherStyles: false,
            scroll: scroll
        )
        switch theme {
        case "dark", "oled": preferences.theme = .dark
        case "sepia": preferences.theme = .sepia
        default: preferences.theme = .light
        }
        navigator.submitPreferences(preferences)
    }
}

struct ReaderContainer: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { navigator }
    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {}
}

struct ReaderScreen: View {
    @EnvironmentObject private var store: BookshelfStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("readerFontSize") private var fontSize = 1.1
    @AppStorage("readerTheme") private var theme = "system"
    @AppStorage("readerFont") private var font = "serif"
    @AppStorage("readerScroll") private var scroll = false

    let bookID: UUID
    @State private var session: ReaderSession?
    @State private var error: String?

    private var book: LocalBook? { store.books.first(where: { $0.id == bookID }) }

    var body: some View {
        NavigationStack {
            Group {
                if let session = session {
                    ReaderContainer(navigator: session.navigator).ignoresSafeArea(edges: .bottom)
                } else if let error = error {
                    ContentUnavailableView("Не удалось открыть книгу", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView("Открываем EPUB…")
                }
            }
            .navigationTitle(book?.title ?? "Читалка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { persist(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("А−") { fontSize = max(0.7, fontSize - 0.15) }
                        Button("А+") { fontSize = min(3.0, fontSize + 0.15) }
                        Picker("Тема", selection: $theme) {
                            Text("Светлая").tag("light")
                            Text("Тёмная").tag("dark")
                            Text("Сепия").tag("sepia")
                            Text("OLED").tag("oled")
                        }
                    } label: { Image(systemName: "textformat.size") }
                }
            }
        }
        .task { await load() }
        .onDisappear { persist() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
        .onChange(of: fontSize) { _, _ in apply() }
        .onChange(of: font) { _, _ in apply() }
        .onChange(of: theme) { _, _ in apply() }
        .onChange(of: colorScheme) { _, _ in apply() }
        .onChange(of: scroll) { _, _ in apply() }
    }

    private func load() async {
        guard session == nil, let book = book else { return }
        do {
            session = try await ReaderSession.open(fileURL: store.fileURL(for: book), previousLocation: book.locatorJSON)
            apply()
        } catch { self.error = error.localizedDescription }
    }

    private func apply() {
        session?.applyPreferences(fontSize: fontSize, font: font, theme: theme == "system" ? (colorScheme == .dark ? "dark" : "light") : theme, scroll: scroll)
    }

    private func persist() {
        guard let locatorJSON = session?.navigator.currentLocation?.jsonString else { return }
        store.savePosition(bookID: bookID, locatorJSON: locatorJSON)
    }
}
