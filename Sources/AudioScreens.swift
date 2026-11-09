import SwiftUI

struct AudioCatalogScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    var showsHeader = true
    @EnvironmentObject private var player: AudioPlayerModel
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("appLanguage") private var language = "ru"
    @FocusState private var queryFocused: Bool
    private var query: String {
        get { navigation.searchQuery }
        nonmutating set { navigation.searchQuery = newValue }
    }
    @State private var searchMode = "title"
    private var byAuthor: Bool {
        get { searchMode == "author" }
        nonmutating set { searchMode = newValue ? "author" : "title" }
    }
    @State private var books: [AudioBook] = []
    @State private var searching = false
    @State private var didSearch = false
    @State private var showVPNHint = false
    @State private var message: String?
    @State private var searchID = UUID()
    @State private var searchTask: Task<Void, Never>?
    @State private var hintTask: Task<Void, Never>?
    @State private var selected: AudioBook?
    @State private var showPlayer = false
    @State private var acceptedRevision = 0
    @State private var sourceFailures = 0
    @AppStorage(SourcePreferences.key) private var enabledSourceData = Data()
    @State private var showCatalogs=false
    @State private var webCatalog:AudioWebCatalog?
    private var color: Color { Color(hex: accentHex) }
    private var languageName:String {bookLanguage == "all" ? "Все":bookLanguage == "en" ? "English":"Русский"}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if showsHeader {
                        ReaderHeader(title: "Аудиокниги", trailingIcon: nil, trailingAction: nil)
                    }
                    VStack(alignment: .leading, spacing: ReaderMetrics.formSpacing) {
                        ReaderQueryField(query:$navigation.searchQuery, focus:$queryFocused, placeholder: searchMode == "narrator" ? "Имя исполнителя" : "Название или автор") {if !searching {startSearch()}}
                        ReaderSegmentedControl(items:[("title","По названию"),("author","По автору"),("narrator","По исполнителю")],selection:$searchMode)
                        ReaderSearchLanguage(selection:$bookLanguage)

                        PurpleAction(title: searching ? "Отменить поиск" : "Найти аудиокниги",
                                     icon: searching ? "xmark" : "magnifyingglass") {
                            if searching { cancelSearch() }
                            else { startSearch() }
                        }
                        .disabled(!searching && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(!searching && query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? 0.5:1)
                        if searching {
                            HStack(spacing: 9) {
                                ProgressView().tint(color)
                                Text(verbatim:L10n.render("Ищем записи…",language:localizationLanguage))
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                            .font(.subheadline)
                            if showVPNHint {
                                Text(verbatim:L10n.render("Поиск затянулся. Если каталог не открывается, попробуйте VPN.",language:localizationLanguage))
                                    .font(.footnote)
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                    }
                    if let message {
                        ReaderCard {
                            Label(L10n.render(message, language:localizationLanguage), systemImage: "wifi.exclamationmark")
                                .font(.subheadline)
                                .foregroundStyle(ReaderStyle.secondary)
                        }
                    }
                    HStack {
                        SectionLabel(text:"Результаты")
                        if sourceFailures > 0 {Text(verbatim:L10n.text("Часть источников не ответила. Результаты остальных уже доступны.")).font(.caption).foregroundStyle(ReaderStyle.secondary)}
                        if books.count>=100 {Text(verbatim:L10n.text("Показаны первые 100 результатов. Уточните название или автора.")).font(.caption).foregroundStyle(ReaderStyle.secondary)}
                        Spacer()
                        if didSearch {
                            Text("\(books.count)")
                                .font(.caption).foregroundStyle(ReaderStyle.secondary)
                        }
                    }
                    if didSearch && books.isEmpty && !searching && message == nil {
                        ReaderCard {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(verbatim:L10n.render("Ничего не найдено",language:localizationLanguage))
                                    .font(.headline)
                                Text(verbatim:L10n.render("Попробуйте другое название или автора. Бесплатных записей некоторых книг пока нет.",language:localizationLanguage))
                                    .font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                    } else if !didSearch && books.isEmpty {
                        ReaderCard {
                            Label("Найдите аудиокнигу и выбирайте главы для прослушивания.",
                                  systemImage: "headphones")
                                .font(.subheadline)
                                .foregroundStyle(ReaderStyle.secondary)
                        }
                    }
                    VStack(spacing: 11) {
                        ForEach(books) { book in
                            Button {
                                selected = book
                            } label: {
                                ReaderCard {
                                    HStack(spacing: 13) {
                                        BookArtwork(title: book.title, author: book.author,
                                                    coverURL: book.coverURL, width: 66, height: 94)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(book.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                            Text(verbatim:L10n.authorName(book.author))
                                                .font(.footnote)
                                                .foregroundStyle(ReaderStyle.secondary)
                                                .lineLimit(2)
                                            Text(verbatim:L10n.render(book.sourceTitle,language:localizationLanguage))
                                                .font(.caption2)
                                                .foregroundStyle(color)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ReaderStyle.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if player.book != nil {
                        Button { showPlayer = true } label: {
                            Label("Продолжить прослушивание", systemImage: "play.circle.fill")
                                .foregroundStyle(color)
                                .font(.headline)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .readerCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item:$webCatalog) {AudioWebCatalogScreen(url:$0.url)}
            .fullScreenCover(item: $selected) { book in
                AudioBookDetailScreen(book: book) {}
                    .environmentObject(player)
            }
            .fullScreenCover(isPresented: $showPlayer) {
                AudioPlayerScreen()
                    .environmentObject(player)
            }
            .onChange(of:navigation.searchScope) { _, scope in
                queryFocused = false
                if scope == "audio" { handlePendingSearch() }
            }
            .onAppear {
                if bookLanguage == "auto" {bookLanguage=language}
                handlePendingSearch()
            }
            .onChange(of:navigation.bookToSearch) {_,_ in handlePendingSearch()}
            .onChange(of:navigation.authorToSearch) {_,_ in handlePendingSearch()}
            .onChange(of: enabledSourceData) { _, _ in
                cancelSearch()
                didSearch = false
                message = nil
                books = []
            }
            .task(id:books.prefix(8).map(\.id)) { await CoverCache.shared.prefetch(books.prefix(8).compactMap(\.coverURL)) }
            .onDisappear { if searching { cancelSearch() } }
        }
    }

    private func handlePendingSearch() {
        guard navigation.searchScope == "audio", navigation.tab == .search else { return }
        if let title=navigation.bookToSearch {
            navigation.bookToSearch=nil;query=title;byAuthor=false;startSearch()
        } else if let author=navigation.authorToSearch {
            navigation.authorToSearch=nil;query=author;byAuthor=true;startSearch()
        }
    }

    private func cancelSearch() {
        searchID = UUID()
        searchTask?.cancel()
        hintTask?.cancel()
        searchTask = nil
        hintTask = nil
        searching = false
        showVPNHint = false
    }

    private func startSearch() {
        queryFocused = false; cancelSearch()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        didSearch = true; books = []; message = nil; searching = true; acceptedRevision = 0; sourceFailures = 0
        let token = UUID(); searchID = token
        let term = query; let authorMode = byAuthor; let narratorMode = searchMode == "narrator"
        let selectedLanguage = ReaderPreferences.effectiveLanguage(bookLanguage, appLanguage: language)
        searchTask = Task {
            defer { if searchID == token { searching = false } }
            do {
                let final = try await UnifiedSearchService.audio(query: term, byAuthor: authorMode, language: selectedLanguage, byNarrator: narratorMode, onResults: { update in
                    await MainActor.run {
                        guard searchID == token, !Task.isCancelled, update.sequence > acceptedRevision else { return }
                        acceptedRevision = update.sequence; books = update.books; sourceFailures = update.failed.count
                    }
                })
                try Task.checkCancellation()
                guard searchID == token else { return }
                books = final
            } catch is CancellationError { }
            catch { if searchID == token { message = L10n.errorDescription(error) } }
        }
    }

}

struct AudioBookDetailScreen:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let book:AudioBook
    @State private var selectedEdition: AudioEdition?
    @State private var resolvedBook: AudioBook?
    @State private var webPage = false
    @State private var playable = false
    @State private var downloadable = false
    @State private var downloadArchive = false
    private var editionBook: AudioBook { (selectedEdition.map { book.selecting($0) } ?? book).withResolvedSource }
    private var displayed: AudioBook { resolvedBook ?? editionBook }
    let onPlay:()->Void
    @EnvironmentObject private var player:AudioPlayerModel
    @EnvironmentObject private var navigation:ReaderNavigation
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    @AppStorage("audio.historyJSON") private var historyJSON="[]"
    @AppStorage("audio.favoritesJSON") private var favoritesJSON="[]"
    @State private var chapters:[AudioChapter]=[]
    @State private var loading=true
    @State private var message:String?
    @State private var format="audio"
    @State private var showPlayer=false
    private var favorite:Bool {decode(favoritesJSON).contains {$0.id == displayed.id}}
    private var saved:Bool {decode(historyJSON).contains {$0.id == displayed.id}}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    BookDetailHero(title:displayed.title,author:displayed.author,coverURL:displayed.coverURL,
                                   tags:(displayed.genres ?? []).prefix(2).map {ReaderPreferences.genreName($0,language:UserDefaults.standard.string(forKey:"appLanguage") ?? "ru")})
                    ReaderSegmentedControl(items:[("books","Книга"),("audio","Аудиокнига")],selection:$format)
                    PublicationFacts(language: displayed.language, date: displayed.publicationDate, series: displayed.series, number: displayed.seriesNumber)
                    let description=BookDescription.clean(displayed.description)
                    if !description.isEmpty {
                        Text(description).font(.system(size:14)).lineSpacing(4).foregroundStyle(.white.opacity(0.88))
                    }
                    if loading {ProgressView().padding(.vertical,10).tint(Color(hex:accentHex))}
                    if let message {Text(verbatim:L10n.render(message,language:localizationLanguage)).font(.system(size:12)).foregroundStyle(ReaderStyle.secondary)}
                    if let narrator = displayed.narrator, !narrator.isEmpty {
                        Label(narrator, systemImage: "person.wave.2").font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                    }
                    if let duration = displayed.durationSeconds, duration > 0 {
                        Text(verbatim: String(format: L10n.text("%d ч %d мин"), Int(duration) / 3600, Int(duration) % 3600 / 60)).font(.caption).foregroundStyle(ReaderStyle.secondary)
                    }
                    if let editions = book.editions, editions.count > 1 {
                        Menu("Озвучка и источник") {
                            ForEach(editions) { edition in
                                let label = [edition.narrator?.isEmpty == false ? edition.narrator : nil,
                                             SourceCatalog.source(edition.providerID)?.name ?? edition.providerID,
                                             edition.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
                                Button(label) {
                                    selectedEdition = edition; resolvedBook = nil
                                }
                            }
                        }.frame(minHeight: 44)
                    }
                    if playable && !chapters.isEmpty && !loading {
                        PurpleAction(title:"Слушать аудиокнигу",icon:"play.fill") {
                            player.open(displayed,tracks:chapters,downloadsAllowed:downloadable);showPlayer=true;onPlay()
                        }
                        if downloadable {
                            AudioDownloadAction(book:displayed,chapters:chapters)
                        }
                    } else if !loading && displayed.pageURL != nil {
                        PurpleAction(title: "Слушать на сайте", icon: "safari") { downloadArchive = false; webPage = true }
                    }
                    if displayed.archiveURL != nil && !loading {
                        PurpleAction(title: "Скачать архив аудиокниги", icon: "arrow.down.to.line") { downloadArchive = true; webPage = true }
                    }
                    BookFavoriteButton(favorite:favorite) {
                        var values=decode(favoritesJSON)
                        if favorite {values.removeAll {$0.id == displayed.id}}
                        else {values.insert(displayed,at:0);RecommendationProfile.record(title:displayed.title,author:displayed.author,weight:4,genre:displayed.genres?.first,kind:.audio,series:displayed.series)}
                        favoritesJSON=encode(values)
                    }
                    if displayed.source == .local {
                        NavigationLink("Изменить книгу и порядок глав") {AudioEditScreen(book:book)}
                            .font(.system(size:12)).foregroundStyle(ReaderStyle.secondary)
                    }
                    if playable && !chapters.isEmpty {
                        VStack(alignment:.leading,spacing:5) {
                            Text(verbatim:L10n.render("Главы",language:localizationLanguage)).font(.system(size:15,weight:.semibold)).padding(.top,8).padding(.bottom,5)
                            ForEach(Array(chapters.enumerated()),id:\.element.id) {index,chapter in
                                Button {
                                    player.open(displayed,tracks:chapters,downloadsAllowed:downloadable);player.playChapter(index);showPlayer=true;onPlay()
                                } label:{
                                    HStack {
                                        Text("\(index+1)").font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).frame(width:20)
                                        Text(chapter.title).font(.system(size:13)).lineLimit(2).foregroundStyle(.white.opacity(0.87))
                                        Spacer()
                                        Image(systemName:"play").font(.system(size:12)).foregroundStyle(Color(hex:accentHex))
                                    }.frame(minHeight:40).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if index != chapters.count-1 {ReaderDivider()}
                            }
                        }
                    }
                }.padding(.horizontal,20).padding(.top,10).padding(.bottom,30)
            }.readerCanvas().readerNavigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button {dismiss()} label:{Image(systemName:"chevron.left").font(.system(size:18,weight:.medium))}
                            .accessibilityLabel(Text(verbatim:L10n.render("Назад",language:localizationLanguage)))
                    }
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        if let track=chapters.first,!track.url.isFileURL {
                            ShareLink(item:track.url) {Image(systemName:"square.and.arrow.up").font(.system(size:17))}
                        }
                        Button {
                            var values=decode(historyJSON)
                            if saved {values.removeAll {$0.id == displayed.id}} else {values.insert(displayed,at:0)}
                            historyJSON=encode(values)
                        } label:{Image(systemName:saved ? "bookmark.fill":"bookmark").font(.system(size:17))}
                            .accessibilityLabel(Text(verbatim:L10n.render(saved ? "Удалить из библиотеки":"Добавить в библиотеку",language:localizationLanguage)))
                    }
                }.tint(Color(hex:accentHex))
                .task(id: selectedEdition?.id ?? book.id) { await loadEdition() }
                .sheet(isPresented: $webPage) {
                    if let id = displayed.providerID, let source = SourceCatalog.source(id), let page = downloadArchive ? displayed.archiveURL : displayed.pageURL {
                        SourceWebScreen(source: source, url: page, title: displayed.title, author: displayed.author, language: displayed.language, narrator: displayed.narrator, series: displayed.series)
                    }
                }
                .onChange(of:format) {_,value in
                    if value == "books" {navigation.bookToSearch=displayed.title;navigation.searchScope="books";navigation.tab = .search;dismiss()}
                }
                .fullScreenCover(isPresented:$showPlayer) {AudioPlayerScreen().environmentObject(player)}
        }
    }
    private func loadEdition() async {
        loading = true; chapters = []; message = nil; playable = false; downloadable = false
        defer { if !Task.isCancelled { loading = false } }
        let current = editionBook
        do {
            if let id = current.providerID, let source = SourceCatalog.source(id) {
                resolvedBook = try? await AudioSourceFactory.adapter(source).detail(current)
            }
            let tracks = try await AudioCatalogService.chapters(for: resolvedBook ?? current)
            try Task.checkCancellation()
            guard let first = tracks.first else { return }
            var valid = first.url.isFileURL
            if !valid { valid = await SourceFileProbe.playable(first.url) }
            try Task.checkCancellation()
            if valid {
                chapters = tracks; playable = true
                let indices = Set([0, tracks.count / 2, tracks.count - 1])
                var direct = true
                for index in indices {
                    if !tracks[index].url.isFileURL, !(await SourceFileProbe.check(tracks[index].url, kind: .audioFile)) { direct = false }
                }
                try Task.checkCancellation(); downloadable = direct
            }
            else { message = current.source == .local ? "Файлы аудиокниги недоступны. Импортируйте её повторно." : "Встроенное воспроизведение недоступно. Можно открыть книгу на сайте." }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { message = current.source == .local ? "Файлы аудиокниги недоступны. Импортируйте её повторно." : "Встроенное воспроизведение недоступно. Можно открыть книгу на сайте." } }
    }
    private func decode(_ raw:String)->[AudioBook] {raw.data(using:.utf8).flatMap{try? JSONDecoder().decode([AudioBook].self,from:$0)} ?? []}
    private func encode(_ values:[AudioBook])->String {(try? JSONEncoder().encode(values)).map{String(decoding:$0,as:UTF8.self)} ?? "[]"}
}

struct AudioPlayerScreen:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @EnvironmentObject private var player:AudioPlayerModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    @State private var scrubbing=false
    @State private var scrubPosition=0.0
    private var color:Color {Color(hex:accentHex)}
    var body:some View {
        GeometryReader {geometry in
            let coverHeight=min(277,max(220,geometry.size.height*0.34))
            ScrollView {
                VStack(spacing:0) {
                    HStack {
                        Button {dismiss()} label:{Image(systemName:"chevron.down").font(.system(size:18,weight:.medium))}
                            .accessibilityLabel(Text(verbatim:L10n.render("Свернуть плеер",language:localizationLanguage)))
                        Spacer()
                        Menu {
                            if let book=player.book, player.canDownloadBook {
                                Button("Скачать аудиокнигу",systemImage:"arrow.down.to.line") {
                                    player.startDownload(book,tracks:player.chapters)
                                }.disabled(player.downloadingBookID == book.id)
                            }
                            if player.canDownloadBook {
                                Button("Сохранить текущую главу",systemImage:"arrow.down.to.line") {Task {await player.downloadCurrentChapter()}}
                                    .disabled(player.downloadingChapter != nil)
                            }
                            Button("Добавить закладку",systemImage:"bookmark") {player.addBookmark()}
                            if player.chapterIndex>0 {Button("Предыдущая глава") {player.previous()}}
                            if player.chapterIndex+1<player.chapters.count {Button("Следующая глава") {player.next()}}
                        } label:{Image(systemName:"ellipsis").font(.system(size:21,weight:.medium))}
                    }.foregroundStyle(Color(hex:"#C9BDD6")).frame(height:36)
                    Spacer(minLength:12).frame(maxHeight:30)
                    if let book=player.book {
                        ZStack {
                            AudioWaveBackdrop().frame(height:116).padding(.horizontal,-7)
                            BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:coverHeight*0.668,height:coverHeight)
                        }.frame(maxWidth:.infinity).frame(height:coverHeight+5)
                        Text(book.title).font(.system(size:21,weight:.semibold)).tracking(-0.3).lineLimit(2)
                            .multilineTextAlignment(.center).padding(.top,15)
                        Text(verbatim:L10n.authorName(book.author)).font(.system(size:13)).foregroundStyle(ReaderStyle.secondary)
                            .multilineTextAlignment(.center).lineLimit(2).padding(.top,6)
                    } else {
                        Image("HeroHeadphones").resizable().scaledToFit().frame(height:280)
                        Text(verbatim:L10n.render("Выберите аудиокнигу",language:localizationLanguage)).font(.system(size:20,weight:.semibold)).padding(.top,15)
                    }
                    Spacer(minLength:18).frame(maxHeight:34)
                    timeline
                    HStack(spacing:47) {
                        Button {player.skip(by:-15)} label:{Image(systemName:"gobackward.15").font(.system(size:27,weight:.regular))}
                            .disabled(!player.canSeek).accessibilityLabel(Text(verbatim:L10n.render("Назад на 15 секунд",language:localizationLanguage)))
                        Button {player.toggle()} label:{
                            Image(systemName:player.isPlaying ? "pause.fill":"play.fill").font(.system(size:30,weight:.semibold))
                                .offset(x:player.isPlaying ? 0:2).foregroundStyle(.white)
                                .frame(width:75,height:75).background(ReaderStyle.actionGradient(accentHex),in:Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.13),lineWidth:0.7))
                                .shadow(color:color.opacity(0.22),radius:15,y:4)
                        }.disabled(player.book == nil).accessibilityLabel(Text(verbatim:L10n.render(player.isPlaying ? "Пауза":"Воспроизвести",language:localizationLanguage)))
                        Button {player.skip(by:30)} label:{Image(systemName:"goforward.30").font(.system(size:27,weight:.regular))}
                            .disabled(!player.canSeek).accessibilityLabel(Text(verbatim:L10n.render("Вперёд на 30 секунд",language:localizationLanguage)))
                    }.foregroundStyle(Color(hex:"#E4DEEC")).buttonStyle(.plain).padding(.top,24)
                    Spacer(minLength:22).frame(maxHeight:44)
                    bottomControls
                    if let error=player.error {Text(verbatim:L10n.render(error,language:localizationLanguage)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).padding(.top,14)}
                    if let remaining=player.sleepTimerRemaining {
                        Text(verbatim:L10n.render("До остановки: \(Int(ceil(remaining/60))) мин",language:localizationLanguage)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).padding(.top,12)
                    }
                    Spacer(minLength:10)
                }.padding(.horizontal,24).padding(.top,2).padding(.bottom,14)
                    .frame(minHeight:geometry.size.height,alignment:.top).frame(maxWidth:.infinity)
            }.scrollIndicators(.hidden).readerCanvas()
        }.preferredColorScheme(.dark)
    }
    private var timeline:some View {
        VStack(spacing:0) {
            Slider(value:Binding(
                get:{scrubbing ? scrubPosition:max(player.seekLowerBound,min(player.position,max(player.seekUpperBound,player.seekLowerBound+1)))},
                set:{scrubPosition=$0}
            ),in:player.seekLowerBound...max(player.seekUpperBound,player.seekLowerBound+1),
                   onEditingChanged:{editing in scrubbing=editing;if !editing {player.seek(to:scrubPosition)}})
                .tint(color).disabled(!player.canSeek).accessibilityLabel(Text(verbatim:L10n.render("Позиция воспроизведения",language:localizationLanguage)))
            HStack {
                Text(timeText(scrubbing ? scrubPosition:player.position))
                Spacer()
                Text(timeText(player.duration))
            }.font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(ReaderStyle.secondary)
            if !player.canSeek,player.book != nil {
                Text(verbatim:L10n.render("Источник пока не предоставил диапазон перемотки.",language:localizationLanguage))
                    .font(.system(size:10)).foregroundStyle(ReaderStyle.secondary).padding(.top,7)
            }
        }
    }
    private var bottomControls:some View {
        HStack {
            Menu {
                ForEach([0.75,1.0,1.25,1.5,1.75,2.0],id:\.self) {value in
                    Button(rateText(Float(value))) {player.setRate(Float(value))}
                }
            } label:{
                Text(rateText(player.rate)).font(.system(size:12,weight:.semibold)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal,12).frame(height:31).background(Color.white.opacity(0.05),in:Capsule())
            }
            Spacer()
            Menu {
                Button("Добавить закладку",systemImage:"bookmark") {player.addBookmark()}
                ForEach(player.bookmarks) {bookmark in
                    Button(L10n.render("Закладка · \(timeText(bookmark.position))",language:localizationLanguage)) {player.openBookmark(bookmark)}
                }
                Divider()
                ForEach(Array(player.chapters.enumerated()),id:\.element.id) {index,chapter in
                    Button(chapter.title) {player.playChapter(index)}
                }
            } label:{Image(systemName:"list.bullet").font(.system(size:21,weight:.regular)).frame(width:42,height:34)}
                .accessibilityLabel(Text(verbatim:L10n.render("Главы и закладки",language:localizationLanguage)))
            Spacer()
            Menu {
                Button("Отключить таймер") {player.setSleepTimer(minutes:nil)}
                ForEach([5,10,15,30,60],id:\.self) {minutes in
                    Button(L10n.render("\(minutes) мин",language:localizationLanguage)) {player.setSleepTimer(minutes:minutes)}
                }
            } label:{
                Image(systemName:"timer").font(.system(size:23,weight:.light))
                    .foregroundStyle(player.sleepTimerRemaining == nil ? ReaderStyle.secondary:color).frame(width:42,height:34)
            }.accessibilityLabel(Text(verbatim:L10n.render("Таймер сна",language:localizationLanguage)))
        }.foregroundStyle(ReaderStyle.secondary)
    }
    private func rateText(_ rate:Float)->String {
        var result=String(format:"%.2f",rate)
        if result.hasSuffix("0") {result.removeLast()}
        return result+"×"
    }
    private func timeText(_ value:Double)->String {
        guard value.isFinite else{return "0:00"}
        let total=max(0,Int(value))
        return total>=3600 ? String(format:"%02d:%02d:%02d",total/3600,(total%3600)/60,total%60):
            String(format:"%d:%02d",total/60,total%60)
    }
}
