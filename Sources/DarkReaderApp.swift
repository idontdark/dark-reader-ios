import SwiftUI
import UniformTypeIdentifiers

@main
struct DarkReaderApp: App {
    @StateObject private var bookshelf = BookshelfStore()
    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryScreen().tabItem { Label("Библиотека", systemImage: "books.vertical") }
                CatalogScreen().tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                SettingsScreen().tabItem { Label("Настройки", systemImage: "gearshape") }
            }
            .environmentObject(bookshelf)
            .tint(.indigo)
        }
    }
}

struct LibraryScreen: View {
    @EnvironmentObject private var store: BookshelfStore
    @State private var importing = false
    @State private var selected: LocalBook?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if store.books.isEmpty {
                    ContentUnavailableView("Пока нет книг", systemImage: "books.vertical",
                        description: Text("Найдите книгу или импортируйте EPUB."))
                }
                ForEach(store.books) { book in
                    Button { selected = book } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.headline)
                            Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                            if book.locatorJSON != nil {
                                Label("Продолжить чтение", systemImage: "bookmark.fill").font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button("Удалить", role: .destructive) { store.delete(book) }
                    }
                }
            }
            .navigationTitle("Моя библиотека")
            .toolbar { Button { importing = true } label: { Image(systemName: "plus") } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data]) { result in
                do {
                    let url = try result.get()
                    try store.addImportedFile(from: url, title: url.deletingPathExtension().lastPathComponent)
                } catch { self.error = error.localizedDescription }
            }
            .sheet(item: $selected) { book in
                ReaderScreen(bookID: book.id).environmentObject(store)
            }
            .alert("Ошибка", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

private struct CatalogPage {
    let title: String
    let results: [CatalogBook]
}

struct CatalogScreen: View {
    @EnvironmentObject private var store: BookshelfStore
    @AppStorage("catalogProvider") private var provider = "flibusta"
    @AppStorage("catalogURL") private var catalogURL = "https://flibusta.is/opds/search?searchType=books"
    @AppStorage("catalogQueryParameter") private var queryParameter = "searchTerm"
    @State private var query = ""
    @State private var mode = "title"
    @State private var results: [CatalogBook] = []
    @State private var previousPages: [CatalogPage] = []
    @State private var pageTitle = "Каталог книг"
    @State private var hasSearched = false
    @State private var busy = false
    @State private var downloading: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Источник") {
                    Picker("Каталог", selection: $provider) {
                        Text("Флибуста (OPDS)").tag("flibusta")
                        Text("Project Gutenberg (OPDS)").tag("gutenberg")
                        Text("Gutendex (нестабильный)").tag("gutendex")
                        Text("Другой OPDS").tag("custom")
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    TextField("Название книги или автор", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    Picker("Искать", selection: $mode) {
                        Text("По названию").tag("title")
                        Text("По автору").tag("author")
                    }
                    .pickerStyle(.segmented)
                    Button("Найти книги") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }

                if busy { ProgressView("Получаем данные каталога…") }

                if !previousPages.isEmpty {
                    Section {
                        Button {
                            if let previous = previousPages.popLast() {
                                results = previous.results
                                pageTitle = previous.title
                            }
                        } label: {
                            Label("Назад к результатам", systemImage: "arrow.left")
                        }
                    }
                }

                Section("Результаты: \(results.count)") {
                    if hasSearched && results.isEmpty && !busy {
                        ContentUnavailableView("Нет доступных EPUB", systemImage: "books.vertical",
                            description: Text("Попробуйте другой запрос или источник."))
                    }
                    ForEach(results) { book in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(book.title).font(.headline)
                                if book.epubURL != nil {
                                    Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                                    Text("EPUB").font(.caption2).foregroundStyle(.tertiary)
                                } else {
                                    Label("Открыть раздел", systemImage: "folder")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if book.epubURL != nil {
                                Button { Task { await download(book) } } label: {
                                    if downloading == book.id { ProgressView() }
                                    else { Image(systemName: "arrow.down.circle.fill").font(.title2) }
                                }
                                .buttonStyle(.borderless)
                                .disabled(downloading != nil || busy)
                                .accessibilityLabel("Скачать EPUB")
                            } else if book.navigationURL != nil {
                                Button { Task { await browse(book) } } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .buttonStyle(.borderless)
                                .disabled(busy)
                                .accessibilityLabel("Открыть \(book.title)")
                            }
                        }
                    }
                }
            }
            .navigationTitle(pageTitle)
            .onChange(of: provider) { _, _ in resetResults() }
            .onChange(of: mode) { _, _ in resetResults() }
            .alert("Ошибка", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func resetResults() {
        results = []
        previousPages = []
        pageTitle = "Каталог книг"
        hasSearched = false
    }

    private func search() async {
        busy = true
        defer { busy = false }
        do {
            results = try await CatalogProviders.search(
                query: query, mode: mode, provider: provider,
                customURL: catalogURL, customParameter: queryParameter
            )
            previousPages = []
            pageTitle = "Результаты поиска"
            hasSearched = true
        } catch {
            results = []
            previousPages = []
            self.error = error.localizedDescription
            hasSearched = true
        }
    }

    private func browse(_ book: CatalogBook) async {
        guard let url = book.navigationURL else { return }
        busy = true
        defer { busy = false }
        do {
            let next = try await CatalogProviders.browse(url: url)
            previousPages.append(CatalogPage(title: pageTitle, results: results))
            results = next
            pageTitle = book.title
            hasSearched = true
        } catch { self.error = error.localizedDescription }
    }

    private func download(_ book: CatalogBook) async {
        downloading = book.id
        defer { downloading = nil }
        do { try await store.download(book) }
        catch { self.error = error.localizedDescription }
    }
}

struct SettingsScreen: View {
    @AppStorage("catalogURL") private var catalogURL = "https://flibusta.is/opds/search?searchType=books"
    @AppStorage("catalogQueryParameter") private var queryParameter = "searchTerm"
    @AppStorage("readerFontSize") private var fontSize = 1.1
    @AppStorage("readerTheme") private var theme = "system"
    @AppStorage("readerFont") private var font = "serif"
    @AppStorage("readerScroll") private var scroll = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Чтение") {
                    Picker("Тема", selection: $theme) {
                        Text("Системная").tag("system")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                        Text("Сепия").tag("sepia")
                        Text("Чёрная (OLED)").tag("oled")
                    }

                    Picker("Шрифт", selection: $font) {
                        Text("С засечками").tag("serif")
                        Text("Без засечек").tag("sans")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Размер текста")
                            Spacer()
                            Text("\(Int(fontSize * 100)) %")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $fontSize, in: 0.7...3.0, step: 0.1)
                            .accessibilityLabel("Размер текста")
                    }
                    Toggle("Вертикальная прокрутка", isOn: $scroll)
                }

                Section("Каталоги") {
                    DisclosureGroup("Свой OPDS-каталог") {
                        TextField("Адрес поиска (HTTPS)", text: $catalogURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        TextField("Параметр поиска", text: $queryParameter)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("Используется при выборе «Другой OPDS» в поиске.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        SupportProjectScreen()
                    } label: {
                        Label("Поддержать проект", systemImage: "heart")
                    }

                    Link(destination: URL(string: "https://t.me/ipa_dark")!) {
                        HStack {
                            Label("Разработчик", systemImage: "paperplane")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("О приложении")
                } footer: {
                    Text("Dark Reader · версия \(appVersion)")
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
