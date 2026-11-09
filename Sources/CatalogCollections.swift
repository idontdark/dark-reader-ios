import SwiftUI

struct DiscoveryCollectionScreen:View {
    let title:String
    let genres:[String]
    var sort:String="readinglog"
    var personalized=false
    @EnvironmentObject private var library:BookshelfStore
    @AppStorage("appLanguage") private var language="ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage="auto"
    private var contentLanguage:String {bookLanguage == "auto" ? language:bookLanguage}
    @State private var books:[DiscoveryBook]=[]
    @State private var loading=true
    @State private var message:String?
    @State private var failed=false
    @State private var requestID=UUID()
    @State private var selected:DiscoveryBook?
    var body:some View {
        ScrollView {
            LazyVStack(spacing:12) {
                if loading && books.isEmpty {CatalogSkeletons()}
                if loading && !books.isEmpty {ProgressView().accessibilityLabel(Text(verbatim:L10n.render("Обновляем подборку",language:language)))}
                if let message {
                    ReaderCard {
                        Text(verbatim:L10n.render(message)).font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                        if failed {Button("Повторить") {Task {await load()}}.padding(.top,12)}
                    }
                }
                ForEach(books) {book in
                    Button {selected=book} label:{CatalogResultRow(title:book.title,author:book.author,coverURL:book.coverURL)}.buttonStyle(.plain)
                }
            }.padding(ReaderMetrics.screenInset)
        }.readerCanvas().readerNavigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .task(id:contentLanguage+sort+String(personalized)+genres.joined(separator:",")) {await load()}
            .refreshable {await load()}
            .fullScreenCover(item:$selected) {DiscoveryBookDetail(book:$0)}
    }
    private func load() async {
        let token=UUID();requestID=token;loading=true;message=nil;failed=false
        defer {if requestID == token {loading=false}}
        do {
            let found=try await DiscoveryService.books(genres:genres,language:contentLanguage,limit:24,sort:sort)
            try Task.checkCancellation()
            guard requestID == token else{return}
            books=personalized ? RecommendationProfile.rank(found,excluding:library.books.map(\.title)):found
            if books.isEmpty {message="На выбранном языке пока нет подходящих книг."}
        } catch is CancellationError {} catch {
            guard !Task.isCancelled,requestID == token else{return}
            failed=true;message="Не удалось загрузить подборку. Проверьте подключение и повторите попытку."
        }
    }
}
struct AudioCollectionScreen:View {
    let title:String
    var newest=false
    var genres:[String]=[]
    var personalized=false
    @EnvironmentObject private var player:AudioPlayerModel
    @AppStorage("appLanguage") private var language="ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage="auto"
    private var contentLanguage:String {bookLanguage == "auto" ? language:bookLanguage}
    @AppStorage("preferredAudioSource") private var source:AudioSource = .archive
    @AppStorage("disabledAudioSources") private var disabled=""
    @State private var books:[AudioBook]=[]
    @State private var loading=true
    @State private var message:String?
    @State private var failed=false
    @State private var requestID=UUID()
    @State private var selected:AudioBook?
    var body:some View {
        ScrollView {
            LazyVStack(spacing:12) {
                if loading && books.isEmpty {CatalogSkeletons()}
                if loading && !books.isEmpty {ProgressView().accessibilityLabel(Text(verbatim:L10n.render("Обновляем подборку",language:language)))}
                if let message {
                    ReaderCard {
                        Text(verbatim:L10n.render(message)).font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                        if failed {Button("Повторить") {Task {await load()}}.padding(.top,12)}
                    }
                }
                ForEach(books) {book in
                    Button {selected=book} label:{CatalogResultRow(title:book.title,author:book.author,coverURL:book.coverURL)}.buttonStyle(.plain)
                }
            }.padding(ReaderMetrics.screenInset)
        }.readerCanvas().readerNavigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .task(id:contentLanguage+source.rawValue+disabled+String(personalized)+genres.joined(separator:",")) {await load()}
            .refreshable {await load()}
            .fullScreenCover(item:$selected) {AudioBookDetailScreen(book:$0){}.environmentObject(player)}
    }
    private func load() async {
        let token=UUID();requestID=token;loading=true;message=nil;failed=false
        defer {if requestID == token {loading=false}}
        do {
            let found=try await UnifiedDiscoveryService.audio(genres:genres,language:contentLanguage,
                shelf:newest ? .recent : personalized ? .personalized : genres.isEmpty ? .popular : .genre)
            try Task.checkCancellation()
            guard requestID == token else{return}
            books=found
            if books.isEmpty {message="На выбранном языке пока нет подходящих записей."}
        } catch is CancellationError {} catch {
            guard !Task.isCancelled,requestID == token else{return}
            failed=true;message="Не удалось загрузить аудиокниги. Проверьте подключение и повторите попытку."
        }
    }
}

struct CatalogGenresScreen:View {
    let audio:Bool
    @AppStorage("appLanguage") private var language="ru"
    var body:some View {
        ScrollView {
            ReaderInsetGroup {
                ForEach(ReaderPreferences.genres,id:\.id) {genre in
                    NavigationLink {
                        if audio {AudioCollectionScreen(title:ReaderPreferences.genreName(genre.id,language:language),genres:[genre.id])}
                        else {DiscoveryCollectionScreen(title:ReaderPreferences.genreName(genre.id,language:language),genres:[genre.id])}
                    } label:{
                        ReaderRow(icon:genre.icon,title:ReaderPreferences.genreName(genre.id,language:language),subtitle:nil) {
                            Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                        }
                    }.buttonStyle(.plain)
                    if genre.id != ReaderPreferences.genres.last?.id {ReaderDivider()}
                }
            }.padding(18)
        }.readerCanvas().readerNavigationTitle("Жанры").navigationBarTitleDisplayMode(.inline)
    }
}
struct CatalogAuthorsScreen:View {
    let audio:Bool
    @EnvironmentObject private var navigation:ReaderNavigation
    @AppStorage("appLanguage") private var language="ru"
    @AppStorage("preferredAuthorsJSON") private var raw="[]"
    private var authors:[String] {
        var seen=Set<String>()
        return (ReaderPreferences.array(raw)+(language == "en" ? ReaderPreferences.suggestedAuthorsEN:ReaderPreferences.suggestedAuthorsRU))
            .filter {seen.insert($0).inserted}
    }
    var body:some View {
        ScrollView {
            VStack(spacing:15) {
                ReaderInsetGroup {
                    ForEach(authors,id:\.self) {author in
                        Button {
                            navigation.authorToSearch=author
                            navigation.searchScope=audio ? "audio":"books"
                            navigation.tab = .search
                        } label:{
                            ReaderRow(icon:"person",title:author,subtitle:nil) {
                                Image(systemName:"magnifyingglass").font(.system(size:13)).foregroundStyle(ReaderStyle.secondary)
                            }
                        }.buttonStyle(.plain)
                        if author != authors.last {ReaderDivider()}
                    }
                }
                NavigationLink("Любимые авторы") {FavoriteAuthorsScreen()}.font(.system(size:13))
            }.padding(18)
        }.readerCanvas().readerNavigationTitle("Авторы").navigationBarTitleDisplayMode(.inline)
    }
}
struct CatalogSeriesScreen:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let audio:Bool
    @EnvironmentObject private var navigation:ReaderNavigation
    @AppStorage("catalogProvider") private var provider="flibusta"
    @State private var target:URL?
    @State private var loading=true
    @State private var message:String?
    var body:some View {
        Group {
            if let target {OPDSBrowseScreen(title:"Серии",url:target)}
            else {
                ScrollView {
                    ReaderCard {
                        if loading {ProgressView().padding(.vertical,15)}
                        else {
                            Text(verbatim:L10n.render(message ?? "Этот источник пока не передаёт список серий.",language:localizationLanguage)).font(.system(size:14)).foregroundStyle(ReaderStyle.secondary)
                            Button("Найти книгу по названию") {
                                navigation.searchScope=audio ? "audio":"books";navigation.tab = .search
                            }.font(.system(size:13,weight:.medium)).padding(.top,12)
                        }
                    }.padding(18)
                }.readerCanvas()
            }
        }.readerNavigationTitle("Серии").navigationBarTitleDisplayMode(.inline)
            .task {
                defer {loading=false}
                guard !audio else {message="Раздел серий пока недоступен. Если он будет востребован, я добавлю его, когда найду подходящий сервис. Пока книги серии можно искать по названию.";return}
                let saved=OPDSSources.decode(UserDefaults.standard.string(forKey:"savedOPDSCatalogs") ?? "[]")
                let address=provider == "flibusta" ? "https://flibusta.is/opds":saved.first(where:{"opds:"+$0.id.uuidString == provider})?.url
                guard let address,let root=URL(string:address) else {message="Для просмотра серий выберите OPDS-каталог, который их поддерживает.";return}
                do {
                    let entries=try await CatalogProviders.browse(url:root)
                    target=entries.first {($0.title.localizedCaseInsensitiveContains("серии") || $0.title.localizedCaseInsensitiveContains("series")) && $0.navigationURL != nil}?.navigationURL
                    if target == nil {message="В этом каталоге не найден раздел серий."}
                } catch {message="Не удалось открыть список серий. Проверьте подключение."}
            }
    }
}
struct OPDSBrowseScreen:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let title:String
    let url:URL
    @State private var entries:[CatalogBook]=[]
    @State private var message:String?
    @State private var selected:CatalogBook?
    var body:some View {
        ScrollView {
            VStack(spacing:10) {
                if let message {Text(verbatim:L10n.render(message,language:localizationLanguage)).font(.system(size:13)).foregroundStyle(ReaderStyle.secondary)}
                ForEach(entries) {book in
                    if let navigation=book.navigationURL,book.epubURL == nil {
                        NavigationLink {OPDSBrowseScreen(title:book.title,url:navigation)} label:{
                            ReaderCard {ReaderRow(icon:"books.vertical",title:book.title,subtitle:nil) {
                                Image(systemName:"chevron.right").font(.system(size:11))
                            }}
                        }.buttonStyle(.plain)
                    } else {
                        Button {selected=book} label:{
                            ReaderCard {ReaderRow(icon:"book",title:book.title,subtitle:book.author) {
                                Image(systemName:"chevron.right").font(.system(size:11))
                            }}
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(18)
        }.readerCanvas().readerNavigationTitle(title,localized:false).navigationBarTitleDisplayMode(.inline)
            .task {do {entries=try await CatalogProviders.browse(url:url)} catch {message="Не удалось открыть каталог."}}
            .fullScreenCover(item:$selected) {book in CatalogBookDetailSheet(book:book){selected=nil}}
    }
}
