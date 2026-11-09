import SwiftUI
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator
import UIKit
import WebKit

@MainActor
final class ReaderSession: ObservableObject, EPUBNavigatorDelegate {
    let navigator: EPUBNavigatorViewController

    @Published private(set) var totalPositions = 0
    @Published private(set) var isReady = false
    @Published private(set) var displayedTheme: String
    private let publication: Publication
    private var options: ReaderOptions
    private var updateTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var transitionCover: UIView?
    @Published private(set) var location:Locator?
    @Published var errorMessage:String?
    var onLocationChange:((Locator)->Void)?
    var onToggleChrome:(()->Void)?
    var onPageTurn:(()->Void)?
    private var pageNavigation:DirectionalNavigationAdapter?
    var fraction:Double? {
        if let value=location?.locations.totalProgression {return value}
        guard let position=location?.locations.position,totalPositions>1 else{return nil}
        return Double(position-1)/Double(totalPositions-1)
    }
    private init(navigator: EPUBNavigatorViewController, publication: Publication, options: ReaderOptions) {
        self.navigator = navigator
        self.publication = publication
        self.options = options
        self.displayedTheme = options.theme
        self.location = navigator.currentLocation
        navigator.delegate=self
        let adapter=DirectionalNavigationAdapter(animatedTransition:true,onNavigation:{[weak self] in self?.onPageTurn?()})
        adapter.animatedTransition = options.animated && !UIAccessibility.isReduceMotionEnabled
        pageNavigation=adapter;adapter.bind(to:navigator)
        navigator.addObserver(.tap { [weak self] _ in
            self?.onToggleChrome?()
            return true
        })
    }
    func navigator(_ navigator:Navigator,locationDidChange locator:Locator) {
        location = locator
        if !isReady {
            isReady = true
            positionTask = Task { [weak self, publication] in
                let positions = (try? await publication.positions().get()) ?? []
                guard !Task.isCancelled else { return }
                self?.totalPositions = positions.count
            }
        }
        onLocationChange?(locator)
    }
    func navigator(_ navigator:Navigator,presentError error:NavigatorError) {
        errorMessage="Это действие недоступно для данной книги."
    }

    static func open(fileURL: URL, previousLocation: String?, options: ReaderOptions) async throws -> ReaderSession {
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
        let navigator = try EPUBNavigatorViewController(publication: publication, initialLocation: locator, config: .init(
            preferences: options.preferences,
            contentInset: [.compact: (top: 64, bottom: 40), .regular: (top: 64, bottom: 40)],
            preloadPreviousPositionCount: 0, preloadNextPositionCount: 1
        ))
        return ReaderSession(navigator: navigator, publication: publication, options: options)
    }

    func apply(_ next: ReaderOptions) {
        guard next != options else { return }
        options = next
        pageNavigation?.animatedTransition = next.animated && !UIAccessibility.isReduceMotionEnabled
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            guard let self else { return }
            // Keep the last complete page visible while WebKit changes its CSS.
            // Native chrome switches only after the page has completed two frames.
            if self.transitionCover == nil, self.isReady, let cover = self.navigator.view.snapshotView(afterScreenUpdates: false) {
                cover.frame = self.navigator.view.bounds
                cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                cover.isUserInteractionEnabled = false
                self.navigator.view.addSubview(cover)
                self.transitionCover = cover
            }
            self.navigator.submitPreferences(next.preferences)
            await Task.yield()
            for webView in Self.webViews(in: self.navigator.view) {
                _ = try? await webView.callAsyncJavaScript(
                    """
                    const root = document.documentElement;
                    const normalize = value => { const e = document.createElement('span'); e.style.color = value; e.style.position = 'fixed'; e.style.visibility = 'hidden'; document.body.appendChild(e); const result = getComputedStyle(e).color; e.remove(); return result; };
                    const expectedColor = normalize(background);
                    const deadline = Date.now() + 2000;
                    while (Date.now() < deadline) {
                        const style = getComputedStyle(root);
                        const size = parseFloat(style.getPropertyValue('--USER__fontSize'));
                        const color = style.getPropertyValue('--USER__backgroundColor').trim();
                        if (Math.abs(size - percent) < 0.01 && color && normalize(color) === expectedColor) break;
                        await new Promise(resolve => setTimeout(resolve, 32));
                    }
                    await Promise.race([document.fonts.ready, new Promise(resolve => setTimeout(resolve, 500))]);
                    await Promise.race([new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))), new Promise(resolve => setTimeout(resolve, 250))]);
                    return true;
                    """,
                    arguments: ["percent": next.fontSize * 100, "background": ReaderPaper(theme: next.theme).backgroundHex], in: nil, contentWorld: .page
                )
                guard !Task.isCancelled else { return }
            }
            guard !Task.isCancelled else { return }
            self.displayedTheme = next.theme
            self.navigator.view.backgroundColor = UIColor(ReaderPaper(theme: next.theme).background)
            self.transitionCover?.removeFromSuperview()
            self.transitionCover = nil
        }
    }
    private static func webViews(in view: UIView) -> [WKWebView] {
        if let webView = view as? WKWebView { return [webView] }
        return view.subviews.flatMap { webViews(in: $0) }
    }
    func cancelUpdates() {
        updateTask?.cancel(); positionTask?.cancel()
        transitionCover?.removeFromSuperview(); transitionCover = nil
    }

}

private extension ReaderOptions {
    var preferences: EPUBPreferences {
        var preferences = EPUBPreferences(
            fontFamily: font == "sans" ? .sansSerif : .serif,
            fontSize: fontSize, publisherStyles: false, scroll: scroll
        )
        // Readium uses a multiplier (1.0 = 100%), not an integer percentage.
        switch theme {
        case "dark", "oled": preferences.theme = .dark
        case "sepia": preferences.theme = .sepia
        default: preferences.theme = .light
        }
        let palette = ReaderPaper(theme: theme)
        preferences.backgroundColor = ReadiumNavigator.Color(hex: palette.backgroundHex)
        preferences.textColor = ReadiumNavigator.Color(hex: palette.textHex)
        return preferences
    }
}

private struct ReaderSurface: View {
    @ObservedObject var session: ReaderSession
    var body: some View {
        ZStack {
            ReaderContainer(navigator: session.navigator)
            if !session.isReady {
                ReaderPaper(theme: session.displayedTheme).background.ignoresSafeArea()
                ProgressView("Открываем книгу…").tint(ReaderPaper(theme: session.displayedTheme).text)
            }
        }
    }
}

struct ReaderContainer: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { navigator }
    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {}
}

struct ReaderScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

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
    @AppStorage("readerProgressDisplay") private var progressDisplay = "percent"
    @AppStorage("readerPersistentProgress") private var persistentProgress = false

    let bookID: UUID
    let initialLocation: String?
    init(bookID: UUID, initialLocation: String? = nil) {
        self.bookID = bookID
        self.initialLocation = initialLocation
    }
    @State private var session: ReaderSession?
    @State private var displayedTheme: String?
    @State private var bookReady = false
    @StateObject private var chrome=ReaderChrome()
    @AppStorage("readerPageAnimation") private var pageAnimation=true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var error: String?
    @State private var appearanceOpen = false
    @AppStorage("hintReaderFocusShown") private var hintReaderShown = false
    @State private var showReaderTip = false
    @State private var showBookmarks=false
    @State private var namingBookmark=false
    @State private var bookmarkName=""
    @State private var editingBookmark:Int?

    private var book: LocalBook? { store.books.first(where: { $0.id == bookID }) }

    private var effectiveTheme:String {theme == "system" ? (colorScheme == .dark ? "dark":"light"):theme}
    private var paper:ReaderPaper {ReaderPaper(theme:displayedTheme ?? effectiveTheme)}
    private var readerOptions: ReaderOptions {
        ReaderOptions(fontSize: fontSize, font: font, theme: effectiveTheme, scroll: scroll, animated: pageAnimation && !reduceMotion)
    }
    @ViewBuilder var body: some View {
        if let book, BookFileValidator.storedExtension(book.filename) != "epub" {
            NativeDocumentReader(bookID: bookID, initialLocation: initialLocation)
        } else { preferenceObservers }
    }

    @ViewBuilder private var publicationLayer: some View {
        if let session {
            ReaderSurface(session: session).ignoresSafeArea()
                .onReceive(session.$displayedTheme) { displayedTheme = $0 }
                .onReceive(session.$isReady) { bookReady = $0 }
                .accessibilityAction(named: Text(verbatim: L10n.text("Показать панель чтения"))) { chrome.visible = true }
        } else if let error {
            ContentUnavailableView("Не удалось открыть книгу", systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: L10n.render(error, language: localizationLanguage)))
        } else {
            ProgressView("Открываем книгу…")
        }
    }
    @ViewBuilder private var readerOverlays: some View {
        if let session, chrome.visible || persistentProgress {
            VStack {
                Spacer()
                ReadingProgressFooter(session: session, format: progressDisplay, theme: displayedTheme ?? effectiveTheme)
            }.allowsHitTesting(false)
        }
        if chrome.visible { readerControls }
        else if !bookReady {
            VStack {
                HStack { readerButton("chevron.down", label: "Закрыть книгу") { dismiss() }; Spacer() }
                Spacer()
            }.padding(12)
        }
    }
    private var readingCanvas: some View {
        NavigationStack {
            ZStack {
                paper.background.ignoresSafeArea()
                publicationLayer
                readerOverlays
            }
            .toolbar(.hidden, for: .navigationBar)
            .foregroundStyle(paper.text)
            .tint(SwiftUI.Color(hex: accentHex))
        }
        .preferredColorScheme(theme == "system" ? nil : (paper.dark ? .dark : .light))
        .statusBarHidden(session != nil && !chrome.visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: chrome.visible)
        .accessibilityAction(.escape) { persist(); dismiss() }
    }
    private var presentations: some View {
        readingCanvas
            .sheet(isPresented: $showBookmarks) { bookmarksSheet }
            .readerHint(isPresented: $showReaderTip, title: "Только вы и книга", message: "Коснитесь середины страницы, чтобы показать или скрыть панель. Нажимайте по краям для перелистывания. Долгое нажатие выделяет текст.", icon: "book")
            .sheet(isPresented: $appearanceOpen) {
                ReaderAppearanceSheet().presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
    }
    private var readingLifecycle: some View {
        presentations
            .task {
                await load()
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 20_000_000_000) }
                    catch { break }
                    persist()
                }
            }
            .task(id: readerOptions) { [options = readerOptions] in session?.apply(options) }
            .onDisappear { persist(); session?.cancelUpdates() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
            .onChange(of: chrome.visible) { _, visible in
                if visible && !hintReaderShown { hintReaderShown = true; showReaderTip = true }
                if !visible { showReaderTip = false }
            }
    }
    private var syncedPreferences: [String: String] {
        ["readerPersistentProgress": String(persistentProgress),
         "readerPageAnimation": String(pageAnimation),
         "readerProgressDisplay": progressDisplay,
         "readerFontSize": String(fontSize),
         "readerFont": font,
         "readerTheme": theme,
         "readerScroll": String(scroll)]
    }
    private var preferenceObservers: some View {
        readingLifecycle.onChange(of: syncedPreferences) { previous, current in
            syncPreferences(previous: previous, current: current)
        }
    }
    private func syncPreferences(previous: [String: String], current: [String: String]) {
        for (key, value) in current where previous[key] != value {
            sync.settingsChanged(key: key, value: value)
        }
    }

    private var readerControls:some View {
        VStack {
            HStack(spacing:8) {
                readerButton("chevron.down",label:"Закрыть книгу") {persist();dismiss()}
                Text(verbatim:book?.title ?? L10n.text("Читалка")).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .frame(maxWidth:.infinity,alignment:.leading)
                readerButton("bookmark",label:"Мои закладки") {showBookmarks=true}
                readerButton("textformat.size",label:"Оформление чтения") {appearanceOpen=true}
            }.padding(8).background(paper.background.opacity(0.97),in:RoundedRectangle(cornerRadius:16))
                .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(paper.text.opacity(0.12),lineWidth:0.8))
                .padding(.horizontal,12).padding(.top,8)
            Spacer()
        }
    }
    private func readerButton(_ icon:String,label:String,action:@escaping()->Void)->some View {
        Button(action:action) {Image(systemName:icon).font(.title3).foregroundStyle(SwiftUI.Color(hex:accentHex)).frame(width:44,height:44)}
            .buttonStyle(.plain).accessibilityLabel(Text(verbatim:L10n.text(label)))
    }

    private func load() async {
        guard session == nil, let book else { return }
        do {
            let book = await store.prepareForReading(book, explicitLocation: initialLocation)
            try Task.checkCancellation()
            session = try await ReaderSession.open(
                fileURL: store.fileURL(for: book), previousLocation: initialLocation ?? book.locatorJSON,
                options: readerOptions
            )
            let chrome=chrome
            session?.onToggleChrome={ [weak chrome] in chrome?.visible.toggle() }
            session?.onPageTurn={ [weak chrome] in chrome?.visible=false }
            if UIAccessibility.isVoiceOverRunning {chrome.visible=true}
            let id=bookID
            let store=store
            session?.onLocationChange={ [weak store] locator in
                guard let json=try? locator.jsonString() else{return}
                store?.savePosition(bookID:id,locatorJSON:json)
            }
            apply()
        } catch { self.error = L10n.errorDescription(error) }
    }

    private func apply() {
        session?.apply(readerOptions)
    }

    private func addBookmark() {
        guard let locator = session?.navigator.currentLocation,
              let raw = try? locator.jsonString(),let bytes=raw.data(using:.utf8),
              var json=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] else { return }
        json["title"]=bookmarkName.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let data=try? JSONSerialization.data(withJSONObject:json) else{return}
        store.saveBookmark(bookID: bookID, locatorJSON: String(decoding:data,as:UTF8.self))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var bookmarksSheet:some View {
        NavigationStack {
            List {
                if let marks=book?.bookmarks,!marks.isEmpty {
                    ForEach(marks.indices,id:\.self) {index in
                        Button {
                            showBookmarks=false
                            Task {await openBookmark(marks[index])}
                        } label: {
                            Label(markTitle(marks[index],index:index),systemImage:"bookmark.fill").foregroundStyle(.primary)
                        }.swipeActions {
                            Button("Удалить",role:.destructive) {store.deleteBookmark(bookID:bookID,index:index)}
                            Button("Переименовать") {editingBookmark=index;bookmarkName=markTitle(marks[index],index:index);namingBookmark=true}.tint(SwiftUI.Color(hex:accentHex))
                        }
                    }
                } else {
                    Text(verbatim:L10n.render("Добавьте закладку, чтобы вернуться к этому месту в книге.",language:localizationLanguage)).foregroundStyle(.secondary)
                }
            }.readerNavigationTitle("Закладки").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {Button("Готово") {showBookmarks=false}}
                    ToolbarItem(placement:.topBarTrailing) {
                        Button("Добавить",systemImage:"plus") {
                            editingBookmark=nil;bookmarkName="Закладка \((book?.bookmarks?.count ?? 0)+1)";namingBookmark=true
                        }
                    }
                }
                .alert("Название закладки",isPresented:$namingBookmark) {
                    TextField("Например, любимая цитата",text:$bookmarkName)
                    Button("Сохранить") {
                        if bookmarkName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {bookmarkName="Закладка"}
                        if let index=editingBookmark {store.renameBookmark(bookID:bookID,index:index,name:bookmarkName)} else {addBookmark()}
                    }
                    Button("Отмена",role:.cancel) {}
                }
        }.tint(SwiftUI.Color(hex:accentHex)).preferredColorScheme(.dark)
    }
    private func markTitle(_ raw:String,index:Int)->String {
        guard let data=raw.data(using:.utf8),let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              let title=json["title"] as? String,!title.isEmpty else{return "Закладка \(index+1)"}
        return title
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
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerTheme") private var theme = "system"
    @AppStorage("readerFont") private var font = "serif"
    @AppStorage("readerFontSize") private var fontSize = 1.1
    @AppStorage("readerScroll") private var scroll = false
    @AppStorage("readerPageAnimation") private var pageAnimation=true
    @AppStorage("readerProgressDisplay") private var progressDisplay = "percent"
    @AppStorage("readerPersistentProgress") private var persistentProgress = false
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    private let options: [(String, String, SwiftUI.Color, SwiftUI.Color)] = [
        ("light", "Светлая", ReaderPaper(theme:"light").background, .black),
        ("sepia", "Сепия", ReaderPaper(theme:"sepia").background, .black),
        ("dark", "Тёмная", ReaderPaper(theme:"dark").background, .white),
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
                                                        ? SwiftUI.Color(hex: accentHex) : .white.opacity(0.15),
                                                        lineWidth: theme == item.0 ? 2 : 1)
                                            )
                                        Text(verbatim:L10n.text(item.1))
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
                            Text(verbatim:L10n.render("Шрифт",language:localizationLanguage))
                            Spacer()
                            Picker("Шрифт", selection: $font) {
                                Text(verbatim:L10n.render("С засечками",language:localizationLanguage)).tag("serif")
                                Text(verbatim:L10n.render("Без засечек",language:localizationLanguage)).tag("sans")
                            }.tint(.white)
                        }
                        ReaderDivider()
                        HStack {
                            Text(verbatim:L10n.render("Размер текста",language:localizationLanguage))
                            Spacer()
                            Text("\(Int(fontSize * 100))%")
                                .foregroundStyle(ReaderStyle.secondary)
                        }
                        Slider(value: $fontSize, in: 0.7...3.0, step: 0.1)
                            .tint(SwiftUI.Color(hex: accentHex))
                        ReaderDivider()
                        Toggle("Всегда показывать прогресс",isOn:$persistentProgress).padding(.vertical,10)
                        Toggle("Анимация перелистывания",isOn:$pageAnimation).padding(.vertical,10).disabled(scroll)
                        Text(verbatim:L10n.text("Плавное перелистывание по нажатию. В режиме прокрутки и при уменьшении движения анимация не используется.")).font(.caption).foregroundStyle(ReaderStyle.secondary)
                        ReaderDivider()
                        Toggle("Вертикальная прокрутка", isOn: $scroll)
                            .padding(.vertical, 10)
                        ReaderDivider()
                        VStack(alignment:.leading,spacing:10) {
                            Text(verbatim:L10n.render("Прогресс чтения",language:localizationLanguage)).font(.system(size:14,weight:.semibold))
                            ReaderSegmentedControl(items:[("percent","Процент прочтения"),("pages","Текущая страница")],selection:$progressDisplay)
                            Text(verbatim:L10n.render("Выберите, что показывать внизу книги.",language:localizationLanguage)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                        }.padding(.vertical,12)
                    }
                }
                .padding(20)
            }
            .readerCanvas()
            .readerNavigationTitle("Оформление чтения")
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

private struct ReadingProgressFooter:View {
    @ObservedObject var session:ReaderSession
    let format:String
    let theme:String
    @AppStorage("appLanguage") private var language="ru"
    private var dark:Bool {ReaderPaper(theme:theme).dark}
    private var paper:SwiftUI.Color {ReaderPaper(theme:theme).background}
    var body:some View {
        Text(verbatim:ReadingProgressDisplay.stored(format).text(fraction:session.fraction,position:session.location?.locations.position,
                                                      total:session.totalPositions,language:language))
            .font(.system(size:12,weight:.regular)).italic()
            .foregroundStyle((dark ? SwiftUI.Color.white:SwiftUI.Color.black).opacity(0.42))
            .frame(maxWidth:.infinity).frame(height:27).padding(.bottom,2)
            .background(paper).accessibilityIdentifier("reader-progress")
    }
}
