import SwiftUI
import ReadiumShared

struct BookmarkedLocation {
    let title: String
    let detail: String
    let valid: Bool

    init(raw: String, index: Int, language: String) {
        let object = raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let name = (object?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        title = name.flatMap { $0.isEmpty ? nil : $0 } ?? String(format: L10n.text("Закладка %d", language: language), index + 1)
        valid = (try? Locator(jsonString: raw)) != nil
        let locations = object?["locations"] as? [String: Any]
        var parts: [String] = []
        if let page = locations?["position"] as? Int, page > 0 {
            parts.append(String(format: L10n.text("Страница %d", language: language), page))
        }
        if let fraction = locations?["totalProgression"] as? Double, fraction.isFinite, (0...1).contains(fraction) {
            parts.append("\(Int((fraction * 100).rounded()))%")
        }
        detail = valid ? (parts.isEmpty ? L10n.text("Место в книге", language: language) : parts.joined(separator: " · ")) : L10n.text("Закладка недоступна", language: language)
    }
}

struct LibraryBookmarksScreen: View {
    let audio: Bool
    @EnvironmentObject private var library: BookshelfStore
    @EnvironmentObject private var player: AudioPlayerModel
    @AppStorage("appLanguage") private var language = "ru"
    @AppStorage("audio.historyJSON") private var historyJSON = "[]"
    @AppStorage("accentHex") private var accentHex = ReaderStyle.defaultAccent
    @State private var target: ReadingTarget?
    @State private var openingAudio = false
    @State private var showPlayer = false
    @State private var error: String?
    @State private var editing: EditingTarget?
    @State private var name = ""
    @State private var showNameEditor = false

    private struct ReadingTarget: Identifiable {
        let id = UUID()
        let bookID: UUID
        let locator: String
    }
    private enum EditingTarget {
        case book(UUID, Int)
        case audio(AudioBook, UUID)
    }
    private var books: [LocalBook] { library.books.filter { !($0.bookmarks ?? []).isEmpty } }
    private var audioBooks: [AudioBook] {
        let history = historyJSON.data(using: .utf8).flatMap { try? JSONDecoder().decode([AudioBook].self, from: $0) } ?? []
        return history.filter { !player.savedBookmarks(for: $0).isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(verbatim: L10n.text("Мои закладки", language: language)).font(.title.bold()).foregroundStyle(.white)
                Text(verbatim: L10n.text("Выберите место, чтобы продолжить", language: language))
                    .font(.subheadline).foregroundStyle(ReaderStyle.secondary)
                if audio { audioGroups } else { bookGroups }
                if openingAudio { ProgressView().frame(maxWidth: .infinity).accessibilityLabel(Text(verbatim: L10n.text("Открываем аудиокнигу…", language: language))) }
                if let error {
                    Text(verbatim: error).font(.footnote).foregroundStyle(ReaderStyle.secondary)
                }
                Label {
                    Text(verbatim: L10n.text(audio ? "Нажмите на закладку, чтобы продолжить с сохранённого момента." : "Нажмите на закладку, чтобы открыть нужное место в книге.", language: language))
                } icon: { Image(systemName: "info.circle") }
                    .font(.footnote).foregroundStyle(ReaderStyle.secondary).padding(.top, 4)
            }.padding(20)
        }.readerCanvas().readerNavigationTitle("").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $target) { item in ReaderScreen(bookID: item.bookID, initialLocation: item.locator) }
            .fullScreenCover(isPresented: $showPlayer) { AudioPlayerScreen().environmentObject(player) }
            .alert(Text(verbatim: L10n.text("Название закладки", language: language)), isPresented: $showNameEditor) {
                TextField(L10n.text("Название", language: language), text: $name)
                Button(L10n.text("Сохранить", language: language)) { saveName() }
                Button(L10n.text("Отмена", language: language), role: .cancel) { editing = nil }
            }
    }

    @ViewBuilder private var bookGroups: some View {
        if books.isEmpty { emptyState }
        ForEach(books) { book in
            ReaderCard(inset: 14) {
                header(title: book.title, author: book.author, cover: book.coverURL, count: book.bookmarks?.count ?? 0)
                ForEach(Array((book.bookmarks ?? []).enumerated()), id: \.offset) { index, raw in
                    let location = BookmarkedLocation(raw: raw, index: index, language: language)
                    ReaderDivider()
                    Button { target = ReadingTarget(bookID: book.id, locator: raw) } label: {
                        bookmarkRow(title: location.title, subtitle: location.detail)
                    }.buttonStyle(.plain).disabled(!location.valid)
                        .contextMenu {
                            Button(L10n.text("Переименовать", language: language)) { name = location.title; editing = .book(book.id, index); showNameEditor = true }
                            Button(L10n.text("Удалить", language: language), role: .destructive) { library.deleteBookmark(bookID: book.id, index: index) }
                        }
                }
            }
        }
    }

    @ViewBuilder private var audioGroups: some View {
        if audioBooks.isEmpty { emptyState }
        ForEach(audioBooks) { book in
            let marks = player.savedBookmarks(for: book)
            ReaderCard(inset: 14) {
                header(title: book.title, author: book.author, cover: book.coverURL, count: marks.count)
                ForEach(Array(marks.enumerated()), id: \.element.id) { index, mark in
                    ReaderDivider()
                    Button { open(book, bookmark: mark) } label: {
                        bookmarkRow(title: mark.title.flatMap { $0.isEmpty ? nil : $0 } ?? String(format: L10n.text("Закладка %d", language: language), index + 1), subtitle: audioDetail(book, mark: mark))
                    }.buttonStyle(.plain).disabled(openingAudio)
                        .contextMenu {
                            Button(L10n.text("Переименовать", language: language)) { name = mark.title ?? ""; editing = .audio(book, mark.id); showNameEditor = true }
                            Button(L10n.text("Удалить", language: language), role: .destructive) { player.deleteBookmark(mark.id, for: book) }
                        }
                }
            }
        }
    }

    private var emptyState: some View {
        ReaderCard {
            Label {
                Text(verbatim: L10n.text(audio ? "Добавьте закладку в плеере, чтобы сохранить важный момент." : "Добавьте закладку во время чтения, чтобы вернуться к важному месту.", language: language))
            } icon: { Image(systemName: "bookmark") }
                .font(.subheadline).foregroundStyle(ReaderStyle.secondary).padding(.vertical, 8)
        }
    }

    private func header(title: String, author: String, cover: URL?, count: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            BookArtwork(title: title, author: author, coverURL: cover, width: 64, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title).font(.headline).foregroundStyle(.white).lineLimit(3)
                Text(verbatim: L10n.authorName(author)).font(.subheadline).foregroundStyle(ReaderStyle.secondary).lineLimit(2)
                Text(verbatim: L10n.bookmarkCount(count, language: language)).font(.caption).foregroundStyle(ReaderStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.bottom, 14)
    }

    private func bookmarkRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark").font(.title3).foregroundStyle(Color(hex: accentHex).shade(0.25)).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                Text(verbatim: subtitle).font(.caption).foregroundStyle(ReaderStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(ReaderStyle.secondary)
        }.padding(.vertical, 12).frame(minHeight: 44).contentShape(Rectangle())
    }

    private func audioDetail(_ book: AudioBook, mark: AudioPlayerModel.Bookmark) -> String {
        let chapter = AudioTrackCache.load(book)?.first { $0.id == mark.chapterID }?.title
        let seconds = mark.position.isFinite ? max(0, Int(mark.position)) : 0
        let time = String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        return [chapter, time].compactMap { $0 }.joined(separator: " · ")
    }

    private func open(_ book: AudioBook, bookmark: AudioPlayerModel.Bookmark) {
        guard !openingAudio else { return }
        openingAudio = true; error = nil
        Task { @MainActor in
            defer { openingAudio = false }
            do {
                let chapters = try await AudioCatalogService.chapters(for: book)
                guard chapters.contains(where: { $0.id == bookmark.chapterID }) else { throw AudioCatalogError.noTracks }
                player.open(book, tracks: chapters, bookmark: bookmark)
                showPlayer = true
            } catch { self.error = L10n.errorDescription(error) }
        }
    }

    private func saveName() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { editing = nil; return }
        switch editing {
        case .book(let id, let index): library.renameBookmark(bookID: id, index: index, name: value)
        case .audio(let book, let id): player.renameBookmark(id, for: book, name: value)
        case nil: break
        }
        editing = nil
    }
}
