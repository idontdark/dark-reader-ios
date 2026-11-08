import SwiftUI

struct LibraryScreen:View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @EnvironmentObject private var books:BookshelfStore
    @EnvironmentObject private var navigation:ReaderNavigation
    @EnvironmentObject private var audioPlayer:AudioPlayerModel
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    @AppStorage("audio.historyJSON") private var audioHistoryJSON="[]"
    @AppStorage("catalog.wishlistJSON") private var wishlistJSON="[]"
    @AppStorage("discovery.wishlistJSON") private var discoveryWishlist="[]"
    @AppStorage("hintLibraryShown") private var hintLibraryShown=false
    @AppStorage("onboardingSchemaVersion") private var onboardingVersion=0
    @State private var selected:LocalBook?
    @State private var selectedAudio:AudioBook?
    @State private var selectedCatalog:CatalogBook?
    @State private var selectedDiscovery:DiscoveryBook?
    @State private var showingImport=false
    @State private var showingAudioImport=false
    @State private var showPlayer=false
    @State private var showLibraryTip=false

    private var kind:String { navigation.libraryScope }
    private var allAudio:[AudioBook] {
        audioHistoryJSON.data(using:.utf8).flatMap { try? JSONDecoder().decode([AudioBook].self,from:$0) } ?? []
    }
    private var wished:[CatalogBook] {
        CatalogBookmarks.decode(wishlistJSON).filter { item in !books.books.contains {$0.catalogID == item.id} }
    }
    private var reading:[LocalBook] {
        books.books.filter {$0.locatorJSON != nil && BookProgress.fraction($0.locatorJSON)<0.98}.sorted {$0.changeDate > $1.changeDate}
    }
    private func played(_ book:AudioBook)->Bool {
        let settings=UserDefaults.standard
        let index=settings.integer(forKey:"audio.chapter.\(book.id)")
        return settings.double(forKey:"audio.position.\(book.id).\(index)")>0 &&
            !settings.bool(forKey:"audio.finished.\(book.id)")
    }
    private func downloaded(_ book:AudioBook)->Bool {
        if book.source == .local { return true }
        guard let tracks=AudioTrackCache.load(book),!tracks.isEmpty else { return false }
        return tracks.allSatisfy {audioPlayer.localURL(for:$0) != nil}
    }

    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    ReaderHeader(title:"Библиотека",trailingIcon:"plus",trailingAction:{
                        if kind == "audio" { showingAudioImport=true } else { showingImport=true }
                    })
                    ReaderSegmentedControl(items:[("books","Книги"),("audio","Аудиокниги")],selection:$navigation.libraryScope)
                    if kind == "books" { booksHome } else { audioHome }
                }.padding(.horizontal,20).padding(.top,8).padding(.bottom,24)
            }.readerCanvas().toolbar(.hidden,for:.navigationBar)
                .onAppear { offerHint() }
                .readerHint(isPresented:$showLibraryTip,title:"Начните свою библиотеку",message:"Нажмите «+», чтобы добавить файл. Новую книгу можно найти ниже, в разделе «Откройте новое».",icon:"books.vertical")
                .fullScreenCover(item:$selected) { ReaderScreen(bookID:$0.id) }
                .sheet(isPresented:$showingImport) { ImportScreen().environmentObject(books).environmentObject(navigation) }
                .sheet(isPresented:$showingAudioImport) { AudioImportScreen() }
                .fullScreenCover(item:$selectedAudio) { book in
                    AudioBookDetailScreen(book:book) {}.environmentObject(audioPlayer)
                }
                .fullScreenCover(item:$selectedCatalog) { book in
                    CatalogBookDetailSheet(book:book) {selectedCatalog=nil}.environmentObject(books)
                }
                .fullScreenCover(item:$selectedDiscovery) { book in
                    DiscoveryBookDetail(book:book).environmentObject(navigation)
                }
                .fullScreenCover(isPresented:$showPlayer) { AudioPlayerScreen().environmentObject(audioPlayer) }
        }
    }

    private var booksHome:some View {
        VStack(alignment:.leading,spacing:16) {
            if reading.isEmpty {welcome(audio:false)}
            else if let book=reading.first {featured(book)}
            ReaderInsetGroup {
                NavigationLink {bookCollection("Все книги",items:books.books)} label: {
                    LibraryMenuRow(icon:"book",title:"Все книги",count:books.books.count)
                }
                ReaderDivider()
                NavigationLink {bookCollection("Читаю",items:reading)} label: {
                    LibraryMenuRow(icon:"book",title:"Читаю",count:reading.count)
                }
                ReaderDivider()
                NavigationLink {wishlistCollection} label: {
                    LibraryMenuRow(icon:"bookmark",title:"Хочу прочитать",count:wished.count+DiscoveryService.saved(discoveryWishlist).count)
                }
                ReaderDivider()
                NavigationLink {LibraryBookmarksScreen(audio:false)} label: {
                    LibraryMenuRow(icon:"bookmark",title:"Мои закладки",count:books.books.reduce(0){$0+($1.bookmarks?.count ?? 0)})
                }
            }.buttonStyle(.plain)
            LibraryDiscoverySection(audio:false)
        }
    }
    private var audioHome:some View {
        VStack(alignment:.leading,spacing:16) {
            if let book=audioPlayer.book ?? allAudio.first(where:{played($0)}) {audioFeatured(book)}
            else {welcome(audio:true)}
            ReaderInsetGroup {
                NavigationLink {audioCollection("Все аудиокниги",items:allAudio)} label: {
                    LibraryMenuRow(icon:"headphones",title:"Все аудиокниги",count:allAudio.count)
                }
                ReaderDivider()
                NavigationLink {audioCollection("Слушаю",items:allAudio.filter{played($0)})} label: {
                    LibraryMenuRow(icon:"play.circle",title:"Слушаю",count:allAudio.filter{played($0)}.count)
                }
                ReaderDivider()
                NavigationLink {audioCollection("Загруженные",items:allAudio.filter{downloaded($0)})} label: {
                    LibraryMenuRow(icon:"arrow.down.to.line",title:"Загруженные",count:allAudio.filter{downloaded($0)}.count)
                }
                ReaderDivider()
                NavigationLink {LibraryBookmarksScreen(audio:true)} label: {
                    LibraryMenuRow(icon:"bookmark",title:"Мои закладки",count:allAudio.reduce(0){$0+audioPlayer.savedBookmarks(for:$1).count})
                }
            }.buttonStyle(.plain)
            LibraryDiscoverySection(audio:true)
        }
    }
    private func featured(_ book:LocalBook)->some View {
        HStack(alignment:.top,spacing:13) {
            BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:84,height:128)
            VStack(alignment:.leading,spacing:7) {
                Text(book.title).font(.system(size:16,weight:.semibold)).foregroundStyle(.white).lineLimit(2)
                Text(verbatim:L10n.authorName(book.author)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).lineLimit(2)
                Spacer(minLength:4)
                HStack(spacing:7) {
                    ProgressView(value:BookProgress.fraction(book.locatorJSON)).tint(Color(hex:accentHex))
                    Text("\(Int((BookProgress.fraction(book.locatorJSON)*100).rounded())) %")
                        .font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.8))
                }
                PurpleAction(title:book.locatorJSON == nil ? "Читать":"Продолжить",icon:"arrow.down.to.line",height:44) {selected=book}
            }.frame(minHeight:128)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(LinearGradient(colors:[Color(hex:"#2C203C"),Color(hex:"#28143E"),Color(hex:"#1A1324")],
                                       startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(Color(hex:"#7E4A9C").opacity(0.5),lineWidth:0.8))
    }
    private func audioFeatured(_ book:AudioBook)->some View {
        HStack(alignment:.top,spacing:13) {
            BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:84,height:128)
            VStack(alignment:.leading,spacing:7) {
                Text(verbatim:L10n.render("Время слушать",language:localizationLanguage)).font(.system(size:10,weight:.medium)).foregroundStyle(ReaderStyle.secondary)
                Text(book.title).font(.system(size:16,weight:.semibold)).lineLimit(2)
                Text(verbatim:L10n.authorName(book.author)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).lineLimit(2)
                Spacer(minLength:0)
                PurpleAction(title:"Продолжить",icon:"play.fill",height:44) {
                    if audioPlayer.book?.id == book.id {showPlayer=true} else {selectedAudio=book}
                }
            }.frame(minHeight:128)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(ReaderStyle.cardGradient,in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(ReaderStyle.line,lineWidth:0.8))
    }
    private func welcome(audio:Bool)->some View {
        HStack(spacing:8) {
            VStack(alignment:.leading,spacing:7) {
                Text(verbatim:L10n.render(audio ? "Время слушать":"Время читать",language:localizationLanguage)).font(.system(size:19,weight:.bold))
                Text(verbatim:L10n.render(audio ? "Любимые истории —\nв вашем ритме." : "Истории, которые\nждут вас",language:localizationLanguage))
                    .font(.system(size:12)).foregroundStyle(.white.opacity(0.7)).lineSpacing(2)
            }
            Spacer(minLength:0)
            if audio { Image("HeroHeadphones").resizable().scaledToFit().frame(width:125,height:120) }
            else { BrandBook(width:116) }
        }.padding(.leading,17).padding(.trailing,5).frame(maxWidth:.infinity).frame(height:140)
            .background {
                ZStack(alignment:.bottom) {
                    LinearGradient(colors:[Color(hex:"#321444"),Color(hex:"#21102F"),ReaderStyle.background],
                                   startPoint:.topLeading,endPoint:.bottomTrailing)
                    FooterWaves().frame(height:45).opacity(0.65)
                }.clipShape(RoundedRectangle(cornerRadius:13))
            }.overlay(RoundedRectangle(cornerRadius:13).strokeBorder(Color(hex:"#76438D").opacity(0.35),lineWidth:0.8))
    }
    private func bookCollection(_ title:String,items:[LocalBook])->some View {
        ScrollView {bookRows(items).padding(18)}.readerCanvas().readerNavigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func bookRows(_ items:[LocalBook])->some View {
        if items.isEmpty {empty("В этой категории пока нет книг.")}
        else {
            VStack(spacing:0) {
                ForEach(items) {book in
                    HStack(spacing:11) {
                        Button {selected=book} label: {
                            HStack(spacing:12) {
                                BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:58,height:84)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(book.title).font(.system(size:14,weight:.semibold)).lineLimit(2).foregroundStyle(.white)
                                    Text(verbatim:L10n.authorName(book.author)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).lineLimit(1)
                                    if book.locatorJSON != nil {
                                        ProgressView(value:BookProgress.fraction(book.locatorJSON)).tint(Color(hex:accentHex)).frame(maxWidth:130)
                                    }
                                };Spacer()
                            }
                        }.buttonStyle(.plain)
                        Menu {
                            Button("Читать",systemImage:"book") {selected=book}
                            Button(L10n.render(book.isFavorite == true ? "Убрать из избранного":"В избранное",language:localizationLanguage),systemImage:"star") {books.toggleFavorite(book)}
                            Button("Удалить книгу",systemImage:"trash",role:.destructive) {books.delete(book)}
                        } label: {Image(systemName:"ellipsis").frame(width:28,height:40).foregroundStyle(ReaderStyle.secondary)}
                    }.padding(.vertical,10)
                    if book.id != items.last?.id {ReaderDivider()}
                }
            }
        }
    }
    private var wishlistCollection:some View {
        ScrollView {
            VStack(spacing:12) {
                ForEach(wished) {book in
                    Button {selectedCatalog=book} label: {ReaderCard {Text(book.title).foregroundStyle(.white)}}.buttonStyle(.plain)
                }
                discoveryRows(DiscoveryService.saved(discoveryWishlist))
                if wished.isEmpty && DiscoveryService.saved(discoveryWishlist).isEmpty {empty("Добавляйте книги в этот список с помощью закладки в карточке книги.")}
            }.padding(18)
        }.readerCanvas().readerNavigationTitle("Хочу прочитать").navigationBarTitleDisplayMode(.inline)
    }
    private func discoveryRows(_ items:[DiscoveryBook])->some View {
        ForEach(items) {book in
            Button {selectedDiscovery=book} label: {
                ReaderCard {
                    HStack(spacing:12) {
                        DiscoveryArtwork(book:book,width:48,height:70)
                        VStack(alignment:.leading,spacing:5) {
                            Text(book.title).font(.system(size:14,weight:.medium)).foregroundStyle(.white)
                            Text(verbatim:L10n.authorName(book.author)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                        };Spacer()
                    }
                }
            }.buttonStyle(.plain)
        }
    }
    private func audioCollection(_ title:String,items:[AudioBook])->some View {
        ScrollView {audioRows(items).padding(18)}.readerCanvas().readerNavigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func audioRows(_ items:[AudioBook])->some View {
        if items.isEmpty {empty("В этой категории пока нет аудиокниг.")}
        else {
            VStack(spacing:10) {
                ForEach(items) {book in
                    Button {selectedAudio=book} label: {
                        ReaderCard {
                            HStack(spacing:12) {
                                BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:58,height:84)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(book.title).font(.system(size:14,weight:.semibold)).foregroundStyle(.white).lineLimit(2)
                                    Text(verbatim:L10n.authorName(book.author)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).lineLimit(1)
                                    Text(verbatim:L10n.render(book.source.title,language:localizationLanguage)).font(.system(size:10)).foregroundStyle(Color(hex:accentHex))
                                };Spacer()
                                Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func empty(_ message:String)->some View {
        Text(verbatim:L10n.render(message,language:localizationLanguage)).font(.system(size:13)).foregroundStyle(ReaderStyle.secondary)
            .frame(maxWidth:.infinity,alignment:.center).multilineTextAlignment(.center).padding(.vertical,30)
    }
    private func offerHint() {
        guard onboardingVersion>=3,!hintLibraryShown else{return}
        hintLibraryShown=true;showLibraryTip=true
    }
}
enum BookProgress {
    static func fraction(_ locator:String?)->Double {
        guard let locator,let data=locator.data(using:.utf8),
              let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let locations=object["locations"] as? [String:Any] else{return 0}
        let value=locations["totalProgression"] as? Double ?? locations["progression"] as? Double ?? 0
        return max(0,min(1,value))
    }
}
