import SwiftUI

private struct CatalogHistoryPage {
    let heading: String
    let books: [CatalogBook]
}

struct CatalogScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    var showsHeader = true
    @EnvironmentObject private var library: BookshelfStore
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @FocusState private var queryFocused: Bool
    private var query: String {
        get { navigation.searchQuery }
        nonmutating set { navigation.searchQuery = newValue }
    }
    @State private var mode = "title"
    @State private var results: [CatalogBook] = []
    @State private var history: [CatalogHistoryPage] = []
    @State private var heading = "Результаты"
    @State private var hasSearched = false
    @State private var searching = false
    @ObservedObject private var downloads = DownloadQueue.shared
    @State private var downloadingID: String?
    @State private var downloadProgress = 0.0
    @State private var completedTitle: String?
    @State private var error: String?
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("hintCatalogShown") private var hintCatalogShown = false
    @State private var showCatalogTip = false
    @AppStorage("preferredGenresJSON") private var genresJSON = "[]"
    @State private var searchTask: Task<Void, Never>?
    @State private var vpnTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var showVPNHint = false
    @State private var selectedBook: CatalogBook?
    @State private var readingBook:LocalBook?
    @State private var recommended: [CatalogBook] = []
    @State private var loadedRecommendations = false
    @State private var acceptedRevision = 0
    @State private var sourceFailures = 0
    @AppStorage(SourcePreferences.key) private var enabledSourceData = Data()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if showsHeader {
                        ReaderHeader(title: "Каталог книг", trailingIcon: nil, trailingAction: nil)
                    }

                    VStack(alignment: .leading, spacing: ReaderMetrics.formSpacing) {
                        ReaderQueryField(query:$navigation.searchQuery, focus:$queryFocused) {startSearch()}

                        ReaderSegmentedControl(items:[("title","По названию"),("author","По автору")],selection:$mode)
                        ReaderSearchLanguage(selection:$bookLanguage)

                        PurpleAction(title: searching ? "Отменить поиск" : "Найти книги",
                                     icon: searching ? "xmark" : "magnifyingglass") {
                            if searching { cancelSearch() } else { startSearch() }
                        }
                        .disabled(!searching && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(!searching && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    }

                    if let completedTitle {
                        ReaderCard {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim:L10n.render("Книга скачана",language:localizationLanguage))
                                        .font(.headline)
                                    Text(completedTitle)
                                    Text(verbatim:L10n.render("Книга уже в библиотеке. Можно начинать чтение.",language:localizationLanguage))
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

                    if showsHeader && !hasSearched && !recommended.isEmpty {
                        VStack(alignment: .leading, spacing: 13) {
                            SectionLabel(text: "Для вас")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(recommended) { book in
                                        Button { selectedBook = book } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                BookArtwork(title: book.title, author: book.author,
                                                            coverURL: book.coverURL, width: 96, height: 140)
                                                Text(book.title)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(2)
                                                Text(verbatim:L10n.authorName(book.author))
                                                    .font(.caption2)
                                                    .foregroundStyle(ReaderStyle.secondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 96, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
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
                        if sourceFailures > 0 {
                            Text(verbatim: L10n.text("Часть источников не ответила. Результаты остальных уже доступны."))
                                .font(.caption).foregroundStyle(ReaderStyle.secondary)
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
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(spacing: 12) {
                                    ProgressView().tint(Color(hex: accentHex))
                                    Text(verbatim:L10n.render("Ищем книги…",language:localizationLanguage)).foregroundStyle(ReaderStyle.secondary)
                                }
                                if showVPNHint {
                                    Text(verbatim:L10n.render("Поиск занимает больше времени обычного. Если каталог не отвечает, попробуйте VPN.",language:localizationLanguage))
                                        .font(.footnote)
                                        .foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .padding(18)
                        }
                        if hasSearched && results.isEmpty && !searching {
                            emptyResults
                        } else if !hasSearched && !searching {
                            ReaderCard {
                                Label("Начните с названия книги или имени автора.", systemImage: "text.book.closed")
                                    .font(.subheadline)
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        } else {
                            VStack(spacing: 11) {
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
            .onChange(of:navigation.searchScope) { _, scope in
                queryFocused = false
                if scope == "books" { handlePendingSearch() }
            }
            .onAppear {
                if bookLanguage == "auto" { bookLanguage = language }
                handlePendingAuthor()
                handlePendingBook()
                if !hintCatalogShown {
                    hintCatalogShown = true
                    showCatalogTip = true
                }
            }
            .onChange(of: navigation.authorToSearch) { _, _ in handlePendingAuthor() }
            .onChange(of: navigation.bookToSearch) { _, _ in handlePendingBook() }
            .onChange(of:library.books.map(\.id)) {old,ids in
                if let added=library.books.first(where:{candidate in !old.contains(candidate.id) && results.contains(where:{$0.id == candidate.catalogID})}),
                   let catalogID=added.catalogID,results.contains(where:{$0.id == catalogID}) {
                    completedTitle=added.title
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .readerHint(isPresented:$showCatalogTip,title:"Найдите свою следующую книгу",message:"Введите название или автора. Поиск выполняется по всем включённым источникам, а результаты появляются постепенно.",icon:"magnifyingglass")
            .onChange(of: enabledSourceData) { _, _ in
                cancelSearch()
                history = []
                results = []
                completedTitle = nil
                hasSearched = false
            }
            .task(id:results.prefix(8).map(\.id)) { await CoverCache.shared.prefetch(results.prefix(8).compactMap(\.coverURL)) }
            .onDisappear { cancelSearch() }
            .fullScreenCover(item: $selectedBook) { book in
                CatalogBookDetailSheet(book: book) { selectedBook = nil }
                    .environmentObject(library)
            }
            .fullScreenCover(item:$readingBook) {book in ReaderScreen(bookID:book.id).environmentObject(library)}
            .readerError($error,title:"Источник не ответил")
        }
    }

    private var emptyResults: some View {
        ReaderCard {
            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim:L10n.render("Ничего не найдено",language:localizationLanguage)).font(.headline)
                Text(verbatim:L10n.render("Попробуйте другое название или автора. Источники можно проверить в настройках.",language:localizationLanguage))
                    .font(.subheadline)
                    .foregroundStyle(ReaderStyle.secondary)
            }
        }
    }

    private func bookRow(_ book: CatalogBook) -> some View {
        let local=library.books.first {$0.catalogID == book.id}
        let task=downloads.items.first {$0.id == book.id}
        return ReaderCard {
            HStack(alignment: .center, spacing: 13) {
                Button { selectedBook = book } label: {
                    BookArtwork(title: book.title, author: book.author,
                                coverURL: book.coverURL, width: 66, height: 94)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 7) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(verbatim:L10n.authorName(book.author))
                        .font(.footnote)
                        .foregroundStyle(ReaderStyle.secondary)
                        .lineLimit(1)
                    if local != nil {
                        Label("В библиотеке",systemImage:"checkmark.circle.fill").font(.caption.weight(.medium)).foregroundStyle(.green)
                    } else if let task {
                        if [.connecting,.downloading,.queued].contains(task.state) {
                            ProgressView(value: task.progress).progressViewStyle(.linear)
                            .tint(Color(hex: accentHex))
                        }
                        Text(verbatim:L10n.render(task.state.title,language:localizationLanguage))
                            .font(.caption2)
                            .foregroundStyle(ReaderStyle.secondary)
                    } else {
                        Text(verbatim:L10n.render(book.downloadFormat?.uppercased() ?? "Карточка книги",language:localizationLanguage))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ReaderStyle.secondary)
                    }
                }
                Spacer(minLength: 1)
                if let epubURL = book.epubURL, ["http", "https"].contains(epubURL.scheme ?? "") {
                    Button {
                        if let local {readingBook=local}
                        else if let task,[.connecting,.downloading,.queued].contains(task.state) {downloads.pause(book.id)}
                        else if task?.state == .paused {downloads.retry(book.id)}
                        else {downloads.enqueue(book)}
                    } label: {
                        if local != nil {Text(verbatim:L10n.render("Читать",language:localizationLanguage)).font(.system(size:12,weight:.semibold)).foregroundStyle(Color(hex:accentHex))}
                        else {
                            Image(systemName:task?.state == .paused ? "play.circle" : task.map {[.connecting,.downloading,.queued].contains($0.state)} == true ? "pause.circle":"arrow.down.to.line")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(Color(hex: accentHex))
                        }
                    }
                    .accessibilityLabel(Text(verbatim:L10n.render(local != nil ? "Читать \(book.title)":"Загрузка \(book.title)",language:localizationLanguage)))
                } else if book.navigationURL != nil {
                    Button { selectedBook = book } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ReaderStyle.secondary)
                    }
                    .accessibilityLabel(Text(verbatim:L10n.render("Открыть раздел \(book.title)",language:localizationLanguage)))
                }
            }
        }.fixedSize(horizontal:false,vertical:true)
    }

    private var languageName: String {
        switch bookLanguage {
        case "en": return "English"
        case "ru": return "Русский"
        case "all": return "Все"
        default: return language == "en" ? "English" : "Русский"
        }
    }


    private func handlePendingSearch() { handlePendingAuthor(); handlePendingBook() }

    private func handlePendingAuthor() {
        guard navigation.searchScope == "books", navigation.tab == .search else { return }
        guard let author = navigation.authorToSearch, !author.isEmpty else { return }
        navigation.authorToSearch = nil
        query = author
        mode = "author"
        startSearch()
    }

    private func handlePendingBook() {
        guard navigation.searchScope == "books", navigation.tab == .search else { return }
        guard let title = navigation.bookToSearch, !title.isEmpty else { return }
        navigation.bookToSearch = nil
        query = title
        mode = "title"
        startSearch()
    }

    private func cancelSearch() {
        searchTask?.cancel()
        vpnTask?.cancel()
        searchTask = nil
        vpnTask = nil
        requestID = UUID()
        searching = false
        showVPNHint = false
    }

    private func startSearch() {
        queryFocused = false
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        cancelSearch()
        let token = UUID(); requestID = token
        let term = query; let authorMode = mode == "author"
        let selectedLanguage = ReaderPreferences.effectiveLanguage(bookLanguage, appLanguage: language)
        results = []; history = []; hasSearched = true; heading = "Результаты"
        acceptedRevision = 0; sourceFailures = 0; searching = true; error = nil
        searchTask = Task {
            defer { if requestID == token { searching = false } }
            do {
                let final = try await UnifiedSearchService.books(query: term, byAuthor: authorMode, language: selectedLanguage, onResults: { update in
                    await MainActor.run {
                        guard requestID == token, !Task.isCancelled, update.sequence > acceptedRevision else { return }
                        acceptedRevision = update.sequence; results = update.books; sourceFailures = update.failed.count
                    }
                })
                try Task.checkCancellation()
                guard requestID == token else { return }
                results = final
            } catch is CancellationError { }
            catch { if requestID == token { self.error = L10n.errorDescription(error) } }
        }
    }

    private func fetchRecommendations() async {
        let preferred = ReaderPreferences.effectiveLanguage(bookLanguage, appLanguage: language) ?? "all"
        recommended = (try? await UnifiedDiscoveryService.books(genres: ReaderPreferences.array(genresJSON), language: preferred, shelf: .personalized, limit: 12)) ?? []
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
            self.error = L10n.errorDescription(error)
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
            self.error = L10n.errorDescription(error)
        }
    }
}
