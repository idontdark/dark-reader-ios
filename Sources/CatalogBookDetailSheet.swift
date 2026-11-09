import SwiftUI

struct CatalogBookDetailSheet:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let book:CatalogBook
    @State private var resolvedBook: CatalogBook?
    @State private var webOffer: BookOffer?
    private var displayed: CatalogBook { resolvedBook ?? book }
    let onClose:()->Void
    @EnvironmentObject private var library:BookshelfStore
    @EnvironmentObject private var navigation:ReaderNavigation
    @AppStorage("catalog.wishlistJSON") private var wishlistJSON="[]"
    @AppStorage("catalog.favoritesJSON") private var favoritesJSON="[]"
    @AppStorage("appLanguage") private var language="ru"
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    @ObservedObject private var downloads=DownloadQueue.shared
    @State private var format="books"
    @State private var reading:LocalBook?
    @State private var loadedSummary: String?
    @State private var loadingSummary = false
    private var local:LocalBook? {library.books.first {$0.catalogID == displayed.id}}
    private var favorite:Bool {local?.isFavorite == true || CatalogBookmarks.decode(favoritesJSON).contains {$0.id == displayed.id}}
    private var wished:Bool {CatalogBookmarks.decode(wishlistJSON).contains {$0.id == displayed.id}}
    private var task:BookDownload? {downloads.items.first {$0.id == displayed.id}}
    private var busy:Bool {task.map {[.queued,.connecting,.downloading,.paused].contains($0.state)} ?? false}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    BookDetailHero(title:displayed.title,author:displayed.author,coverURL:displayed.coverURL,
                                   tags:(displayed.genres ?? []).prefix(2).map {ReaderPreferences.genreName($0,language:language)})
                    ReaderSegmentedControl(items:[("books","Книга"),("audio","Аудиокнига")],selection:$format)
                    PublicationFacts(language: displayed.language, date: displayed.publicationDate, series: displayed.series, number: displayed.seriesNumber)
                    let summary=BookDescription.clean(loadedSummary ?? displayed.summary ?? "")
                    if loadingSummary && summary.isEmpty { ProgressView().controlSize(.small) }
                    Text(verbatim:L10n.render(summary.isEmpty ? "Описание пока недоступно.":summary,language:localizationLanguage))
                        .font(.system(size:14)).lineSpacing(4)
                        .foregroundStyle(summary.isEmpty ? ReaderStyle.secondary:.white.opacity(0.88))
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .padding(.vertical,3)
                    if let task,busy {
                        HStack(spacing:9) {
                            ProgressView().tint(Color(hex:accentHex))
                            Text(verbatim:L10n.render(task.state.title,language:localizationLanguage)).font(.system(size:12)).foregroundStyle(ReaderStyle.secondary)
                            Spacer()

                        }
                    }
                    PurpleAction(title:actionTitle,icon:local == nil ? "arrow.down.to.line":"book") {
                        if let local {reading=local}
                        else if task?.state == .paused {downloads.retry(displayed.id)}
                        else if displayed.epubURL != nil {downloads.enqueue(displayed)}
                        else if let offer = displayed.offers?.first { webOffer = offer }
                        else {findBook()}
                    }.disabled(busy && task?.state != .paused)
                    if local != nil {
                        Label("Книга добавлена в библиотеку",systemImage:"checkmark.circle.fill")
                            .font(.system(size:12,weight:.medium)).foregroundStyle(.green)
                        Button("Открыть библиотеку") {navigation.libraryScope="books";navigation.tab = .library;onClose()}
                            .font(.system(size:13,weight:.semibold))
                    }
                    if let offers = displayed.offers, offers.count > 1 {
                        Menu("Источники и форматы") {
                            ForEach(offers) { offer in
                                Button(offer.sourceName + " · " + (offer.format?.uppercased() ?? L10n.text("На сайте"))) { select(offer) }
                            }
                        }.frame(minHeight: 44)
                    }
                    BookFavoriteButton(favorite:favorite) {
                        let newValue = !favorite
                        CatalogBookmarks.set(displayed,key:CatalogBookmarks.favoritesKey,enabled:newValue)
                        if let local, (local.isFavorite ?? false) != newValue {library.toggleFavorite(local)}
                    }
                    if task?.state == .failed {
                        Text(verbatim:L10n.render("Не удалось скачать книгу. Проверьте подключение и повторите попытку.",language:localizationLanguage))
                            .font(.system(size:12)).foregroundStyle(ReaderStyle.secondary)
                    }
                }.padding(.horizontal,20).padding(.top,10).padding(.bottom,30)
            }.readerCanvas().readerNavigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button(action:onClose) {Image(systemName:"chevron.left").font(.system(size:18,weight:.medium))}
                            .accessibilityLabel(Text(verbatim:L10n.render("Назад",language:localizationLanguage)))
                    }
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        if let url=displayed.epubURL ?? displayed.navigationURL {
                            ShareLink(item:url) {Image(systemName:"square.and.arrow.up").font(.system(size:17))}
                        }
                        Button {CatalogBookmarks.toggle(displayed,key:CatalogBookmarks.wishlistKey)} label:{
                            Image(systemName:wished ? "bookmark.fill":"bookmark").font(.system(size:17))
                        }.accessibilityLabel(Text(verbatim:L10n.render(wished ? "Убрать из списка чтения":"Хочу прочитать",language:localizationLanguage)))
                    }
                }.tint(Color(hex:accentHex))
                .task(id:book.id) {
                    loadingSummary=true
                    resolvedBook = try? await UnifiedSearchService.detail(displayed)
                    if let summary = displayed.summary { loadedSummary = summary }
                    else { loadedSummary = await BookDescription.catalog(displayed,language:language) }
                    loadingSummary=false
                }
                .onChange(of:format) {_,value in
                    if value == "audio" {
                        navigation.bookToSearch=displayed.title;navigation.searchScope="audio";navigation.tab = .search
                        onClose()
                    }
                }
                .sheet(item: $webOffer) { offer in
                    if let source = SourceCatalog.source(offer.sourceID) {
                        SourceWebScreen(source: source, url: offer.pageURL, title: displayed.title, author: displayed.author)
                    }
                }
                .fullScreenCover(item:$reading) {ReaderScreen(bookID:$0.id)}
        }
    }
    private var actionTitle:String {
        if local != nil{return "Читать книгу"}
        if task?.state == .paused {return "Продолжить загрузку"}
        if busy{return task?.state.title ?? "В очереди"}
        if displayed.epubURL == nil{return displayed.offers?.isEmpty == false ? "Открыть на сайте" : "Найти книгу в каталоге"}
        return "Скачать книгу"
    }
    private func select(_ offer: BookOffer) {
        guard let file = offer.fileURL else { webOffer = offer; return }
        var choice = displayed; choice.epubURL = file; choice.downloadFormat = offer.format
        resolvedBook = choice; downloads.enqueue(choice)
    }
    private func findBook() {
        navigation.bookToSearch=displayed.title;navigation.searchScope="books";navigation.tab = .search;onClose()
    }
}
