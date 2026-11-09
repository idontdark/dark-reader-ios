import SwiftUI

struct DiscoveryArtwork: View {
    let book: DiscoveryBook
    var width: CGFloat = 104
    var height: CGFloat = 148

    var body: some View {
        CachedCover(url: CoverSize.url(book.coverURL, detailed: width > 115), pointSize: height) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                LinearGradient(colors: [
                    ReaderStyle.surface, Color(red: 0.30, green: 0.20, blue: 0.42)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "book.closed")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.13), lineWidth: 0.7))
        .accessibilityLabel(book.title)
    }
}

struct DiscoveryBookDetail:View {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent

    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let book:DiscoveryBook
    @EnvironmentObject private var navigation:ReaderNavigation
    @Environment(\.dismiss) private var dismiss
    @AppStorage("favoriteBooksJSON") private var favoritesJSON="[]"
    @AppStorage("discovery.wishlistJSON") private var wishlistJSON="[]"
    @AppStorage("appLanguage") private var language="ru"
    @State private var format="books"
    @State private var summary:String?
    private var favorite:Bool {DiscoveryService.saved(favoritesJSON).contains {$0.id == book.id}}
    @ViewBuilder var body: some View {
        if let catalog = book.catalogBook {
            CatalogBookDetailSheet(book: catalog) { dismiss() }
        } else { legacyBody }
    }
    private var legacyBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    BookDetailHero(title:book.title,author:book.author,coverURL:book.coverURL,
                                   tags:[ReaderPreferences.genreName(book.genre,language:language)])
                    ReaderSegmentedControl(items:[("books","Книга"),("audio","Аудиокнига")],selection:$format)
                    Text(verbatim:L10n.render(summary ?? "Описание пока недоступно.",language:localizationLanguage))
                        .font(.system(size:14)).lineSpacing(4).foregroundStyle(summary == nil ? ReaderStyle.secondary:.white.opacity(0.88))
                        .frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,3)
                    PurpleAction(title:"Найти книгу для скачивания",icon:"arrow.down.to.line") {find("books")}
                    BookFavoriteButton(favorite:favorite) {toggle()}
                    Link(destination:book.detailURL) {
                        Text(verbatim:L10n.render("Сведения об издании · Open Library",language:localizationLanguage)).font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                    }
                }.padding(.horizontal,20).padding(.top,10).padding(.bottom,30)
            }.readerCanvas().readerNavigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button {dismiss()} label:{Image(systemName:"chevron.left").font(.system(size:18,weight:.medium))}
                            .accessibilityLabel(Text(verbatim:L10n.render("Назад",language:localizationLanguage)))
                    }
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        ShareLink(item:book.detailURL) {Image(systemName:"square.and.arrow.up").font(.system(size:17))}
                        Button {toggleWishlist()} label:{Image(systemName:DiscoveryService.saved(wishlistJSON).contains {$0.id == book.id} ? "bookmark.fill":"bookmark").font(.system(size:17))}
                            .accessibilityLabel(Text(verbatim:L10n.render("Хочу прочитать",language:localizationLanguage)))
                    }
                }.tint(Color(hex:accentHex))
                .task {summary=await BookDescription.discovery(book,language:language)}
                .onChange(of:format) {_,value in if value == "audio" {find("audio")}}
        }
    }
    private func toggleWishlist() {
        var items=DiscoveryService.saved(wishlistJSON)
        if items.contains(where:{$0.id == book.id}) {items.removeAll {$0.id == book.id}} else {items.insert(book,at:0)}
        wishlistJSON=DiscoveryService.encode(items)
        GoogleDriveBackup.shared.requestBackup()
    }
    private func toggle() {
        var books=DiscoveryService.saved(favoritesJSON)
        if favorite {books.removeAll {$0.id == book.id}} else {books.append(book)}
        favoritesJSON=DiscoveryService.encode(books)
    }
    private func find(_ scope:String) {
        navigation.bookToSearch=book.title;navigation.searchScope=scope;navigation.tab = .search;dismiss()
    }
}
