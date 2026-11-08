import SwiftUI
import Foundation

/// Public-domain discovery metadata. Items are *real works*, never AI-generated titles or covers.
/// Open Library does not guarantee the linked work has a downloadable file.
struct DiscoveryBook: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let coverURL: URL
    let detailURL: URL
    let genre: String
    var firstPublishYear:Int? = nil
}

enum DiscoveryService {
    private static let genreSlugs: [String: String] = [
        "detective": "mystery",
        "fantasy": "science_fiction",
        "romance": "romance",
        "classics": "classic_literature",
        "adventure": "adventure",
        "history": "history",
        "biography": "biography",
        "nonfiction": "nonfiction",
        "children": "juvenile_fiction",
        "thriller": "thrillers"
    ]

    private struct SearchFeed: Decodable { let docs: [Work] }
    private struct Editions: Decodable { let docs: [Edition] }
    private struct Edition: Decodable {
        let key: String
        let title: String
        let language: [String]?
        let cover_i: Int?
    }
    private struct Work: Decodable {
        let key: String
        let first_publish_year:Int?
        let author_name: [String]?
        let cover_i: Int?
        let editions: Editions?
    }

    /// Require a matching edition. A work's default title can be in another language.
    static func books(genres: [String], language: String, limit: Int = 24, sort: String = "readinglog") async throws -> [DiscoveryBook] {
        let code = language == "all" ? "":language == "en" ? "eng" : "rus"
        let selected = Array((genres.isEmpty ? ["all"] : genres).prefix(3))
        var result: [DiscoveryBook] = []
        var lastError: Error?
        for genre in selected {
            try Task.checkCancellation()
            let slug=genreSlugs[genre]
            let year=Calendar.current.component(.year,from:Date())
            let query=[code.isEmpty ? nil:"language:\(code)",slug.map {"subject:\($0)"},sort == "new" ? "first_publish_year:[\(year-2) TO \(year)]":nil].compactMap {$0}.joined(separator:" ")
            var components = URLComponents(string: "https://openlibrary.org/search.json")!
            components.queryItems = [
                .init(name: "q", value: query.isEmpty ? "*:*":query),
                .init(name: "lang", value: language),
                .init(name: "sort", value: sort),
                .init(name: "fields", value: "key,first_publish_year,author_name,cover_i,editions,editions.key,editions.title,editions.language,editions.cover_i"),
                .init(name: "limit", value: "60")
            ]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 18
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      data.count < 3_000_000 else { throw ReaderError.noResults }
                let feed = try JSONDecoder().decode(SearchFeed.self, from: data)
                for item in feed.docs {
                    guard let edition = item.editions?.docs.first(where: {code.isEmpty || $0.language?.contains(code) == true || $0.language == nil}) else {continue}
                    guard !edition.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,edition.title.count <= 300 else {continue}
                    let cover=edition.cover_i ?? item.cover_i ?? 0
                    if sort == "new", !(year-2...year).contains(item.first_publish_year ?? 0) {continue}
                    if code == "rus", edition.title.range(of: "[А-Яа-яЁё]", options: .regularExpression) == nil { continue }
                    result.append(DiscoveryBook(
                        id: "openlibrary:\(item.key)", title: edition.title,
                        author: (item.author_name ?? []).joined(separator: ", "),
                        coverURL: URL(string: "https://covers.openlibrary.org/b/id/\(cover)-M.jpg")!,
                        detailURL: URL(string: "https://openlibrary.org\(edition.key)")!, genre: genre,firstPublishYear:item.first_publish_year
                    ))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        var seen = Set<String>()
        let grouped = Dictionary(grouping: result, by: \.genre)
        var unique: [DiscoveryBook] = []
        for index in 0..<24 {
            for genre in selected {
                if let values = grouped[genre], values.indices.contains(index),
                   seen.insert(values[index].id).inserted { unique.append(values[index]) }
            }
        }
        if unique.isEmpty, let lastError { throw lastError }
        return Array(unique.prefix(limit))
    }

    static func saved(_ value: String) -> [DiscoveryBook] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DiscoveryBook].self, from: data)) ?? []
    }

    static func encode(_ books: [DiscoveryBook]) -> String {
        guard let data = try? JSONEncoder().encode(books) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

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
    var body:some View {
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
