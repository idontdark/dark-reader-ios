import SwiftUI

private struct CatalogHistoryPage {
    let heading: String
    let books: [CatalogBook]
}

struct CatalogScreen: View {
    @EnvironmentObject private var library: BookshelfStore
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @AppStorage("catalogProvider") private var provider = "flibusta"
    @AppStorage("catalogURL") private var customURL = "https://flibusta.is/opds/search?searchType=books"
    @AppStorage("catalogQueryParameter") private var customParameter = "searchTerm"
    @State private var query = ""
    @State private var mode = "title"
    @State private var results: [CatalogBook] = []
    @State private var history: [CatalogHistoryPage] = []
    @State private var heading = "Результаты"
    @State private var hasSearched = false
    @State private var searching = false
    @State private var downloadingID: String?
    @State private var downloadProgress = 0.0
    @State private var completedTitle: String?
    @State private var error: String?
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("hintCatalogShown") private var hintCatalogShown = false
    @State private var showCatalogTip = false

    private var providerName: String {
        switch provider {
        case "flibusta": "Флибуста"
        case "gutenberg": "Project Gutenberg"
        case "gutendex": "Gutendex"
        default: "Другой OPDS"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ReaderHeader(title: "Каталог книг", trailingIcon: nil, trailingAction: nil)

                    VStack(alignment: .leading, spacing: 14) {
                        Menu {
                            Button("Флибуста", systemImage: "books.vertical") { provider = "flibusta" }
                            Button("Project Gutenberg", systemImage: "globe") { provider = "gutenberg" }
                            Button("Gutendex", systemImage: "book.closed") { provider = "gutendex" }
                            Button("Другой OPDS", systemImage: "server.rack") { provider = "custom" }
                        } label: {
                            HStack {
                                Image(systemName: "square.stack")
                                    .foregroundStyle(Color(hex: accentHex))
                                Text(providerName)
                                    .foregroundStyle(.white)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                            .padding(14)
                            .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(ReaderStyle.secondary)
                            TextField("Название или автор", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { Task { await search() } }
                                .foregroundStyle(.white)
                            if !query.isEmpty {
                                Button { query = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 13))

                        Picker("Поиск", selection: $mode) {
                            Text("По названию").tag("title")
                            Text("По автору").tag("author")
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                            Text("Язык книг")
                            Spacer()
                            Menu {
                                Button("Автоматически") { bookLanguage = "auto" }
                                Button("Русский") { bookLanguage = "ru" }
                                Button("English") { bookLanguage = "en" }
                                Button("Все языки") { bookLanguage = "all" }
                            } label: {
                                Text(languageName)
                                    .foregroundStyle(Color(hex: accentHex))
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(ReaderStyle.secondary)

                        PurpleAction(title: searching ? "Ищем…" : "Найти книги", icon: "magnifyingglass") {
                            Task { await search() }
                        }
                        .disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    }

                    if let completedTitle {
                        ReaderCard {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Книга скачана")
                                        .font(.headline)
                                    Text("«\(completedTitle)» уже в библиотеке. Можно начинать чтение.")
                                        .font(.subheadline)
                                        .foregroundStyle(ReaderStyle.secondary)
                                }
                                Spacer(minLength: 0)
                                Button { self.completedTitle = nil } label: {
                                    Image(systemName: "xmark").foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .padding(.bottom, 13)
                            PurpleAction(title: "Открыть библиотеку", icon: "books.vertical") {
                                navigation.tab = .library
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            SectionLabel(text: heading)
                            Spacer()
                            if hasSearched {
                                Text("\(results.count)")
                                    .font(.caption)
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        if !supportsLanguageFiltering && hasSearched {
                            Text("Этот каталог не поддерживает точную фильтрацию по языку.")
                                .font(.caption)
                                .foregroundStyle(ReaderStyle.secondary)
                        }
                        if !history.isEmpty {
                            Button {
                                if let previous = history.popLast() {
                                    heading = previous.heading
                                    results = previous.books
                                }
                            } label: {
                                Label("Назад к результатам", systemImage: "chevron.left")
                                    .foregroundStyle(Color(hex: accentHex))
                                    .font(.subheadline)
                            }
                        }
                        if searching {
                            HStack(spacing: 12) {
                                ProgressView().tint(Color(hex: accentHex))
                                Text("Ищем книги…").foregroundStyle(ReaderStyle.secondary)
                            }
                            .padding(18)
                        } else if hasSearched && results.isEmpty {
                            emptyResults
                        } else if !hasSearched {
                            ReaderCard {
                                Label("Начните с названия книги или имени автора.", systemImage: "text.book.closed")
                                    .font(.subheadline)
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        } else {
                            LazyVStack(spacing: 11) {
                                ForEach(results) { book in
                                    bookRow(book)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .readerCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                handlePendingAuthor()
                if !hintCatalogShown {
                    hintCatalogShown = true
                    showCatalogTip = true
                }
            }
            .onChange(of: navigation.authorToSearch) { _, _ in handlePendingAuthor() }
            .alert("Поиск книг", isPresented: $showCatalogTip) {
                Button("Понятно") {}
            } message: {
                Text("Найдите книгу по названию или автору и скачайте EPUB. Он появится в библиотеке.")
            }
            .onChange(of: provider) { _, _ in
                history = []
                results = []
                completedTitle = nil
                hasSearched = false
            }
            .alert("Не удалось выполнить действие", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("Понятно", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var emptyResults: some View {
        ReaderCard {
            VStack(alignment: .leading, spacing: 7) {
                Text("Ничего не найдено").font(.headline)
                Text("Попробуйте другой запрос или переключите каталог.")
                    .font(.subheadline)
                    .foregroundStyle(ReaderStyle.secondary)
            }
        }
    }

    private func bookRow(_ book: CatalogBook) -> some View {
        ReaderCard {
            HStack(alignment: .center, spacing: 13) {
                BookArtwork(title: book.title, author: book.author,
                            coverURL: book.coverURL, width: 66, height: 94)
                VStack(alignment: .leading, spacing: 7) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(book.author)
                        .font(.footnote)
                        .foregroundStyle(ReaderStyle.secondary)
                        .lineLimit(1)
                    if downloadingID == book.id {
                        ProgressView(value: downloadProgress)
                            .tint(Color(hex: accentHex))
                        Text(downloadProgress > 0
                             ? "Скачивание \(Int(downloadProgress * 100))%"
                             : "Подключаемся…")
                            .font(.caption2)
                            .foregroundStyle(ReaderStyle.secondary)
                    } else {
                        Text(book.epubURL != nil ? "EPUB" : "Открыть раздел")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ReaderStyle.secondary)
                    }
                }
                Spacer(minLength: 1)
                if let epubURL = book.epubURL, epubURL.scheme == "https" {
                    Button { Task { await download(book) } } label: {
                        if downloadingID == book.id {
                            ProgressView().tint(Color(hex: accentHex))
                        } else {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(Color(hex: accentHex))
                        }
                    }
                    .disabled(downloadingID != nil)
                    .accessibilityLabel("Скачать \(book.title)")
                } else if book.navigationURL != nil {
                    Button { Task { await browse(book) } } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ReaderStyle.secondary)
                    }
                    .disabled(searching)
                    .accessibilityLabel("Открыть раздел \(book.title)")
                }
            }
        }
    }

    private var languageName: String {
        switch bookLanguage {
        case "en": return "English"
        case "ru": return "Русский"
        case "all": return "Все языки"
        default: return language == "en" ? "English" : "Русский"
        }
    }

    private var supportsLanguageFiltering: Bool { provider == "gutendex" }

    private func handlePendingAuthor() {
        guard let author = navigation.authorToSearch, !author.isEmpty else { return }
        navigation.authorToSearch = nil
        query = author
        mode = "author"
        Task { await search() }
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            results = try await CatalogProviders.search(
                query: query, mode: mode, provider: provider,
                customURL: customURL, customParameter: customParameter,
                language: ReaderPreferences.effectiveLanguage(bookLanguage, appLanguage: language)
            )
            hasSearched = true
            heading = "Результаты"
            history.removeAll()
            completedTitle = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func browse(_ book: CatalogBook) async {
        guard let url = book.navigationURL else { return }
        searching = true
        defer { searching = false }
        do {
            let next = try await CatalogProviders.browse(url: url)
            history.append(CatalogHistoryPage(heading: heading, books: results))
            heading = book.title
            results = next
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func download(_ book: CatalogBook) async {
        downloadingID = book.id
        downloadProgress = 0
        defer { downloadingID = nil }
        do {
            try await library.download(book) { value in
                downloadProgress = value
            }
            completedTitle = book.title
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
