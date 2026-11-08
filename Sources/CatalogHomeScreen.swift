import SwiftUI

struct CatalogHomeScreen:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @EnvironmentObject private var navigation:ReaderNavigation
    @EnvironmentObject private var player:AudioPlayerModel
    @EnvironmentObject private var library:BookshelfStore
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    @AppStorage("preferredGenresJSON") private var genresJSON="[]"
    @AppStorage("favoriteBooksJSON") private var favoritesJSON="[]"
    @AppStorage("appLanguage") private var language="ru"
    @AppStorage("catalogProvider") private var provider="flibusta"
    @AppStorage("preferredAudioSource") private var audioSource:AudioSource = .archive
    @AppStorage("disabledAudioSources") private var disabledSources=""
    @State private var recommendations:[DiscoveryBook]=[]
    @State private var audioBooks:[AudioBook]=[]
    @State private var loading=false
    @State private var notice:String?
    @State private var selectedBook:DiscoveryBook?
    @State private var selectedAudio:AudioBook?
    @State private var showPlayer=false
    @State private var showSources=false
    @State private var showImport=false
    private var selection:String {navigation.catalogScope}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:13) {
                    ReaderHeader(title:"Каталог",trailingIcon:"magnifyingglass") {
                        navigation.searchScope=selection;navigation.tab = .search
                    }
                    ReaderSegmentedControl(items:[("books","Книги"),("audio","Аудиокниги")],selection:$navigation.catalogScope)
                    CatalogPromoCarousel(audio:selection == "audio",onSearch:{
                        navigation.searchScope=selection;navigation.tab = .search
                    },onLibrary:{
                        navigation.libraryScope=selection;navigation.tab = .library
                    },onImport:{showImport=true})
                    sourceChips
                    categoryRows
                    recommendationsSection.padding(.top,7)
                }.padding(.horizontal,18).padding(.bottom,26)
            }.readerCanvas().toolbar(.hidden,for:.navigationBar)
                .task(id:selection+language+genresJSON+favoritesJSON) {await refresh()}
                .navigationDestination(isPresented:$showSources) {AudioSourcesScreen()}
                .sheet(isPresented:$showImport) {
                    if selection == "audio" {AudioImportScreen()}
                    else {ImportScreen().environmentObject(library).environmentObject(navigation)}
                }
                .fullScreenCover(item:$selectedBook) {book in DiscoveryBookDetail(book:book).environmentObject(navigation)}
                .fullScreenCover(item:$selectedAudio) {book in
                    AudioBookDetailScreen(book:book) {}.environmentObject(player)
                }
                .fullScreenCover(isPresented:$showPlayer) {AudioPlayerScreen().environmentObject(player)}
        }
    }
    private var sourceChips:some View {
        HStack(spacing:8) {
            if selection == "books" {
                sourceButton("Флибуста",icon:"books.vertical") {openBooks("flibusta")}
                sourceButton("Project Gutenberg",icon:"book.closed") {openBooks("gutendex")}
            } else {
                sourceButton("LibriVox",icon:"headphones") {openAudio(.librivox)}
                sourceButton("Internet Archive",icon:"waveform") {openAudio(.archive)}
            }
        }
    }
    private func sourceButton(_ title:String,icon:String,action:@escaping()->Void)->some View {
        Button(action:action) {
            HStack(spacing:7) {
                Image(systemName:icon).font(.system(size:17)).foregroundStyle(Color(hex:accentHex))
                Text(title).font(.system(size:12,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength:0)
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(ReaderStyle.secondary)
            }.foregroundStyle(.white).padding(.horizontal,10).frame(maxWidth:.infinity).frame(height:40)
                .background(ReaderStyle.cardGradient,in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(ReaderStyle.line,lineWidth:0.7))
        }.buttonStyle(.plain)
    }
    private func openAudio(_ selected:AudioSource) {
        disabledSources=disabledSources.components(separatedBy:",").filter {$0 != selected.rawValue}.joined(separator:",")
        UserDefaults.standard.set("",forKey:"preferredAudioCatalogID")
        audioSource=selected;navigation.searchScope="audio";navigation.tab = .search
    }
    private var categoryRows:some View {
        ReaderInsetGroup {
            NavigationLink {
                if selection == "audio" {AudioCollectionScreen(title:"Популярные",newest:false)}
                else {DiscoveryCollectionScreen(title:"Популярные",genres:ReaderPreferences.array(genresJSON),sort:"readinglog")}
            } label:{catalogRow("Популярные",icon:"flame")}
            ReaderDivider()
            NavigationLink {
                if selection == "audio" {AudioCollectionScreen(title:"Новинки",newest:true)}
                else {DiscoveryCollectionScreen(title:"Новинки",genres:ReaderPreferences.array(genresJSON),sort:"new")}
            } label:{catalogRow("Новинки",icon:"sparkles.rectangle.stack")}
            ReaderDivider()
            NavigationLink {CatalogGenresScreen(audio:selection == "audio")} label:{catalogRow("Жанры",icon:"square.grid.2x2")}
            ReaderDivider()
            NavigationLink {CatalogAuthorsScreen(audio:selection == "audio")} label:{catalogRow("Авторы",icon:"person")}
            ReaderDivider()
            NavigationLink {CatalogSeriesScreen(audio:selection == "audio")} label:{catalogRow("Серии",icon:"text.book.closed")}
        }.buttonStyle(.plain)
    }
    private func catalogRow(_ title:String,icon:String)->some View {
        HStack(spacing:11) {
            Image(systemName:icon).font(.system(size:17,weight:.regular)).frame(width:22)
            Text(verbatim:L10n.render(title,language:localizationLanguage)).font(.system(size:14,weight:.medium))
            Spacer()
            Image(systemName:"chevron.right").font(.system(size:11,weight:.medium)).foregroundStyle(ReaderStyle.secondary)
        }.foregroundStyle(.white.opacity(0.91)).frame(minHeight:43).contentShape(Rectangle())
    }
    @ViewBuilder private var recommendationsSection:some View {
        VStack(alignment:.leading,spacing:11) {
            HStack {
                Text(verbatim:L10n.render("Для вас",language:localizationLanguage)).font(.system(size:16,weight:.semibold))
                Spacer()
                NavigationLink {GenreSettingsScreen()} label:{
                    Text(verbatim:L10n.render("Мои интересы",language:localizationLanguage)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                }
            }
            if loading && recommendations.isEmpty && audioBooks.isEmpty {
                ProgressView().tint(Color(hex:accentHex)).padding(.vertical,15)
            } else if selection == "books" && !recommendations.isEmpty {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(alignment:.top,spacing:12) {
                        ForEach(recommendations) {book in
                            Button {selectedBook=book} label:{
                                VStack(alignment:.leading,spacing:6) {
                                    DiscoveryArtwork(book:book,width:94,height:136)
                                    Text(book.title).font(.system(size:11,weight:.medium)).lineLimit(2)
                                    Text(book.author).font(.system(size:10)).foregroundStyle(ReaderStyle.secondary).lineLimit(1)
                                }.foregroundStyle(.white).frame(width:94,alignment:.leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            } else if selection == "audio" && !audioBooks.isEmpty {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(alignment:.top,spacing:12) {
                        ForEach(audioBooks.prefix(12)) {book in
                            Button {selectedAudio=book} label:{
                                VStack(alignment:.leading,spacing:6) {
                                    BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:94,height:136)
                                    Text(book.title).font(.system(size:11,weight:.medium)).lineLimit(2)
                                    Text(book.author).font(.system(size:10)).foregroundStyle(ReaderStyle.secondary).lineLimit(1)
                                }.foregroundStyle(.white).frame(width:94,alignment:.leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text(verbatim:L10n.render(notice ?? "Подборка на выбранном языке пока недоступна.",language:localizationLanguage))
                    .font(.system(size:12)).foregroundStyle(ReaderStyle.secondary)
            }
        }
    }
    private func openBooks(_ selected:String) {
        provider=selected;navigation.searchScope="books";navigation.tab = .search
    }
    private func refresh() async {
        loading=true;notice=nil
        defer {loading=false}
        do {
            let genres=RecommendationProfile.genres(ReaderPreferences.array(genresJSON))
            if selection == "books" {
                let found=try await DiscoveryService.books(genres:genres,language:language)
                try Task.checkCancellation()
                recommendations=RecommendationProfile.rank(found,excluding:library.books.map(\.title))
            } else {
                guard !disabledSources.components(separatedBy:",").contains(audioSource.rawValue) else {
                    audioBooks=[];notice="Включите источник аудиокниг.";return
                }
                let found=try await AudioCatalogService.featured(source:audioSource,language:language,genres:genres)
                try Task.checkCancellation()
                audioBooks=RecommendationProfile.rankAudio(found,genres:ReaderPreferences.array(genresJSON))
            }
        } catch is CancellationError {}
        catch {notice="Не удалось обновить подборку. Проверьте подключение."}
    }
}

struct CatalogPromoCarousel:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let audio:Bool
    let onSearch:()->Void
    let onLibrary:()->Void
    let onImport:()->Void
    @State private var index=0
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    var body:some View {
        VStack(spacing:7) {
            TabView(selection:$index) {
                promo(title:audio ? "Аудиокниги":"Электронные книги",
                      subtitle:audio ? "Слушайте любимые\nкниги в любое время":"Любимые истории —\nвсегда под рукой",action:onSearch).tag(0)
                promo(title:audio ? "Слушайте офлайн":"Читайте офлайн",
                      subtitle:"Ваша библиотека\nбез лишних отвлечений",action:onLibrary).tag(1)
                promo(title:"Свои книги",
                      subtitle:audio ? "Добавьте аудиокнигу\nиз приложения «Файлы»":"EPUB, FB2 и MOBI\nв вашей библиотеке",action:onImport).tag(2)
            }.tabViewStyle(.page(indexDisplayMode:.never)).frame(height:142)
            HStack(spacing:4) {
                ForEach(0..<3,id:\.self) {i in Circle().fill(index == i ? Color(hex:accentHex):Color.white.opacity(0.20)).frame(width:4,height:4)}
            }
        }.padding(.top,1)
    }
    private func promo(title:String,subtitle:String,action:@escaping()->Void)->some View {
        Button(action:action) {
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:7) {
                    Text(verbatim:L10n.render(title,language:localizationLanguage)).font(.system(size:20,weight:.bold)).tracking(-0.3)
                    Text(verbatim:L10n.render(subtitle,language:localizationLanguage)).font(.system(size:12)).lineSpacing(2).foregroundStyle(.white.opacity(0.8))
                }.padding(.leading,17).frame(maxWidth:.infinity,alignment:.leading)
                if audio {Image("HeroHeadphones").resizable().scaledToFit().frame(width:144,height:139).offset(x:5,y:9)}
                else {BrandBook(width:130).padding(.trailing,8)}
            }.foregroundStyle(.white).frame(maxWidth:.infinity).frame(height:142)
                .background {
                    ZStack(alignment:.bottom) {
                        LinearGradient(colors:[Color(hex:"#3B1556"),Color(hex:"#261039"),Color(hex:"#110A1C")],
                                       startPoint:.topLeading,endPoint:.bottomTrailing)
                        FooterWaves().frame(height:54).opacity(0.8)
                    }
                }.clipShape(RoundedRectangle(cornerRadius:13))
                .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(Color(hex:"#81509E").opacity(0.42),lineWidth:0.8))
        }.buttonStyle(.plain)
    }
}

struct UnifiedSearchScreen:View {
    @EnvironmentObject private var navigation:ReaderNavigation
    var body:some View {
        VStack(spacing:12) {
            ReaderHeader(title:"Поиск",trailingIcon:nil,trailingAction:nil).padding(.horizontal,ReaderMetrics.screenInset)
            ReaderSegmentedControl(items:[("books","Книги"),("audio","Аудиокниги")],selection:$navigation.searchScope)
                .padding(.horizontal,ReaderMetrics.screenInset)
            if navigation.searchScope == "books" {CatalogScreen(showsHeader:false)}
            else {AudioCatalogScreen(showsHeader:false)}
        }.readerCanvas()
    }
}
