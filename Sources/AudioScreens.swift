import SwiftUI

struct AudioCatalogScreen: View {
    var showsHeader = true
    @EnvironmentObject private var player: AudioPlayerModel
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @AppStorage("preferredAudioSource") private var source: AudioSource = .librivox
    @AppStorage("disabledAudioSources") private var disabledSources = ""
    @AppStorage("preferredBookLanguage") private var bookLanguage = "auto"
    @AppStorage("appLanguage") private var language = "ru"
    @State private var query = ""
    @State private var byAuthor = false
    @State private var books: [AudioBook] = []
    @State private var searching = false
    @State private var didSearch = false
    @State private var showVPNHint = false
    @State private var message: String?
    @State private var searchID = UUID()
    @State private var searchTask: Task<Void, Never>?
    @State private var hintTask: Task<Void, Never>?
    @State private var selected: AudioBook?
    @State private var showPlayer = false
    private var color: Color { Color(hex: accentHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    if showsHeader {
                        ReaderHeader(title: "Аудиокниги", trailingIcon: nil, trailingAction: nil)
                    }
                    VStack(alignment: .leading, spacing: 13) {
                        NavigationLink("Источники аудиокниг") { AudioSourcesScreen() }
                        SectionLabel(text: "Источник")
                        Picker("Источник", selection: $source) {
                            ForEach(AudioSource.online.filter { !disabledSources.components(separatedBy: ",").contains($0.rawValue) }) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(ReaderStyle.secondary)
                            TextField("Название или автор", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { startSearch() }
                            if !query.isEmpty {
                                Button { query = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        .padding(14)
                        .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                        Picker("Искать", selection: $byAuthor) {
                            Text("По названию").tag(false)
                            Text("По автору").tag(true)
                        }
                        .pickerStyle(.segmented)

                        Picker("Язык книг", selection: $bookLanguage) {
                            Text("Русский").tag("ru")
                            Text("English").tag("en")
                            Text("Все").tag("all")
                        }.pickerStyle(.segmented)

                        PurpleAction(title: searching ? "Отменить поиск" : "Найти аудиокниги",
                                     icon: searching ? "xmark" : "magnifyingglass") {
                            if searching { cancelSearch() }
                            else { startSearch() }
                        }
                        .disabled(!searching && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if searching {
                            HStack(spacing: 9) {
                                ProgressView().tint(color)
                                Text("Ищем записи…")
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                            .font(.subheadline)
                            if showVPNHint {
                                Text("Поиск затянулся. Если каталог не открывается, попробуйте VPN.")
                                    .font(.footnote)
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                    }
                    if let message {
                        ReaderCard {
                            Label(message, systemImage: "wifi.exclamationmark")
                                .font(.subheadline)
                                .foregroundStyle(ReaderStyle.secondary)
                        }
                    }
                    HStack {
                        SectionLabel(text: didSearch ? "Результаты" : "Бесплатные записи")
                        Spacer()
                        if didSearch {
                            Text("\(books.count)")
                                .font(.caption).foregroundStyle(ReaderStyle.secondary)
                        }
                    }
                    if didSearch && books.isEmpty && !searching && message == nil {
                        ReaderCard {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Ничего не найдено")
                                    .font(.headline)
                                Text("Попробуйте другое название или автора. Бесплатных записей некоторых книг пока нет.")
                                    .font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                    } else if !didSearch && books.isEmpty {
                        ReaderCard {
                            Label("Найдите аудиокнигу и выбирайте главы для прослушивания.",
                                  systemImage: "headphones")
                                .font(.subheadline)
                                .foregroundStyle(ReaderStyle.secondary)
                        }
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(books) { book in
                            Button {
                                selected = book
                            } label: {
                                ReaderCard {
                                    HStack(spacing: 13) {
                                        BookArtwork(title: book.title, author: book.author,
                                                    coverURL: book.coverURL, width: 72, height: 100)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(book.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                            Text(book.author)
                                                .font(.footnote)
                                                .foregroundStyle(ReaderStyle.secondary)
                                                .lineLimit(2)
                                            Text(book.source.title)
                                                .font(.caption2)
                                                .foregroundStyle(color)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ReaderStyle.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if player.book != nil {
                        Button { showPlayer = true } label: {
                            Label("Продолжить прослушивание", systemImage: "play.circle.fill")
                                .foregroundStyle(color)
                                .font(.headline)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .readerCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) { book in
                AudioBookDetailScreen(book: book) { showPlayer = true }
                    .environmentObject(player)
            }
            .sheet(isPresented: $showPlayer) {
                AudioPlayerScreen()
                    .environmentObject(player)
            }
            .onAppear { if bookLanguage == "auto" { bookLanguage = language } }
            .onChange(of: source) { _, _ in
                cancelSearch()
                didSearch = false
                message = nil
                books = []
            }
            .onDisappear { if searching { cancelSearch() } }
        }
    }

    private func cancelSearch() {
        searchID = UUID()
        searchTask?.cancel()
        hintTask?.cancel()
        searchTask = nil
        hintTask = nil
        searching = false
        showVPNHint = false
    }

    private func startSearch() {
        cancelSearch()
        guard !disabledSources.components(separatedBy: ",").contains(source.rawValue), source != .local else {
            message = "Включите выбранный источник в настройках источников."
            return
        }
        didSearch = true
        books = []
        message = nil
        searching = true
        let token = UUID()
        searchID = token
        let chosenSource = source
        let term = query
        let authorMode = byAuthor
        hintTask = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled && searching && searchID == token { showVPNHint = true }
        }
        searchTask = Task {
            do {
                let result = try await AudioCatalogService.search(
                    source: chosenSource, query: term, byAuthor: authorMode, language: ReaderPreferences.effectiveLanguage(bookLanguage, appLanguage: language)
                )
                try Task.checkCancellation()
                guard source == chosenSource && searchID == token else { return }
                books = result
            } catch is CancellationError {
                // A canceled search is not an error and must not repaint old results.
            } catch {
                guard !Task.isCancelled && searchID == token else { return }
                message = "Не удалось загрузить записи. Проверьте интернет или попробуйте VPN."
            }
            guard searchID == token else { return }
            hintTask?.cancel()
            searching = false
            showVPNHint = false
        }
    }
}

struct AudioBookDetailScreen: View {
    let book: AudioBook
    let onPlay: () -> Void
    @EnvironmentObject private var player: AudioPlayerModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @State private var chapters: [AudioChapter] = []
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 17) {
                        BookArtwork(title: book.title, author: book.author,
                                    coverURL: book.coverURL, width: 116, height: 164)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title)
                                .font(.system(.title3, weight: .bold))
                            Text(book.author)
                                .foregroundStyle(ReaderStyle.secondary)
                                .font(.subheadline)
                            Text(book.source.title)
                                .font(.caption)
                                .foregroundStyle(Color(hex: accentHex))
                        }
                        Spacer(minLength: 0)
                    }
                    if book.source == .local {
                        NavigationLink("Изменить книгу и порядок глав") { AudioEditScreen(book: book) }
                    }
                    if !book.description.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            SectionLabel(text: "О книге")
                            Text(book.description.replacingOccurrences(of: "<[^>]+>", with: "",
                                    options: .regularExpression))
                                .font(.subheadline)
                                .foregroundStyle(ReaderStyle.secondary)
                                .lineLimit(9)
                        }
                    }
                    SectionLabel(text: "Главы")
                    if loading {
                        ProgressView("Загружаем главы…")
                    } else if let message {
                        Text(message).font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                    } else {
                        ForEach(chapters.indices, id: \.self) { index in
                            Button {
                                player.open(book, tracks: chapters)
                                player.playChapter(index)
                                dismiss()
                                onPlay()
                            } label: {
                                ReaderCard {
                                    HStack(spacing: 13) {
                                        Image(systemName: "play.circle")
                                            .foregroundStyle(Color(hex: accentHex))
                                            .font(.title2)
                                        Text(chapters[index].title)
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ReaderStyle.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .readerCanvas()
            .navigationTitle("Аудиокнига")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task {
                do {
                    chapters = try await AudioCatalogService.chapters(for: book)
                } catch {
                    message = "Не удалось загрузить главы. Проверьте интернет или попробуйте VPN."
                }
                loading = false
            }
        }
    }
}

struct AudioPlayerScreen: View {
    @EnvironmentObject private var player: AudioPlayerModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false
    private var color: Color { Color(hex: accentHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 16)
                    if let book = player.book {
                        BookArtwork(title: book.title, author: book.author,
                                    coverURL: book.coverURL, width: 178, height: 230)
                        Text(book.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundStyle(ReaderStyle.secondary)
                        if player.chapters.indices.contains(player.chapterIndex) {
                            Text(player.chapters[player.chapterIndex].title)
                                .foregroundStyle(ReaderStyle.secondary)
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                        }
                    }
                    Slider(
                        value: Binding(
                            get: { scrubbing ? scrubPosition : max(player.seekLowerBound, min(player.position, max(player.seekUpperBound, player.seekLowerBound + 1))) },
                            set: { scrubPosition = $0 }
                        ),
                        in: player.seekLowerBound...max(player.seekUpperBound, player.seekLowerBound + 1),
                        onEditingChanged: { editing in
                            scrubbing = editing
                            if !editing { player.seek(to: scrubPosition) }
                        }
                    )
                    .disabled(!player.canSeek)
                    .tint(color)
                    if !player.canSeek {
                        Text("Перемотка станет доступна, когда источник предоставит диапазон аудио.")
                            .font(.caption).foregroundStyle(ReaderStyle.secondary)
                    }
                    HStack {
                        Text(timeText(player.position))
                        Spacer()
                        Text(timeText(player.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ReaderStyle.secondary)
                    HStack(spacing: 22) {
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                        Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(color)
                        }
                        Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30") }
                        Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                    }
                    .font(.title2)
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    Menu {
                        Button("Добавить закладку", systemImage: "bookmark") { player.addBookmark() }
                        ForEach(player.bookmarks) { bookmark in
                            Button("Закладка · \(timeText(bookmark.position))") { player.openBookmark(bookmark) }
                        }
                        Divider()
                        ForEach(Array(player.chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button(chapter.title) { player.playChapter(index) }
                        }
                    } label: {
                        Label("Главы и закладки", systemImage: "list.bullet")
                    }.foregroundStyle(color)
                    HStack(spacing: 14) {
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                                Button("\(value.formatted())×") { player.setRate(Float(value)) }
                            }
                        } label: {
                            Label("\(Double(player.rate).formatted())×", systemImage: "speedometer")
                        }
                        Spacer()
                        Menu {
                            Button("Выключить таймер", systemImage: "xmark.circle") {
                                player.setSleepTimer(minutes: nil)
                            }
                            ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                                Button("\(minutes) мин") { player.setSleepTimer(minutes: minutes) }
                            }
                        } label: {
                            Label("Таймер", systemImage: "moon.zzz")
                        }
                        Spacer()
                        Button {
                            Task { await player.downloadCurrentChapter() }
                        } label: {
                            if player.downloadingChapter != nil {
                                ProgressView()
                            } else {
                                Label("Сохранить главу", systemImage: "arrow.down.to.line")
                            }
                        }
                        .disabled(player.downloadingChapter != nil)
                    }
                    .foregroundStyle(color)
                    .font(.subheadline)
                    if let error = player.error {
                        Text(error).font(.footnote).foregroundStyle(ReaderStyle.secondary)
                    }
                    if let remaining = player.sleepTimerRemaining {
                        Label("До остановки: \(Int(ceil(remaining / 60))) мин", systemImage: "moon.zzz")
                            .font(.caption)
                            .foregroundStyle(ReaderStyle.secondary)
                    }
                    Text("Продолжим с того же места при следующем запуске.")
                        .font(.caption)
                        .foregroundStyle(ReaderStyle.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .readerCanvas()
            .navigationTitle("Сейчас играет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func timeText(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
