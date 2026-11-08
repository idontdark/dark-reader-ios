import SwiftUI
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator
import UIKit

@MainActor
final class ReaderSession: ObservableObject, EPUBNavigatorDelegate {
    let navigator: EPUBNavigatorViewController

    let totalPositions:Int
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
    private init(navigator:EPUBNavigatorViewController,totalPositions:Int) {
        self.navigator=navigator
        self.totalPositions=totalPositions
        self.location=navigator.currentLocation
        navigator.delegate=self
        let adapter=DirectionalNavigationAdapter(animatedTransition:true,onNavigation:{[weak self] in self?.onPageTurn?()})
        pageNavigation=adapter;adapter.bind(to:navigator)
        navigator.addObserver(.tap { [weak self] _ in
            self?.onToggleChrome?()
            return true
        })
    }
    func navigator(_ navigator:Navigator,locationDidChange locator:Locator) {
        location=locator
        onLocationChange?(locator)
    }
    func navigator(_ navigator:Navigator,presentError error:NavigatorError) {
        errorMessage="Это действие недоступно для данной книги."
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
        let navigator = try EPUBNavigatorViewController(publication: publication, initialLocation: locator, config:.init(contentInset:[.compact:(top:64,bottom:56),.regular:(top:64,bottom:56)]))
        let positions=(try? await publication.positions().get()) ?? []
        return ReaderSession(navigator:navigator,totalPositions:positions.count)
    }

    func applyPreferences(fontSize: Double, font: String, theme: String, scroll: Bool, animated:Bool=true) {
        var preferences = EPUBPreferences(
            fontFamily: font == "sans" ? .sansSerif : .serif,
            fontSize: fontSize,
            publisherStyles: false,
            scroll: scroll, animated:pageAnimation && !reduceMotion
        )
        switch theme {
        case "dark", "oled": preferences.theme = .dark
        case "sepia": preferences.theme = .sepia
        default: preferences.theme = .light
        }
        let palette=ReaderPaper(theme:theme)
        preferences.backgroundColor=ReadiumNavigator.Color(hex:palette.backgroundHex)
        preferences.textColor=ReadiumNavigator.Color(hex:palette.textHex)
        navigator.view.backgroundColor=UIColor(palette.background)
        pageNavigation?.animatedTransition=animated && !UIAccessibility.isReduceMotionEnabled
        navigator.submitPreferences(preferences)
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

    let bookID: UUID
    let initialLocation: String?
    init(bookID: UUID, initialLocation: String? = nil) {
        self.bookID = bookID
        self.initialLocation = initialLocation
    }
    @State private var session: ReaderSession?
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
    private var paper:ReaderPaper {ReaderPaper(theme:effectiveTheme)}
    var body: some View {
        NavigationStack {
            ZStack {
                paper.background.ignoresSafeArea()
                Group {
                if let session {
                    ReaderContainer(navigator: session.navigator).ignoresSafeArea()
                        .accessibilityAction(named:Text(verbatim:L10n.text("Показать панель чтения"))) {chrome.visible=true}
                } else if let error {
                    ContentUnavailableView(
                        "Не удалось открыть книгу",
                        systemImage: "exclamationmark.triangle",
                        description: Text(verbatim:L10n.render(error,language:localizationLanguage))
                    )
                } else {
                    ProgressView("Открываем книгу…")
                }
                }
                if let session {
                    VStack {Spacer();ReadingProgressFooter(session:session,format:progressDisplay,theme:effectiveTheme)}.allowsHitTesting(false)
                }
                if chrome.visible || session == nil {readerControls}
            }
            .toolbar(.hidden,for:.navigationBar)
            .foregroundStyle(paper.text)
            .tint(SwiftUI.Color(hex:accentHex))
        }
        .preferredColorScheme(theme == "system" ? nil:(paper.dark ? .dark:.light))
        .statusBarHidden(session != nil && !chrome.visible)
        .animation(reduceMotion ? nil:.easeInOut(duration:0.16),value:chrome.visible)
        .accessibilityAction(.escape) {persist();dismiss()}
        .sheet(isPresented:$showBookmarks) {bookmarksSheet}
        .readerHint(isPresented:$showReaderTip,title:"Только вы и книга",message:"Коснитесь середины страницы, чтобы показать или скрыть панель. Нажимайте по краям для перелистывания. Долгое нажатие выделяет текст.",icon:"book")
        .sheet(isPresented: $appearanceOpen) {
            ReaderAppearanceSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await load()
            if session != nil && !hintReaderShown {
                hintReaderShown = true
                showReaderTip = true
            }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 20_000_000_000) }
                catch { break }
                persist()
            }
        }
        .onDisappear { persist() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
        .onChange(of:pageAnimation) {_,value in apply();sync.settingsChanged(key:"readerPageAnimation",value:String(value))}
        .onChange(of:reduceMotion) {_,_ in apply()}
        .onChange(of: progressDisplay) { _,value in sync.settingsChanged(key:"readerProgressDisplay",value:value) }
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
            session = try await ReaderSession.open(
                fileURL: store.fileURL(for: book), previousLocation: initialLocation ?? book.locatorJSON
            )
            let chrome=chrome
            session?.onToggleChrome={ [weak chrome] in chrome?.visible.toggle() }
            session?.onPageTurn={ [weak chrome] in chrome?.visible=false }
            if UIAccessibility.isVoiceOverRunning {chrome.visible=true}
            let id=bookID
            let store=store
            session?.onLocationChange={ [weak store,weak chrome] locator in
                if !UIAccessibility.isVoiceOverRunning {chrome?.visible=false}
                guard let json=try? locator.jsonString() else{return}
                store?.savePosition(bookID:id,locatorJSON:json)
            }
            apply()
        } catch { self.error = L10n.errorDescription(error) }
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
