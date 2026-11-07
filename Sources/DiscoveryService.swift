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
        let author_name: [String]?
        let cover_i: Int?
        let editions: Editions?
    }

    /// Require a matching edition. A work's default title can be in another language.
    static func books(genres: [String], language: String, limit: Int = 24, sort: String = "readinglog") async throws -> [DiscoveryBook] {
        let code = language == "en" ? "eng" : "rus"
        let selected = Array((genres.isEmpty ? ["classics", "adventure"] : genres).prefix(3))
        var result: [DiscoveryBook] = []
        var lastError: Error?
        for genre in selected {
            try Task.checkCancellation()
            guard let slug = genreSlugs[genre] else { continue }
            var components = URLComponents(string: "https://openlibrary.org/search.json")!
            components.queryItems = [
                .init(name: "q", value: "language:\(code) subject:\(slug)"),
                .init(name: "lang", value: language),
                .init(name: "sort", value: sort),
                .init(name: "fields", value: "key,author_name,cover_i,editions,editions.key,editions.title,editions.language,editions.cover_i"),
                .init(name: "limit", value: "24")
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
                    guard let edition = item.editions?.docs.first(where: { $0.language?.contains(code) == true }),
                          let cover = edition.cover_i, cover > 0 else { continue }
                    if code == "rus", edition.title.range(of: "[А-Яа-яЁё]", options: .regularExpression) == nil { continue }
                    result.append(DiscoveryBook(
                        id: "openlibrary:\(item.key)", title: edition.title,
                        author: (item.author_name ?? []).joined(separator: ", "),
                        coverURL: URL(string: "https://covers.openlibrary.org/b/id/\(cover)-M.jpg")!,
                        detailURL: URL(string: "https://openlibrary.org\(edition.key)")!, genre: genre
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
        CachedCover(url: CoverSize.url(book.coverURL, detailed: width > 115)) { image in
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
    let book:DiscoveryBook
    @EnvironmentObject private var navigation:ReaderNavigation
    @Environment(\.dismiss) private var dismiss
    @AppStorage("favoriteBooksJSON") private var favoritesJSON="[]"
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
                    Text(summary ?? "Описание пока недоступно.")
                        .font(.system(size:14)).lineSpacing(4).foregroundStyle(summary == nil ? ReaderStyle.secondary:.white.opacity(0.88))
                        .frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,3)
                    PurpleAction(title:"Найти книгу для скачивания",icon:"arrow.down.to.line") {find("books")}
                    BookFavoriteButton(favorite:favorite) {toggle()}
                    Link(destination:book.detailURL) {
                        Text("Сведения об издании · Open Library").font(.system(size:11)).foregroundStyle(ReaderStyle.secondary)
                    }
                }.padding(.horizontal,20).padding(.top,10).padding(.bottom,30)
            }.readerCanvas().navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button {dismiss()} label:{Image(systemName:"chevron.left").font(.system(size:18,weight:.medium))}
                            .accessibilityLabel("Назад")
                    }
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        ShareLink(item:book.detailURL) {Image(systemName:"square.and.arrow.up").font(.system(size:17))}
                        Button {toggle()} label:{Image(systemName:favorite ? "bookmark.fill":"bookmark").font(.system(size:17))}
                            .accessibilityLabel("Избранное")
                    }
                }.tint(Color(hex:"#D2C5DE"))
                .task {summary=await BookDescription.discovery(book,language:language)}
                .onChange(of:format) {_,value in if value == "audio" {find("audio")}}
        }
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
