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

    private struct SubjectFeed: Decodable {
        let works: [Work]
    }

    private struct Work: Decodable {
        let key: String
        let title: String
        let cover_id: Int?
        let authors: [Person]?
    }

    private struct Person: Decodable {
        let name: String?
    }

    /// Fetches books by *actual* genre classification with cover ids and author metadata.
    /// Requests are bounded to at most 3 genres and 16 works each to be respectful of the public API.
    static func books(genres: [String], language: String, limit: Int = 24) async throws -> [DiscoveryBook] {
        let selected = Array((genres.isEmpty ? ["fantasy", "detective"] : genres).prefix(3))
        var result: [DiscoveryBook] = []
        var lastError: Error?
        for genre in selected {
            try Task.checkCancellation()
            guard let slug = genreSlugs[genre] else { continue }
            var components = URLComponents(string: "https://openlibrary.org/subjects/\(slug).json")!
            components.queryItems = [.init(name: "limit", value: "16")]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 14
            request.setValue("DarkReader/0.7 (iOS; genre discovery)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      data.count < 3_000_000 else { continue }
                let feed = try JSONDecoder().decode(SubjectFeed.self, from: data)
                for item in feed.works {
                    guard let cover = item.cover_id, cover > 0, item.key.hasPrefix("/works/"),
                          let coverURL = URL(string: "https://covers.openlibrary.org/b/id/\(cover)-M.jpg"),
                          let detailURL = URL(string: "https://openlibrary.org\(item.key)") else { continue }
                    let authors = (item.authors ?? []).compactMap(\.name)
                    result.append(DiscoveryBook(
                        id: "openlibrary:\(item.key)",
                        title: item.title,
                        author: authors.isEmpty ? (language == "en" ? "Author not listed" : "Автор не указан") : authors.joined(separator: ", "),
                        coverURL: coverURL,
                        detailURL: detailURL,
                        genre: genre
                    ))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        let unique = Array(Dictionary(grouping: result, by: \.id).values.compactMap(\.first))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
        AsyncImage(url: book.coverURL) { image in
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

struct DiscoveryBookDetail: View {
    let book: DiscoveryBook
    @EnvironmentObject private var navigation: ReaderNavigation
    @Environment(\.dismiss) private var dismiss
    @AppStorage("favoriteBooksJSON") private var favoritesJSON = "[]"
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    private var favorite: Bool { DiscoveryService.saved(favoritesJSON).contains(where: { $0.id == book.id }) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        DiscoveryArtwork(book: book, width: 125, height: 174)
                        VStack(alignment: .leading, spacing: 9) {
                            Text(book.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                            Text(book.author)
                                .font(.subheadline)
                                .foregroundStyle(ReaderStyle.secondary)
                        }
                    }
                    ReaderCard {
                        Text("Книга подобрана по жанру «\(ReaderPreferences.genreName(book.genre, language: "ru"))».")
                            .font(.subheadline)
                            .foregroundStyle(ReaderStyle.secondary)
                        Text("Наличие формата для скачивания зависит от каталога.")
                            .font(.footnote)
                            .foregroundStyle(ReaderStyle.secondary)
                            .padding(.top, 5)
                    }
                    PurpleAction(title: "Найти книгу для скачивания", icon: "magnifyingglass") {
                        navigation.bookToSearch = book.title
                        navigation.tab = .search
                        dismiss()
                    }
                    Button {
                        var values = DiscoveryService.saved(favoritesJSON)
                        if favorite { values.removeAll { $0.id == book.id } }
                        else { values.append(book) }
                        favoritesJSON = DiscoveryService.encode(values)
                    } label: {
                        Label(favorite ? "Удалить из избранного" : "Добавить в избранное",
                              systemImage: favorite ? "bookmark.fill" : "bookmark")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(ReaderStyle.line))
                    }
                    .foregroundStyle(.white)
                    Link(destination: book.detailURL) {
                        Label("Сведения об издании · Open Library", systemImage: "arrow.up.right.square")
                            .font(.footnote)
                            .foregroundStyle(Color(hex: accentHex))
                    }
                }
                .padding(20)
            }
            .readerCanvas()
            .navigationTitle("О книге")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}
