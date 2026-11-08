import SwiftUI

enum DownloadState: String, Codable {
    case queued, connecting, downloading, paused, downloaded, failed
    var title: String {
        switch self {
        case .queued: "В очереди"
        case .connecting: "Подключение"
        case .downloading: "Загрузка"
        case .paused: "Пауза"
        case .downloaded: "Загружено"
        case .failed: "Не удалось загрузить"
        }
    }
}
struct BookDownload: Identifiable, Codable {
    var book: CatalogBook
    var state: DownloadState = .queued
    var progress: Double = 0
    var resumeData: Data?
    var id: String { book.id }
}
@MainActor
final class DownloadQueue: ObservableObject {
    static let shared = DownloadQueue()
    @Published private(set) var items: [BookDownload] = []
    private var tasks: [String: Task<Void, Never>] = [:]
    var activeDownloadCount: Int { tasks.count }
    private weak var library: BookshelfStore?
    private let storage: URL
    init(storage: URL? = nil) {
        self.storage = storage ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("download-queue.json")
        if let data = try? Data(contentsOf: self.storage),
           let saved = try? JSONDecoder().decode([BookDownload].self, from: data) {
            items = saved.map {
                var item = $0
                if [.connecting, .downloading].contains(item.state) { item.state = .queued }
                return item
            }
        }
    }
    func attach(_ library: BookshelfStore) { self.library = library; pump() }
    func enqueue(_ book: CatalogBook) {
        guard book.epubURL != nil, tasks[book.id] == nil,
              !items.contains(where: { ($0.id == book.id || $0.book.epubURL == book.epubURL) && [.queued, .connecting, .downloading, .paused].contains($0.state) }),
              library?.books.contains(where: { $0.catalogID == book.id }) != true else { return }
        items.removeAll { $0.id == book.id }
        items.append(BookDownload(book: book))
        persist()
        pump()
    }
    func pause(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state != .downloaded else { return }
        items[i].state = .paused
        library?.pauseDownload(id) { [weak self] data in
            guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[index].resumeData = data
            self.persist()
        }
        persist()
    }
    func cancel(_ id: String) {
        tasks[id]?.cancel()
        items.removeAll { $0.id == id }
        persist()
    }
    func retry(_ id: String) {
        guard tasks[id] == nil, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = .queued
        persist()
        pump()
    }
    private func pump() {
        guard let library else { return }
        while tasks.count < 3, let next = items.first(where: { $0.state == .queued && tasks[$0.id] == nil }) {
            let id = next.id
            update(id, state: .connecting)
            tasks[id] = Task { [weak self] in
                guard let self else { return }
                guard self.items.first(where: { $0.id == id })?.state == .connecting else {
                    self.tasks[id] = nil; self.pump(); return
                }
                do {
                    try await library.download(next.book, progress: { [weak self] progress in
                        guard let self, let i = self.items.firstIndex(where: { $0.id == id }),
                              self.items[i].state != .paused else { return }
                        self.items[i].state = .downloading
                        self.items[i].progress = progress
                    }, resumeData: next.resumeData)
                    self.update(id, state: .downloaded)
                } catch {
                    if let i = self.items.firstIndex(where: { $0.id == id }) {
                        if let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                            self.items[i].resumeData = resume
                        }
                        if self.items[i].state != .paused { self.items[i].state = .failed }
                    }
                }
                self.tasks[id] = nil
                self.persist()
                self.pump()
            }
        }
    }
    private func update(_ id: String, state: DownloadState) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].state = state
            if state == .downloaded { items[i].progress = 1; items[i].resumeData = nil }
        }
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: storage, options: .atomic) }
    }
}

struct DownloadsScreen: View {
    @AppStorage("appLanguage") private var localizationLanguage="ru"

    @ObservedObject private var queue = DownloadQueue.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if queue.items.isEmpty {
                    ReaderCard { Text(verbatim:L10n.render("Загрузок пока нет",language:localizationLanguage)).foregroundStyle(ReaderStyle.secondary) }
                }
                ForEach(queue.items) { item in
                    ReaderCard {
                        Text(item.book.title).font(.headline)
                        Text(verbatim:L10n.render(item.state.title,language:localizationLanguage)).font(.caption).foregroundStyle(ReaderStyle.secondary).padding(.vertical, 8)
                        if item.state == .downloading { ProgressView(value: item.progress) }
                        HStack {
                            if [.failed, .paused].contains(item.state) {
                                Button("Повторить") { queue.retry(item.id) }
                            }
                            if [.queued, .connecting, .downloading].contains(item.state) {
                                Button("Пауза") { queue.pause(item.id) }
                            }
                            if item.state != .downloaded {
                                Button("Отменить", role: .destructive) { queue.cancel(item.id) }
                            }
                        }.font(.subheadline).padding(.top, 8)
                    }
                }
            }.padding(20)
        }.readerCanvas().readerNavigationTitle("Загрузки")
    }
}
