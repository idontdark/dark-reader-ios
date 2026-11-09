import Foundation
import SwiftUI

enum ReaderPreferences {
    static let genres: [(id: String, ru: String, en: String, icon: String)] = [
        ("detective", "Детективы", "Mystery", "magnifyingglass"),
        ("fantasy", "Фэнтези", "Fantasy", "sparkles"),
        ("science_fiction", "Научная фантастика", "Science fiction", "moon.stars"),
        ("historical_fiction", "Исторические романы", "Historical fiction", "building.columns"),
        ("psychology", "Психология", "Psychology", "brain"),
        ("business", "Бизнес", "Business", "briefcase"),
        ("romance", "Романы", "Romance", "heart"),
        ("classics", "Классика", "Classics", "books.vertical"),
        ("adventure", "Приключения", "Adventure", "safari"),
        ("history", "История", "History", "clock"),
        ("biography", "Биографии", "Biography", "person.crop.square"),
        ("nonfiction", "Нон-фикшн", "Non-fiction", "lightbulb"),
        ("children", "Детские", "Children", "figure.and.child.holdinghands"),
        ("thriller", "Триллеры", "Thrillers", "bolt")
    ]

    static let suggestedAuthorsRU = [
        "Артур Конан Дойл", "Александр Пушкин", "Жюль Верн",
        "Фёдор Достоевский", "Лев Толстой", "Михаил Булгаков",
        "Агата Кристи", "Ильф и Петров"
    ]
    static let suggestedAuthorsEN = [
        "Arthur Conan Doyle", "Jane Austen", "Jules Verne",
        "Mark Twain", "Charles Dickens", "Mary Shelley",
        "Agatha Christie", "Leo Tolstoy"
    ]

    static func array(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(NSOrderedSet(array: decoded)) as? [String] ?? decoded
    }

    static func encode(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    static func effectiveLanguage(_ choice: String, appLanguage: String) -> String? {
        switch choice {
        case "ru", "en": return choice
        case "all": return nil
        default: return appLanguage == "en" ? "en" : "ru"
        }
    }

    static func genreName(_ id: String, language: String) -> String {
        guard let item = genres.first(where: { $0.id == id }) else { return id }
        return language == "en" ? item.en : item.ru
    }
}

struct LanguageSettingsScreen: View {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent

    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @AppStorage("appLanguage") private var appLanguage = "ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("preferredAuthorsJSON") private var authorsJSON = "[]"
    @State private var showLanguageTip = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionLabel(text: "Язык приложения")
                ReaderCard {
                    languageOption("ru", "Русский", symbol: "🇷🇺")
                    ReaderDivider()
                    languageOption("en", "English", symbol: "🇬🇧")
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Язык книг")
                    ReaderCard {
                        bookLanguageOption("ru","Русский",symbol:"🇷🇺")
                        ReaderDivider()
                        bookLanguageOption("en","English",symbol:"🇬🇧")
                        ReaderDivider()
                        bookLanguageOption("all","Все языки",symbol:"🌐")
                        Text(verbatim:L10n.render("Язык книг настраивается отдельно от языка приложения. Фильтрация зависит от выбранного каталога.",language:localizationLanguage))
                            .font(.footnote)
                            .foregroundStyle(ReaderStyle.secondary)
                            .padding(.top, 9)
                    }
                }
            }
            .padding(20)
        }
        .readerCanvas()
        .readerNavigationTitle(appLanguage == "en" ? "Language":"Язык")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bookLanguageOption(_ code:String,_ label:String,symbol:String)->some View {
        Button {bookLanguage=code} label: {
            HStack(spacing:12) {
                Text(symbol).font(.title3)
                Text(label).foregroundStyle(.white)
                Spacer()
                if bookLanguage == code || (bookLanguage == "auto" && appLanguage == code) {
                    Image(systemName:"checkmark.circle.fill").foregroundStyle(Color(hex:accentHex))
                }
            }.padding(.vertical,13).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func languageOption(_ code: String, _ label: String, symbol: String) -> some View {
        Button {
            appLanguage = code

        } label: {
            HStack(spacing: 12) {
                Text(symbol).font(.title3)
                Text(label).foregroundStyle(.white)
                Spacer()
                if appLanguage == code {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: accentHex))
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FavoriteAuthorsScreen: View {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent

    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("preferredAuthorsJSON") private var authorsJSON = "[]"
    @AppStorage("appLanguage") private var language = "ru"
    @State private var authorInput = ""
    @FocusState private var isEditing: Bool

    private var favorites: [String] { ReaderPreferences.array(authorsJSON) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim:L10n.render("Любимые авторы",language:localizationLanguage))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(verbatim:L10n.render("Сохраняйте авторов и ищите их книги в одно касание.",language:localizationLanguage))
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                }
                ReaderCard {
                    HStack(spacing: 11) {
                        Image(systemName: "magnifyingglass").foregroundStyle(ReaderStyle.secondary)
                        TextField("Имя автора", text: $authorInput)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($isEditing)
                            .submitLabel(.done)
                            .onSubmit(addCustomAuthor)
                        Button { addCustomAuthor() } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(authorInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !favorites.isEmpty {
                    SectionLabel(text: "Вы подписаны")
                    ReaderCard {
                        ForEach(favorites, id: \.self) { author in
                            HStack {
                                Button {
                                    navigation.authorToSearch = author
                                    navigation.searchScope = "books"
                                    navigation.tab = .search
                                } label: {
                                    Label(author, systemImage: "person.crop.circle")
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button {
                                    authorsJSON = ReaderPreferences.encode(favorites.filter { $0 != author })
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(ReaderStyle.secondary)
                                }
                                .accessibilityLabel(Text(verbatim:L10n.render("Удалить автора",language:localizationLanguage)))
                            }
                            .padding(.vertical, 11)
                            if favorites.last != author { ReaderDivider() }
                        }
                    }
                }

                SectionLabel(text: "Популярные авторы")
                let suggested = language == "en"
                    ? ReaderPreferences.suggestedAuthorsEN : ReaderPreferences.suggestedAuthorsRU
                ReaderCard {
                    ForEach(suggested, id: \.self) { author in
                        Button {
                            toggle(author)
                        } label: {
                            HStack {
                                Text(verbatim:L10n.authorName(author)).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: favorites.contains(author) ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(Color(hex: accentHex))
                            }
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        if suggested.last != author { ReaderDivider() }
                    }
                }
            }
            .padding(20)
        }
        .readerCanvas()
        .readerNavigationTitle("Авторы")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ author: String) {
        var all = favorites
        if all.contains(author) { all.removeAll { $0 == author } }
        else { all.append(author) }
        authorsJSON = ReaderPreferences.encode(all)
    }

    private func addCustomAuthor() {
        let trimmed = authorInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return }
        if !favorites.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            authorsJSON = ReaderPreferences.encode(favorites + [trimmed])
        }
        authorInput = ""
        isEditing = false
    }
}

struct GenreSettingsScreen: View {
    var kind: SourceKind = .books
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent

    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("preferredAudioGenresJSON") private var audioGenresJSON = ""
    private var selectedJSON: String { kind == .audio && !audioGenresJSON.isEmpty ? audioGenresJSON : genresJSON }
    private var chosen: [String] { ReaderPreferences.array(selectedJSON) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim:L10n.render("Любимые жанры",language:localizationLanguage)).font(.system(size: 27, weight: .bold, design: .rounded))
                Text(verbatim:L10n.render("Выбранные жанры помогут подобрать книги для вас.",language:localizationLanguage))
                    .font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                ForEach(ReaderPreferences.genres, id: \.id) { item in
                    Button {
                        var values = chosen
                        if values.contains(item.id) { values.removeAll { $0 == item.id } }
                        else { values.append(item.id) }
                        if kind == .audio { audioGenresJSON = ReaderPreferences.encode(values) }
                        else { genresJSON = ReaderPreferences.encode(values) }
                        GoogleDriveBackup.shared.requestBackup()
                    } label: {
                        HStack {
                            Image(systemName: item.icon)
                                .foregroundStyle(Color(hex: accentHex))
                                .frame(width: 30)
                            Text(ReaderPreferences.genreName(item.id, language: language))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: chosen.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color(hex: accentHex))
                        }
                        .padding(15)
                        .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .readerCanvas()
        .readerNavigationTitle("Жанры")
        .navigationBarTitleDisplayMode(.inline)
    }
}
