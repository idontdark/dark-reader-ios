import Foundation

enum SourceHealthChecker {
    static func check(_ source: SourceDescriptor) async -> SourceHealthResult {
        await withTaskGroup(of: SourceHealthResult.self) { group in
            group.addTask { await perform(source) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                return SourceHealthResult(state: .unverified, checkedAt: Date(), domainReachable: false, searchSucceeded: false,
                    detailSucceeded: false, downloadSucceeded: false, playbackSucceeded: false, message: "Проверка заняла слишком много времени. Попробуйте ещё раз с VPN.")
            }
            let result = await group.next()!
            group.cancelAll(); return result
        }
    }
    private static func perform(_ source: SourceDescriptor) async -> SourceHealthResult {
        await SourceHTTPClient.shared.clearCache()
        var domain = false; var search = false; var detail = false; var download = false; var playback = false
        do { _ = try await SourceHTTPClient.shared.load(source.homepage, cached: false); domain = true } catch { }
        do {
            try Task.checkCancellation()
            if source.kind == .books {
                let adapter = BookSourceFactory.adapter(source)
                let query = source.adapter == .gutenberg ? "Austen" : "Чехов"
                let books = try await adapter.search(query, byAuthor: true, onPage: nil)
                search = !books.isEmpty
                if let first = books.first {
                    let book = try await adapter.detail(first)
                    detail = !book.title.isEmpty && book.author != "Неизвестный автор"
                    if let file = book.epubURL { download = await SourceFileProbe.check(file, kind: .book) }
                }
            } else {
                let adapter = AudioSourceFactory.adapter(source)
                let books = try await adapter.search(source.adapter == .librivox ? "Doyle" : "Чехов", byAuthor: true, onPage: nil)
                search = !books.isEmpty
                if let first = books.first {
                    let book = try await adapter.detail(first); detail = !book.title.isEmpty && !book.author.isEmpty
                    if let chapters = try? await adapter.chapters(book), let track = chapters.first {
                        playback = await SourceFileProbe.playable(track.url)
                        download = playback && ["mp3", "m4b", "m4a", "wav", "flac", "aac"].contains(track.url.pathExtension.lowercased())
                    }
                }
            }
        } catch { }
        let state: SourceHealthState = search && detail && (domain || download || playback) ? .working : (domain || search ? .partial : .unverified)
        let message = search && detail ? "Поиск и карточка произведения доступны." :
            domain ? "Сайт открывается, но поиск или карточку подтвердить не удалось." : "Не удалось связаться с источником. Он не был отключён."
        return SourceHealthResult(state: state, checkedAt: Date(), domainReachable: domain, searchSucceeded: search,
            detailSucceeded: detail, downloadSucceeded: download, playbackSucceeded: playback, message: message)
    }
}
