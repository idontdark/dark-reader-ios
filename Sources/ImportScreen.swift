import SwiftUI
import UniformTypeIdentifiers

struct ImportScreen: View {
    @EnvironmentObject private var books: BookshelfStore
    @EnvironmentObject private var navigation: ReaderNavigation
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
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
                        Button { navigation.tab = .catalog } label: {
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
                            Text("Вставьте ссылку на книгу")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(hex: accentHex))
                            HStack {
                                Image(systemName: "link")
                                    .foregroundStyle(ReaderStyle.secondary)
                                TextField("https://example.com/book.fb2", text: $directURL)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundStyle(.white)
                            }
                            .padding(.vertical, 14)

                            if downloading {
                                ProgressView(value: progress).tint(Color(hex: accentHex))
                                Text("Скачиваем \(Int(progress * 100))%")
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
                                    Text("Книга добавлена").font(.headline)
                                    Text("Книга готова. Она появится в библиотеке и будет доступна без интернета.")
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

                    Text("EPUB, FB2, MOBI и ZIP с книгой внутри. Защищённые DRM-файлы не поддерживаются.")
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
                                self.error = error.localizedDescription
                            }
                        }
                        if added { completed = true }
                    }
                case .failure(let failure):
                    error = failure.localizedDescription
                }
            }
            .alert("Импорт не завершён", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("Понятно", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private var isValidURL: Bool {
        guard let url = URL(string: directURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "https" && url.host != nil && ["epub", "fb2", "mobi", "zip"].contains(url.pathExtension.lowercased())
    }

    private func downloadURL() async {
        guard let url = URL(string: directURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        downloading = true
        progress = 0
        completed = false
        defer { downloading = false }
        do {
            try await books.downloadFromURL(url) { value in
                progress = value
            }
            completed = true
            directURL = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ImportTutorialScreen: View {
    private let steps: [(String, String, String)] = [
        ("1", "Загрузите файл", "Скачайте книгу в формате EPUB через Safari или другой браузер."),
        ("2", "Откройте приложение «Файлы»", "Найдите EPUB в папке «Загрузки» или в iCloud Drive."),
        ("3", "Поделитесь книгой", "Удерживайте файл, выберите «Поделиться», затем Dark Reader."),
        ("4", "Продолжайте чтение", "Книга появится в библиотеке и будет доступна без интернета.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Как добавить книгу")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("Три удобных способа")
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                }

                ReaderCard {
                    Label("Из «Файлов»", systemImage: "folder")
                        .font(.headline)
                    Text("Нажмите «Добавить книгу» → «Из приложения Файлы» и выберите EPUB. Можно выбрать сразу несколько.")
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
                                .background(Color(hex: ReaderStyle.defaultAccent), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(LocalizedStringKey(step.1)).font(.subheadline.weight(.semibold))
                                Text(LocalizedStringKey(step.2))
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
                    Text("При получении EPUB через AirDrop выберите Dark Reader в меню «Поделиться». Файлы из iCloud Drive импортируются тем же способом.")
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                        .padding(.top, 7)
                }

                ReaderCard {
                    Label("Скачать напрямую с Флибусты", systemImage: "books.vertical")
                        .font(.headline)
                    Text("Откройте вкладку «Каталог», выберите Флибусту, найдите книгу по названию или автору и нажмите значок загрузки.")
                        .font(.subheadline)
                        .foregroundStyle(ReaderStyle.secondary)
                        .padding(.top, 7)
                }
            }
            .padding(20)
        }
        .readerCanvas()
        .navigationTitle("Импорт книг")
        .navigationBarTitleDisplayMode(.inline)
    }
}

