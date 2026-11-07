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
    @EnvironmentObject private var sync: CloudSyncManager
    @EnvironmentObject private var store: BookshelfStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("readerFontSize") private var fontSize = 1.1
    @AppStorage("readerTheme") private var theme = "system"
    @AppStorage("readerFont") private var font = "serif"
    @AppStorage("readerScroll") private var scroll = false
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    let bookID: UUID
    @State private var session: ReaderSession?
    @State private var error: String?
    @State private var appearanceOpen = false

    private var book: LocalBook? { store.books.first(where: { $0.id == bookID }) }

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    ReaderContainer(navigator: session.navigator)
                        .ignoresSafeArea(edges: .bottom)
                } else if let error {
                    ContentUnavailableView(
                        "Не удалось открыть книгу",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ProgressView("Открываем книгу…")
                }
            }
            .navigationTitle(book?.title ?? "Читалка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { persist(); dismiss() } label: {
                        Image(systemName: "chevron.down")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Добавить закладку", systemImage: "bookmark.fill") {
                            addBookmark()
                        }
                        if let marks = book?.bookmarks, !marks.isEmpty {
                            Divider()
                            ForEach(marks.indices, id: \.self) { i in
                                Button("Закладка \(i + 1)") {
                                    Task { await openBookmark(marks[i]) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    Button { appearanceOpen = true } label: {
                        Image(systemName: "textformat.size")
                    }
                }
            }
            .tint(Color(hex: accentHex))
        }
        .sheet(isPresented: $appearanceOpen) {
            ReaderAppearanceSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await load()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 20_000_000_000) }
                catch { break }
                persist()
            }
        }
        .onDisappear { persist() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
        .onChange(of: fontSize) { _, value in
            apply()
            sync.settingsChanged(key: "readerFontSize", value: String(value))
        }
        .onChange(of: font) { _, value in
            apply()
            sync.settingsChanged(key: "readerFont", value: value)
        }
        .onChange(of: theme) { _, value in
            apply()
            sync.settingsChanged(key: "readerTheme", value: value)
        }
        .onChange(of: colorScheme) { _, _ in apply() }
        .onChange(of: scroll) { _, value in
            apply()
            sync.settingsChanged(key: "readerScroll", value: String(value))
        }
    }

    private func load() async {
        guard session == nil, let book else { return }
        do {
            session = try await ReaderSession.open(
                fileURL: store.fileURL(for: book), previousLocation: book.locatorJSON
            )
            apply()
        } catch { self.error = error.localizedDescription }
    }

    private func apply() {
        session?.applyPreferences(
            fontSize: fontSize,
            font: font,
            theme: theme == "system" ? (colorScheme == .dark ? "dark" : "light") : theme,
            scroll: scroll
        )
    }

    private func addBookmark() {
        guard let locator = session?.navigator.currentLocation,
              let json = try? locator.jsonString() else { return }
        store.saveBookmark(bookID: bookID, locatorJSON: json)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func openBookmark(_ json: String) async {
        guard let locator = try? Locator(jsonString: json) else { return }
        await session?.navigator.go(to: locator)
        persist()
    }

    private func persist() {
        guard let locator = session?.navigator.currentLocation,
              let locatorJSON = try? locator.jsonString() else { return }
        store.savePosition(bookID: bookID, locatorJSON: locatorJSON)
    }
}

private struct ReaderAppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerTheme") private var theme = "system"
    @AppStorage("readerFont") private var font = "serif"
    @AppStorage("readerFontSize") private var fontSize = 1.1
    @AppStorage("readerScroll") private var scroll = false
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    private let options: [(String, String, Color, Color)] = [
        ("light", "Светлая", Color(red: 0.97, green: 0.97, blue: 0.95), .black),
        ("sepia", "Сепия", Color(red: 0.94, green: 0.85, blue: 0.69), .black),
        ("dark", "Тёмная", Color(red: 0.18, green: 0.18, blue: 0.20), .white),
        ("oled", "OLED", .black, .white)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel(text: "Тема чтения")
                        HStack(spacing: 9) {
                            ForEach(options, id: \.0) { item in
                                Button {
                                    theme = item.0
                                } label: {
                                    VStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 11)
                                            .fill(item.2)
                                            .frame(height: 50)
                                            .overlay {
                                                if theme == item.0 {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(item.3)
                                                }
                                            }
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 11)
                                                    .strokeBorder(theme == item.0
                                                        ? Color(hex: accentHex) : .white.opacity(0.15),
                                                        lineWidth: theme == item.0 ? 2 : 1)
                                            )
                                        Text(item.1)
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ReaderCard {
                        HStack {
                            Text("Шрифт")
                            Spacer()
                            Picker("Шрифт", selection: $font) {
                                Text("С засечками").tag("serif")
                                Text("Без засечек").tag("sans")
                            }.tint(.white)
                        }
                        ReaderDivider()
                        HStack {
                            Text("Размер текста")
                            Spacer()
                            Text("\(Int(fontSize * 100))%")
                                .foregroundStyle(ReaderStyle.secondary)
                        }
                        Slider(value: $fontSize, in: 0.7...3.0, step: 0.1)
                            .tint(Color(hex: accentHex))
                        ReaderDivider()
                        Toggle("Вертикальная прокрутка", isOn: $scroll)
                            .padding(.vertical, 10)
                    }
                }
                .padding(20)
            }
            .readerCanvas()
            .navigationTitle("Оформление чтения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
