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

struct CatalogScreen: View {
    @EnvironmentObject private var store: BookshelfStore
    @AppStorage("catalogURL") private var catalogURL = "https://flub.flibusta.is/opds/search"
    @AppStorage("catalogQueryParameter") private var queryParameter = "searchTerm"
    @State private var query = ""
    @State private var mode = "title"
    @State private var results: [CatalogBook] = []
    @State private var busy = false
    @State private var downloading: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Название книги или автор", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    Picker("Искать", selection: $mode) {
                        Text("По названию").tag("title")
                        Text("По автору").tag("author")
                    }.pickerStyle(.segmented)
                    Button("Найти книги") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
                if busy { ProgressView("Поиск в каталоге…") }
                Section("Результаты: \(results.count)") {
                    ForEach(results) { book in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(book.title).font(.headline)
                                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                                Text("EPUB").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            Button { Task { await download(book) } } label: {
                                if downloading == book.id { ProgressView() }
                                else { Image(systemName: "arrow.down.circle.fill").font(.title2) }
                            }
                            .buttonStyle(.borderless)
                            .disabled(downloading != nil)
                        }
                    }
                }
            }
            .navigationTitle("Каталог книг")
            .alert("Ошибка", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func search() async {
        busy = true
        defer { busy = false }
        do {
            let data = try await OPDSClient(searchEndpoint: catalogURL, queryParameter: queryParameter).search(query)
            results = mode == "author"
                ? data.sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
                : data
        } catch { results = []; self.error = error.localizedDescription }
    }

    private func download(_ book: CatalogBook) async {
        downloading = book.id
        defer { downloading = nil }
        do { try await store.download(book) }
        catch { self.error = error.localizedDescription }
    }
}

struct SettingsScreen: View {
    @AppStorage("catalogURL") private var catalogURL = "https://flub.flibusta.is/opds/search"
    @AppStorage("catalogQueryParameter") private var queryParameter = "searchTerm"
    @AppStorage("readerFontSize") private var fontSize = 1.1
    @AppStorage("readerTheme") private var theme = "system"
    @AppStorage("readerFont") private var font = "serif"
    @AppStorage("readerScroll") private var scroll = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Каталог OPDS") {
                    TextField("URL поиска", text: $catalogURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Параметр поиска", text: $queryParameter).textInputAutocapitalization(.never)
                    Text("Доступность адреса Флибусты не подтверждена. Поддерживаются совместимые OPDS-каталоги по HTTPS.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Оформление чтения") {
                    Picker("Тема", selection: $theme) {
                        Text("Системная").tag("system")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                        Text("Сепия").tag("sepia")
                        Text("OLED").tag("oled")
                    }
                    Picker("Шрифт", selection: $font) {
                        Text("С засечками").tag("serif")
                        Text("Без засечек").tag("sans")
                    }
                    HStack {
                        Text("Размер шрифта")
                        Slider(value: $fontSize, in: 0.7...3.0, step: 0.1)
                    }
                    Toggle("Вертикальная прокрутка", isOn: $scroll)
                }
                Section {
                    Text("Dark Reader · 0.1.0 · Readium").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
