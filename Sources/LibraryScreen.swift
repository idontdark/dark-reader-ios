import SwiftUI

struct LibraryScreen:View {
    @EnvironmentObject private var books:BookshelfStore
    @EnvironmentObject private var navigation:ReaderNavigation
    @EnvironmentObject private var audioPlayer:AudioPlayerModel
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent
    @AppStorage("audio.historyJSON") private var audioHistoryJSON="[]"
    @AppStorage("favoriteBooksJSON") private var selectedBooksJSON="[]"
    @AppStorage("catalog.wishlistJSON") private var wishlistJSON="[]"
    @AppStorage("catalog.favoritesJSON") private var favoritesJSON="[]"
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
    @State private var showSearch=false
    @State private var query=""
    @State private var featureIndex=0
    @State private var showLibraryTip=false

    private var kind:String { navigation.libraryScope }
    private var allAudio:[AudioBook] {
        audioHistoryJSON.data(using:.utf8).flatMap { try? JSONDecoder().decode([AudioBook].self,from:$0) } ?? []
    }
    private var recent:[LocalBook] {
        Array(books.books.sorted { ($0.locatorJSON != nil ? 1:0, $0.changeDate) >
                                  ($1.locatorJSON != nil ? 1:0, $1.changeDate) }.prefix(3))
    }
    private var wished:[CatalogBook] {
        CatalogBookmarks.decode(wishlistJSON).filter { item in !books.books.contains {$0.catalogID == item.id} }
    }
    private var catalogFavorites:[CatalogBook] {
        CatalogBookmarks.decode(favoritesJSON).filter { item in !books.books.contains {$0.catalogID == item.id} }
    }
    private var reading:[LocalBook] {
        books.books.filter {$0.locatorJSON != nil && BookProgress.fraction($0.locatorJSON)<0.98}
    }
    private var favoriteLocal:[LocalBook] { books.books.filter {$0.isFavorite == true} }
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
                    ReaderHeader(title:"Моя библиотека",trailingIcon:"plus",trailingAction:{
                        if kind == "audio" { showingAudioImport=true } else { showingImport=true }
                    },secondaryIcon:"magnifyingglass",secondaryAction:{withAnimation {showSearch.toggle()}})
                    ReaderSegmentedControl(items:[("books","Книги"),("audio","Аудиокниги")],selection:$navigation.libraryScope)
                    if showSearch {
                        HStack(spacing:9) {
                            Image(systemName:"magnifyingglass").foregroundStyle(ReaderStyle.secondary)
                            TextField("Название или автор",text:$query).font(.system(size:14))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }.padding(11).background(ReaderStyle.surface,in:RoundedRectangle(cornerRadius:10))
                    }
                    if kind == "books" { booksHome } else { audioHome }
                }.padding(.horizontal,18).padding(.bottom,24)
            }.readerCanvas().toolbar(.hidden,for:.navigationBar)
                .onAppear { offerHint() }
                .onChange(of:recent.count) {_,count in if featureIndex>=count {featureIndex=0}}
                .alert("Ваша библиотека",isPresented:$showLibraryTip) {
                    Button("Понятно") { hintLibraryShown=true }
                } message: { Text("Здесь хранятся ваши книги. Чтобы добавить новую, нажмите +.") }
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
        VStack(alignment:.leading,spacing:17) {
            if recent.isEmpty { welcome(audio:false) }
            else {
                VStack(spacing:7) {
                    TabView(selection:$featureIndex) {
                        ForEach(Array(recent.enumerated()),id:\.element.id) { index,book in
                            featured(book).tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode:.never)).frame(height:190)
                    if recent.count>1 { pageDots(count:recent.count,index:featureIndex) }
                }
            }
            if !showSearch {
                ReaderInsetGroup {
                    NavigationLink { bookCollection("Все книги",items:books.books) } label: {
                        LibraryMenuRow(icon:"books.vertical",title:"Все книги",count:books.books.count)
                    }.buttonStyle(.plain)
                    ReaderDivider()
                    NavigationLink { bookCollection("Читаю",items:reading) } label: {
                        LibraryMenuRow(icon:"book",title:"Читаю",count:reading.count)
                    }.buttonStyle(.plain)
                    ReaderDivider()
                    NavigationLink { wishlistCollection } label: {
                        LibraryMenuRow(icon:"bookmark",title:"Хочу прочитать",count:wished.count+DiscoveryService.saved(discoveryWishlist).count)
                    }.buttonStyle(.plain)
                    ReaderDivider()
                    NavigationLink { favoritesCollection } label: {
                        LibraryMenuRow(icon:"star",title:"Избранное",count:favoriteLocal.count+catalogFavorites.count+DiscoveryService.saved(selectedBooksJSON).count)
                    }.buttonStyle(.plain)
                }
            } else {
                bookRows(books.books.filter { query.isEmpty || ($0.title+" "+$0.author).localizedCaseInsensitiveContains(query) })
            }
            if !DiscoveryService.saved(selectedBooksJSON).isEmpty {
                VStack(alignment:.leading,spacing:10) {
                    SectionLabel(text:"Вы выбрали")
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(alignment:.top,spacing:12) {
                            ForEach(DiscoveryService.saved(selectedBooksJSON)) { book in
                                Button { selectedDiscovery=book } label: {
                                    VStack(alignment:.leading,spacing:6) {
                                        DiscoveryArtwork(book:book,width:88,height:128)
                                        Text(book.title).font(.system(size:11,weight:.medium)).lineLimit(2)
                                    }.foregroundStyle(.white).frame(width:88,alignment:.leading)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(.top,4)
            }
            if !books.books.isEmpty {
                VStack(alignment:.leading,spacing:10) {
                    SectionLabel(text:"Загруженные книги")
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(alignment:.top,spacing:12) {
                            ForEach(books.books.sorted {$0.addedAt > $1.addedAt}) {book in
                                Button {selected=book} label: {
                                    VStack(alignment:.leading,spacing:6) {
                                        BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:88,height:128)
                                        Text(book.title).font(.system(size:11,weight:.medium)).lineLimit(2)
                                    }.foregroundStyle(.white).frame(width:88,alignment:.leading)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(.top,4)
            }
        }
    }
    private var audioHome:some View {
        VStack(alignment:.leading,spacing:17) {
            if let book=audioPlayer.book ?? allAudio.first(where:{played($0)}) {
                audioFeatured(book)
            } else { welcome(audio:true) }
            ReaderInsetGroup {
                NavigationLink { audioCollection("Добавленные",items:allAudio) } label: {
                    LibraryMenuRow(icon:"headphones",title:"Добавленные",count:allAudio.count)
                }.buttonStyle(.plain)
                ReaderDivider()
                NavigationLink { audioCollection("Продолжить слушать",items:allAudio.filter{played($0)}) } label: {
                    LibraryMenuRow(icon:"play.circle",title:"Продолжить слушать",count:allAudio.filter{played($0)}.count)
                }.buttonStyle(.plain)
                ReaderDivider()
                NavigationLink { audioCollection("Загруженные",items:allAudio.filter{downloaded($0)}) } label: {
                    LibraryMenuRow(icon:"arrow.down.circle",title:"Загруженные",count:allAudio.filter{downloaded($0)}.count)
                }.buttonStyle(.plain)
                ReaderDivider()
                NavigationLink { audioCollection("Прослушанные",items:allAudio.filter{UserDefaults.standard.bool(forKey:"audio.finished.\($0.id)")}) } label: {
                    LibraryMenuRow(icon:"checkmark.circle",title:"Прослушанные",count:allAudio.filter{UserDefaults.standard.bool(forKey:"audio.finished.\($0.id)")}.count)
                }.buttonStyle(.plain)
            }
            if allAudio.isEmpty {
                VStack(spacing:12) {
                    Button("Найти аудиокнигу") { navigation.searchScope="audio";navigation.tab = .search }
                    Button("Импортировать аудиокнигу") { showingAudioImport=true }
                }.font(.system(size:13,weight:.medium)).foregroundStyle(Color(hex:accentHex))
                    .frame(maxWidth:.infinity).padding(.top,5)
            } else if showSearch {
                audioRows(allAudio.filter{query.isEmpty || ($0.title+" "+$0.author).localizedCaseInsensitiveContains(query)})
            }
        }
    }
    private func featured(_ book:LocalBook)->some View {
        HStack(alignment:.top,spacing:13) {
            BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:104,height:158)
            VStack(alignment:.leading,spacing:7) {
                Text(book.title).font(.system(size:16,weight:.semibold)).foregroundStyle(.white).lineLimit(3)
                Text(book.author).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).lineLimit(2)
                Spacer(minLength:4)
                HStack(spacing:7) {
                    ProgressView(value:BookProgress.fraction(book.locatorJSON)).tint(Color(hex:accentHex))
                    Text("\(Int((BookProgress.fraction(book.locatorJSON)*100).rounded())) %")
                        .font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.8))
                }
                PurpleAction(title:book.locatorJSON == nil ? "Читать":"Продолжить",icon:"arrow.down.to.line",height:32) {selected=book}
            }.frame(height:158)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(LinearGradient(colors:[Color(hex:"#2C203C"),Color(hex:"#28143E"),Color(hex:"#1A1324")],
                                       startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(Color(hex:"#7E4A9C").opacity(0.5),lineWidth:0.8))
    }
    private func audioFeatured(_ book:AudioBook)->some View {
        HStack(alignment:.top,spacing:13) {
            BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:104,height:158)
            VStack(alignment:.leading,spacing:7) {
                Text("Время слушать").font(.system(size:10,weight:.medium)).foregroundStyle(ReaderStyle.secondary)
                Text(book.title).font(.system(size:16,weight:.semibold)).lineLimit(3)
                Text(book.author).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).lineLimit(2)
                Spacer(minLength:0)
                PurpleAction(title:"Продолжить",icon:"play.fill",height:32) {
                    if audioPlayer.book?.id == book.id {showPlayer=true} else {selectedAudio=book}
                }
            }.frame(height:158)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(ReaderStyle.cardGradient,in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(ReaderStyle.line,lineWidth:0.8))
    }
    private func welcome(audio:Bool)->some View {
        HStack(spacing:8) {
            VStack(alignment:.leading,spacing:7) {
                Text(audio ? "Время слушать":"Время читать").font(.system(size:19,weight:.bold))
                Text(audio ? "Любимые истории —\nв вашем ритме." : "Соберите свою\nлюбимую библиотеку.")
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
    private func pageDots(count:Int,index:Int)->some View {
        HStack(spacing:4) {ForEach(0..<count,id:\.self) {i in Circle().fill(i == index ? Color(hex:accentHex):Color.white.opacity(0.18)).frame(width:4,height:4)}}
            .frame(maxWidth:.infinity)
    }
    private func bookCollection(_ title:String,items:[LocalBook])->some View {
        ScrollView {bookRows(items).padding(18)}.readerCanvas().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
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
                                    Text(book.author).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).lineLimit(1)
                                    if book.locatorJSON != nil {
                                        ProgressView(value:BookProgress.fraction(book.locatorJSON)).tint(Color(hex:accentHex)).frame(maxWidth:130)
                                    }
                                };Spacer()
                            }
                        }.buttonStyle(.plain)
                        Menu {
                            Button("Читать",systemImage:"book") {selected=book}
                            Button(book.isFavorite == true ? "Убрать из избранного":"В избранное",systemImage:"star") {books.toggleFavorite(book)}
                            Button("Удалить книгу",systemImage:"trash",role:.destructive) {books.delete(book)}
                        } label: {Image(systemName:"ellipsis").frame(width:28,height:40).foregroundStyle(ReaderStyle.secondary)}
                    }.padding(.vertical,10)
                    if book.id != items.last?.id {ReaderDivider()}
                }
            }
        }
    }
    private func catalogCollection(_ title:String,items:[CatalogBook])->some View {
        ScrollView {
            VStack(spacing:10) {
                if items.isEmpty {empty("Добавляйте книги с помощью значка закладки в карточке.")}
                ForEach(items) {book in
                    Button {selectedCatalog=book} label: {
                        ReaderCard {
                            HStack(spacing:12) {
                                BookArtwork(title:book.title,author:book.author,coverURL:book.coverURL,width:58,height:84)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(book.title).font(.system(size:14,weight:.semibold)).foregroundStyle(.white).lineLimit(2)
                                    Text(book.author).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                                };Spacer()
                                Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(18)
        }.readerCanvas().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
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
        }.readerCanvas().navigationTitle("Хочу прочитать").navigationBarTitleDisplayMode(.inline)
    }
    private func discoveryRows(_ items:[DiscoveryBook])->some View {
        ForEach(items) {book in
            Button {selectedDiscovery=book} label: {
                ReaderCard {
                    HStack(spacing:12) {
                        DiscoveryArtwork(book:book,width:48,height:70)
                        VStack(alignment:.leading,spacing:5) {
                            Text(book.title).font(.system(size:14,weight:.medium)).foregroundStyle(.white)
                            Text(book.author).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                        };Spacer()
                    }
                }
            }.buttonStyle(.plain)
        }
    }
    private var favoritesCollection:some View {
        ScrollView {
            VStack(spacing:16) {
                if !favoriteLocal.isEmpty {bookRows(favoriteLocal)}
                discoveryRows(DiscoveryService.saved(selectedBooksJSON))
                ForEach(catalogFavorites) {book in
                    Button {selectedCatalog=book} label: {
                        ReaderCard {Text(book.title).font(.system(size:14,weight:.medium)).foregroundStyle(.white)}
                    }.buttonStyle(.plain)
                }
            }.padding(18)
        }.readerCanvas().navigationTitle("Избранное").navigationBarTitleDisplayMode(.inline)
    }
    private func audioCollection(_ title:String,items:[AudioBook])->some View {
        ScrollView {audioRows(items).padding(18)}.readerCanvas().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
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
                                    Text(book.author).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary).lineLimit(1)
                                    Text(book.source.title).font(.system(size:10)).foregroundStyle(Color(hex:accentHex))
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
        Text(LocalizedStringKey(message)).font(.system(size:13)).foregroundStyle(ReaderStyle.secondary)
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
