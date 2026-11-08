import SwiftUI
import UniformTypeIdentifiers

struct ImportScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @EnvironmentObject private var books: BookshelfStore
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @ObservedObject private var downloads=DownloadQueue.shared
    @State private var queuedID:String?
    @State private var importing = false
    @State private var directURL = ""
    @State private var downloading = false
    @State private var progress = 0.0
    @State private var completed = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ReaderHeader(title: "Добавить книгу", trailingIcon: nil, trailingAction: nil)

                    VStack(spacing: 0) {
                        Button { importing = true } label: {
                            ReaderRow(icon: "folder", title: "Из приложения «Файлы»",
                                      subtitle: "iCloud Drive, На iPhone, другие папки") {
                                Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        ReaderDivider()
                        Button { UserDefaults.standard.set("flibusta",forKey:"catalogProvider")
                            navigation.searchScope = "books"
                            navigation.tab = .search } label: {
                            ReaderRow(icon: "books.vertical", title: "Найти на Флибусте",
                                      subtitle: "Поиск и загрузка EPUB прямо в приложении") {
                                Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        ReaderDivider()
                        NavigationLink {
                            ImportTutorialScreen()
                        } label: {
                            ReaderRow(icon: "questionmark.circle", title: "Как импортировать книгу",
                                      subtitle: "Браузер, AirDrop, iCloud Drive") {
                                Image(systemName: "chevron.right").foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 15)
                    .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "По прямой ссылке")
                        ReaderCard {
                            Text(verbatim:L10n.render("Вставьте ссылку на книгу",language:localizationLanguage))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            HStack {
                                Image(systemName: "link")
                                    .foregroundStyle(ReaderStyle.secondary)
                                TextField("", text: $directURL,prompt:Text("https://example.com/book.fb2").foregroundColor(ReaderStyle.secondary))
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundStyle(.white)
                            }
                            .padding(.vertical, 14)

                            if downloading {
                                ProgressView(value: progress).tint(Color(hex: accentHex))
                                Text(verbatim:L10n.render(downloads.items.first(where:{$0.id == queuedID})?.state.title ?? "В очереди",language:localizationLanguage))
                                    .font(.caption)
                                    .foregroundStyle(ReaderStyle.secondary)
                                    .padding(.top, 7)
                            }
                            PurpleAction(title: downloading ? "Загружаем…" : "Загрузить книгу",
                                         icon: "arrow.down.to.line") {
                                Task { await downloadURL() }
                            }
                            .disabled(downloading || !isValidURL)
                            .opacity(downloading || !isValidURL ? 0.6 : 1)
                        }
                    }

                    if completed {
                        ReaderCard {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(verbatim:L10n.render("Книга добавлена",language:localizationLanguage)).font(.headline)
                                    Text(verbatim:L10n.render("Книга уже в библиотеке. Приятного чтения!",language:localizationLanguage))
                                        .font(.subheadline)
                                        .foregroundStyle(ReaderStyle.secondary)
                                }
                            }
                            .padding(.bottom, 12)
                            PurpleAction(title: "Открыть библиотеку", icon: "books.vertical") {
                                navigation.tab = .library
                            }
                        }
                    }

                    Text(verbatim:L10n.render("EPUB, FB2, MOBI и ZIP с книгой внутри. Защищённые DRM-файлы не поддерживаются.",language:localizationLanguage))
                        .font(.footnote)
                        .foregroundStyle(ReaderStyle.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .readerCanvas()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: ["epub", "fb2", "mobi", "zip"].compactMap { UTType(filenameExtension: $0) },
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { @MainActor in
                        var added = false
                        for url in urls {
                            do {
                                try await books.addImportedFile(
                                    from: url, title: url.deletingPathExtension().lastPathComponent
                                )
                                added = true
                            } catch {
                                self.error = L10n.errorDescription(error)
                            }
                        }
                        if added { completed = true }
                    }
                case .failure(let failure):
                    error = L10n.errorDescription(failure)
                }
            }
            .onReceive(downloads.$items) {items in
                guard let id=queuedID else{return}
                guard let item=items.first(where:{$0.id == id}) else {downloading=false;return}
                progress=item.progress
                downloading=[.queued,.connecting,.downloading,.paused].contains(item.state)
                if item.state == .downloaded {completed=true;directURL="";queuedID=nil}
                if item.state == .failed {error="Не удалось скачать книгу. Проверьте подключение и повторите попытку."}
            }
            .alert("Импорт не завершён", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("Понятно", role: .cancel) {}
            } message: { Text(verbatim:L10n.render(error ?? "",language:localizationLanguage)) }
        }
    }

    private var isValidURL: Bool {
        guard let url = URL(string: directURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "https" && url.host != nil
    }

    private func downloadURL() async {
        guard let url=URL(string:directURL.trimmingCharacters(in:.whitespacesAndNewlines)),isValidURL else{return}
        let name=url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "Книга"
        let book=CatalogBook(id:url.absoluteString,title:name.isEmpty ? "Книга":name,author:"Автор не указан",epubURL:url)
        if books.books.contains(where:{$0.catalogID == book.id}) {completed=true;downloading=false;directURL="";return}
        completed=false;progress=0;downloading=true
        if let existing=downloads.items.first(where:{$0.book.epubURL == url && $0.state != .failed}) {
            queuedID=existing.id
        } else {queuedID=book.id;downloads.enqueue(book)}
    }
}

struct ImportTutorialScreen: View {
    @AppStorage("accentHex") private var accentHex=ReaderStyle.defaultAccent

    @AppStorage("appLanguage") private var localizationLanguage="ru"

    private let steps: [(String, String, String)] = [
        ("1", "Скачайте книгу", "Подойдут EPUB, FB2, MOBI и ZIP с книгой внутри."),
        ("2", "Откройте «Файлы»", "Найдите скачанную книгу в «Загрузках» или iCloud Drive."),
        ("3", "Поделитесь книгой", "Удерживайте файл, выберите «Поделиться», затем Dark Reader."),
        ("4", "Продолжайте чтение", "Книга появится в библиотеке и будет доступна без интернета.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(verbatim:L10n.render("Как добавить книгу",language:localizationLanguage))
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text(verbatim:L10n.render("Три удобных способа",language:localizationLanguage))
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                }

                ReaderCard {
                    Label("Из «Файлов»", systemImage: "folder")
                        .font(.headline)
                    Text(verbatim:L10n.render("Выберите «Из приложения Файлы», затем одну или несколько книг. Поддерживаются EPUB, FB2, MOBI и ZIP.",language:localizationLanguage))
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                        .padding(.top, 7)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Из браузера")
                    ForEach(steps, id: \.0) { step in
                        HStack(alignment: .top, spacing: 13) {
                            Text(step.0)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 29, height: 29)
                                .background(Color(hex: accentHex), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim:L10n.render(step.1,language:localizationLanguage)).font(.subheadline.weight(.semibold))
                                Text(verbatim:L10n.render(step.2,language:localizationLanguage))
                                    .font(.subheadline)
                                    .foregroundStyle(ReaderStyle.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ReaderStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                    }
                }

                ReaderCard {
                    Label("AirDrop и iCloud Drive", systemImage: "icloud")
                        .font(.headline)
                    Text(verbatim:L10n.render("При получении EPUB через AirDrop выберите Dark Reader в меню «Поделиться». Файлы из iCloud Drive импортируются тем же способом.",language:localizationLanguage))
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                        .padding(.top, 7)
                }

                ReaderCard {
                    Label("Скачать напрямую с Флибусты", systemImage: "books.vertical")
                        .font(.headline)
                    Text(verbatim:L10n.render("В библиотеке выберите Флибусту или Project Gutenberg, найдите книгу по названию или автору и нажмите кнопку скачивания.",language:localizationLanguage))
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                        .padding(.top, 7)
                }
            }
            .padding(20)
        }
        .readerCanvas()
        .readerNavigationTitle("Импорт книг")
        .navigationBarTitleDisplayMode(.inline)
    }
}

