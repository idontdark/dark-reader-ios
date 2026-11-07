import SwiftUI

/// The browse experience matches the agreed navigation:
/// Library | Catalog | Search | Settings. Books and audiobooks share this catalog.
struct CatalogHomeScreen: View {
    @EnvironmentObject private var navigation: ReaderNavigation
    @EnvironmentObject private var player: AudioPlayerModel

    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("favoriteBooksJSON") private var favoritesJSON = "[]"
    @AppStorage("appLanguage") private var language = "ru"
    @State private var selection = "books"
    @State private var recommendations: [DiscoveryBook] = []
    @State private var audioBooks: [AudioBook] = []
    @State private var loadingBooks = false
    @State private var loadingAudio = false
    @State private var notice: String?
    @State private var selectedBook: DiscoveryBook?
    @State private var selectedAudio: AudioBook?
    @State private var focusedGenre: String?
    @State private var showPlayer = false
    private let accent = ReaderStyle.defaultAccent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ReaderHeader(title: "Каталог", trailingIcon: "magnifyingglass") {
                        navigation.searchScope = selection
                        navigation.tab = .search
                    }
                    Picker("Каталог", selection: $selection) {
                        Text("Книги").tag("books")
                        Text("Аудиокниги").tag("audio")
                    }
                    .pickerStyle(.segmented)

                    if selection == "books" { booksContent }
                    else { audioContent }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .readerCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .task(id: genresJSON + language) { await loadRecommendations() }
            .task(id: selection) {
                if selection == "audio" && audioBooks.isEmpty { await loadFeaturedAudio() }
            }
            .sheet(item: $selectedBook) { item in
                DiscoveryBookDetail(book: item).environmentObject(navigation)
            }
            .sheet(item: $selectedAudio) { item in
                AudioBookDetailScreen(book: item) { showPlayer = true }
                    .environmentObject(player)
            }
            .sheet(isPresented: $showPlayer) {
                AudioPlayerScreen().environmentObject(player)
            }
        }
    }

    private var booksContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            promo(symbol: "books.vertical.fill",
                  heading: "Истории, которые вам понравятся",
                  subheading: "Подборки по любимым жанрам и новые открытия")
            HStack(spacing: 9) {
                sourceChip("Флибуста", icon: "books.vertical", provider: "flibusta")
                sourceChip("Project Gutenberg", icon: "book.closed", provider: "gutendex")
            }
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    SectionLabel(text: focusedGenre.map {
                        ReaderPreferences.genreName($0, language: language)
                    } ?? "Для вас")
                    Spacer()
                    NavigationLink {
                        GenreSettingsScreen()
                    } label: {
                        Text("Изменить жанры")
                            .font(.caption)
                            .foregroundStyle(Color(hex: accentHex))
                    }
                }
                if loadingBooks && recommendations.isEmpty {
                    ProgressView("Подбираем книги…").tint(Color(hex: accentHex))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                } else if recommendations.isEmpty {
                    ReaderCard {
                        Text(notice ?? "Книги пока не загрузились. Повторите попытку.")
                            .font(.subheadline)
                            .foregroundStyle(ReaderStyle.secondary)
                        Button("Обновить") { Task { await loadRecommendations() } }
                            .foregroundStyle(Color(hex: accentHex))
                            .padding(.top, 10)
                    }
                } else {
                    shelf(recommendations)
                }
            }
            if !DiscoveryService.saved(favoritesJSON).isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    SectionLabel(text: "Вы выбрали")
                    shelf(DiscoveryService.saved(favoritesJSON))
                }
            }
            SectionLabel(text: "Жанры")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ReaderPreferences.genres, id: \.id) { genre in
                    Button {
                        Task { await loadGenre(genre.id) }
                    } label: {
                        HStack {
                            Image(systemName: genre.icon).foregroundStyle(Color(hex: accentHex))
                            Text(ReaderPreferences.genreName(genre.id, language: language))
                                .lineLimit(1)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(ReaderStyle.secondary)
                                .font(.caption)
                        }
                        .padding(12)
                        .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var audioContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            promo(symbol: "headphones",
                  heading: "Аудиокниги",
                  subheading: "Слушайте книги и сохраняйте главы на устройстве")
            HStack(spacing: 10) {
                audioSourceButton(.librivox)
                audioSourceButton(.archive)
            }
            SectionLabel(text: "Бесплатные аудиокниги")
            if loadingAudio && audioBooks.isEmpty {
                ProgressView("Загружаем аудиокниги…").tint(Color(hex: accentHex))
                    .padding(.vertical, 12)
            } else if !audioBooks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(audioBooks.prefix(12)) { item in
                            Button { selectedAudio = item } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    BookArtwork(title: item.title, author: item.author, coverURL: item.coverURL,
                                                width: 110, height: 155)
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    Text(item.author)
                                        .font(.caption2)
                                        .foregroundStyle(ReaderStyle.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 110, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ReaderCard {
                    Text(notice ?? "Не удалось загрузить аудиокниги. Проверьте подключение.")
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                    Button("Повторить") { Task { await loadFeaturedAudio() } }
                        .foregroundStyle(Color(hex: accentHex))
                        .padding(.top, 10)
                }
            }
            if player.book != nil {
                Button {
                    showPlayer = true
                } label: {
                    Label("Продолжить прослушивание", systemImage: "play.circle.fill")
                        .foregroundStyle(Color(hex: accentHex))
                        .font(.headline)
                }
            }
        }
    }

    private func promo(symbol: String, heading: String, subheading: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(heading)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subheading)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Color(hex: accentHex))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 128)
        .background(LinearGradient(colors: [ReaderStyle.surface, Color(hex: accentHex).opacity(0.23)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: accentHex).opacity(0.22)))
    }

    private func sourceChip(_ title: String, icon: String, provider: String) -> some View {
        Button {
            UserDefaults.standard.set(provider, forKey: "catalogProvider")
            navigation.searchScope = "books"
            navigation.tab = .search
        } label: {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func audioSourceButton(_ source: AudioSource) -> some View {
        Button {
            UserDefaults.standard.set(source.rawValue, forKey: "preferredAudioSource")
            navigation.searchScope = "audio"
            navigation.tab = .search
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "headphones")
                Text(source.title).lineLimit(1).minimumScaleFactor(0.85)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func shelf(_ books: [DiscoveryBook]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(books) { book in
                    Button { selectedBook = book } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            DiscoveryArtwork(book: book, width: 105, height: 149)
                            Text(book.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(book.author)
                                .font(.caption2)
                                .foregroundStyle(ReaderStyle.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 105, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadGenre(_ genre: String) async {
        focusedGenre = genre
        loadingBooks = true
        defer { loadingBooks = false }
        do {
            let books = try await DiscoveryService.books(genres: [genre], language: language)
            if !books.isEmpty {
                recommendations = books
                notice = nil
            } else {
                notice = "В этом жанре пока нет подходящих книг с обложками."
                recommendations = []
            }
        } catch {
            notice = "Не удалось обновить подборку. Проверьте интернет."
            recommendations = []
        }
    }

    private func loadRecommendations() async {
        loadingBooks = true
        defer { loadingBooks = false }
        do {
            let found = try await DiscoveryService.books(
                genres: ReaderPreferences.array(genresJSON), language: language
            )
            recommendations = found
            notice = nil
        } catch is CancellationError {
            return
        } catch {
            notice = "Не удалось обновить подборку. Проверьте интернет."
        }
    }

    private func loadFeaturedAudio() async {
        loadingAudio = true
        defer { loadingAudio = false }
        do {
            audioBooks = try await AudioCatalogService.featured(source: .librivox)
            notice = nil
        } catch {
            notice = "Каталог аудиокниг не ответил. Попробуйте позднее или включите VPN."
        }
    }
}

struct UnifiedSearchScreen: View {
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Поиск")
                    .font(.title2.bold())
                Spacer()
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(hex: accentHex))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            Picker("Тип книги", selection: $navigation.searchScope) {
                Text("Книги").tag("books")
                Text("Аудиокниги").tag("audio")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if navigation.searchScope == "books" {
                CatalogScreen(showsHeader: false)
            } else {
                AudioCatalogScreen(showsHeader: false)
            }
        }
        .readerCanvas()
    }
}
