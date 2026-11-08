import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AudioImportScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @State private var picking = false
    @State private var busy = false
    @State private var title = ""
    @State private var author = ""
    @State private var address = ""
    @State private var combine = true
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ReaderCard {
                        TextField("Название (можно оставить пустым)", text: $title).padding(.vertical, 10)
                        ReaderDivider()
                        TextField("Автор", text: $author).padding(.vertical, 10)
                        Toggle("Объединить выбранные файлы в одну книгу", isOn: $combine).padding(.vertical, 10)
                    }
                    PurpleAction(title: "Выбрать MP3, M4A, M4B или ZIP", icon: "folder") { picking = true }.disabled(busy)
                    ReaderCard {
                        TextField("HTTPS-ссылка на аудиофайл или ZIP", text: $address)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.bottom, 14)
                        Button("Импортировать по ссылке") {
                            guard let url = URL(string: address) else { return }
                            busy = true
                            Task {
                                defer { busy = false }
                                do { _ = try await AudioImportStore.importURL(url, title: title, author: author); message = "Аудиокнига добавлена в библиотеку." }
                                catch { message = "Не удалось импортировать аудио. Проверьте ссылку и формат." }
                            }
                        }.disabled(busy || address.isEmpty)
                    }
                    if busy { ProgressView("Импортируем аудио…") }
                    if let message { Text(verbatim:L10n.render(message,language:localizationLanguage)).font(.subheadline).foregroundStyle(ReaderStyle.secondary) }
                    Text(verbatim:L10n.render("Порядок глав, название, автора и обложку можно изменить в карточке импортированной книги.",language:localizationLanguage))
                        .font(.footnote).foregroundStyle(ReaderStyle.secondary)
                }.padding(20)
            }.readerCanvas().readerNavigationTitle("Импорт аудиокниг")
                .fileImporter(isPresented: $picking, allowedContentTypes: AudioImportStore.extensions.compactMap { UTType(filenameExtension: $0) },
                              allowsMultipleSelection: true) { result in
                    guard case .success(let urls) = result else { message = "Не удалось открыть файлы."; return }
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            if combine { _ = try await AudioImportStore.importFiles(urls, title: title, author: author) }
                            else { for file in urls { _ = try await AudioImportStore.importFiles([file], title: title, author: author) } }
                            message = "Аудиокниги добавлены в библиотеку."
                        } catch { message = "Не удалось прочитать аудио. Проверьте формат и свободное место." }
                    }
                }
        }
    }
}

struct AudioEditScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    let book: AudioBook
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var tracks: [AudioChapter] = []
    @State private var cover: URL?
    @State private var pickCover = false
    @State private var message: String?
    var body: some View {
        List {
            TextField("Название", text: $title)
            TextField("Автор", text: $author)
            Button("Изменить обложку") { pickCover = true }
            Section("Порядок глав") {
                ForEach(tracks) { Text($0.title) }
                    .onMove { tracks.move(fromOffsets: $0, toOffset: $1) }
            }
            if let message { Text(verbatim:L10n.render(message,language:localizationLanguage)) }
        }.scrollContentBackground(.hidden).readerCanvas().readerNavigationTitle("Изменить аудиокнигу")
            .environment(\.editMode, .constant(.active))
            .onAppear {
                title = book.title; author = book.author; cover = book.coverURL
                tracks = (try? AudioImportStore.chapters(for: book)) ?? []
            }
            .toolbar {
                Button("Сохранить") {
                    do {
                        let updated = AudioBook(id: book.id, source: book.source, sourceID: book.sourceID,
                                                title: title, author: author, description: book.description, coverURL: cover, language: book.language)
                        try AudioImportStore.save(.init(book: updated, chapters: tracks))
                        dismiss()
                    } catch { message = "Не удалось сохранить изменения." }
                }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || tracks.isEmpty)
            }
            .fileImporter(isPresented: $pickCover, allowedContentTypes: [.image]) { result in
                guard case .success(let file) = result else { return }
                let scoped = file.startAccessingSecurityScopedResource()
                defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: file)
                    guard data.count < 10_000_000, UIImage(data: data) != nil else { return }
                    let target = AudioImportStore.directory(book.sourceID).appendingPathComponent("custom-cover-" + UUID().uuidString + ".jpg")
                    try data.write(to: target, options: .atomic)
                    cover = target
                } catch { message = "Не удалось открыть изображение." }
            }
    }
}
