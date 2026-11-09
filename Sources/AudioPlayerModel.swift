import Foundation
import AVFoundation
import MediaPlayer

/// A single playback engine shared across tabs. Playback survives closing its sheet.
@MainActor
final class AudioPlayerModel: ObservableObject {
    struct Bookmark: Codable, Identifiable {
        var id = UUID()
        var chapterID: String
        var position: Double
        var title: String? = nil
    }
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var book: AudioBook?
    @Published private(set) var chapters: [AudioChapter] = []
    @Published private(set) var chapterIndex = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var canSeek = false
    @Published private(set) var seekLowerBound: Double = 0
    @Published private(set) var seekUpperBound: Double = 0
    @Published var rate: Float = 1
    @Published var error: String?
    @Published private(set) var sleepTimerRemaining: TimeInterval?
    private var sleepTask: Task<Void, Never>?
    @Published private(set) var downloadingChapter: String?
    @Published private(set) var downloaded: Set<String> = []
    @Published private(set) var downloadBytes:Int64=0
    @Published private(set) var downloadExpectedBytes:Int64=0
    @Published private(set) var downloadingBookID: String?
    @Published private(set) var completedDownloads = 0
    @Published private(set) var totalDownloads = 0
    @Published private(set) var downloadError: String?
    @Published private(set) var downloadJobs: [AudioDownloadJob] = []
    private var downloadTask: Task<Void, Never>?
    private lazy var downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 3_600
        return URLSession(configuration: configuration)
    }()

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var playbackGeneration = UUID()
    private var seeking = false
    private var seekToken = UUID()
    private var recordedChapter = false
    private var pendingRestore: Double?
    private var wantsPlayback = false
    private let settings = UserDefaults.standard
    private let downloadKey = "audio.offlineChapters"

    init() {
        downloaded = Set(settings.stringArray(forKey: downloadKey) ?? [])
        if let raw = settings.data(forKey: "audio.downloadQueue.v1"), let saved = try? JSONDecoder().decode([AudioDownloadJob].self, from: raw) {
            downloadJobs = saved.map { item in
                var value = item
                if value.state == .downloading || value.state == .connecting { value.state = .queued }
                return value
            }
        }
        setUpRemoteCommands()
        Task { @MainActor [weak self] in self?.pumpDownloads() }
    }

    func open(_ selected: AudioBook, tracks: [AudioChapter], bookmark: Bookmark? = nil) {
        pause()
        guard !tracks.isEmpty else { error = AudioCatalogError.noTracks.localizedDescription; return }
        stopObserver()
        player = nil
        position = 0
        book = selected
        saveToHistory(selected)
        chapters = tracks
        bookmarks = settings.data(forKey: "audio.bookmarks.\(selected.id)").flatMap { try? JSONDecoder().decode([Bookmark].self, from: $0) } ?? []
        chapterIndex = 0
        let savedChapter = settings.integer(forKey: "audio.chapter.\(selected.id)")
        let savedID = settings.string(forKey: "audio.chapterID.\(selected.id)")
        chapterIndex = tracks.firstIndex(where: { $0.id == savedID }) ?? max(0, min(savedChapter, max(0, tracks.count - 1)))
        if let bookmark, let index = tracks.firstIndex(where: { $0.id == bookmark.chapterID }) { chapterIndex = index }
        playChapter(chapterIndex, resumePosition: bookmark?.position)
    }

    /// Save real played items so the Audiobooks section of Library survives relaunch.
    private func saveToHistory(_ item: AudioBook) {
        let key = "audio.historyJSON"
        let saved = settings.string(forKey: key) ?? "[]"
        let existing = (saved.data(using: .utf8)).flatMap {
            try? JSONDecoder().decode([AudioBook].self, from: $0)
        } ?? []
        let updated = [item] + existing.filter { $0.id != item.id }
        if let encoded = try? JSONEncoder().encode(updated) {
            settings.set(String(decoding: encoded, as: UTF8.self), forKey: key)
        }
    }

    func playChapter(_ index: Int, resumePosition: Double? = nil) {
        guard let book, chapters.indices.contains(index) else { return }
        if player != nil { saveProgress() }
        stopObserver()
        player?.pause()
        error = nil
        canSeek = false
        seeking = false
        recordedChapter = false
        wantsPlayback = true
        playbackGeneration = UUID()
        let generation = playbackGeneration
        chapterIndex = index
        let track = chapters[index]
        settings.set(index, forKey: "audio.chapter.\(book.id)")
        settings.set(track.id, forKey: "audio.chapterID.\(book.id)")

        let source = localURL(for: track) ?? track.url
        let item = AVPlayerItem(url: source)
        player = AVPlayer(playerItem: item)
        position = 0
        duration = track.durationSeconds ?? 0
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                            options: [.allowAirPlay, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            self.error = "Не удалось включить воспроизведение звука."
        }
        let saved = resumePosition ?? (settings.object(forKey: "audio.trackPosition.\(book.id).\(track.id)") as? Double)
            ?? settings.double(forKey: "audio.position.\(book.id).\(index)")
        pendingRestore = saved
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                if item.status == .readyToPlay {
                    self.refreshSeekability()
                    if self.canSeek { self.pendingRestore = nil; self.seek(to: saved) }
                    else if let start = track.startSeconds { self.player?.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
                    if self.wantsPlayback {
                        self.player?.playImmediately(atRate: self.rate)
                        self.isPlaying = true
                    }
                } else if item.status == .failed {
                    self.error = "Не удалось открыть аудио. Проверьте источник или импортируйте файл."
                    self.isPlaying = false
                    self.canSeek = false
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                self.settings.removeObject(forKey: "audio.position.\(book.id).\(index)")
                if index + 1 < self.chapters.count { self.playChapter(index + 1) }
                else {
                    self.settings.set(true, forKey: "audio.finished.\(book.id)")
                    self.pause()
                }
            }
        }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                self.didAdvance(to: time.seconds)
            }
        }
        updateNowPlaying()
    }

    func toggle() {
        if isPlaying { pause() }
        else {
            guard player != nil else { return }
            wantsPlayback = true
            player?.playImmediately(atRate: rate)
            isPlaying = true
            updateNowPlaying()
        }
    }

    func pause() {
        wantsPlayback = false
        player?.pause()
        isPlaying = false
        saveProgress()
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: max(0, position + seconds))
    }

    func seek(to seconds: Double) {
        refreshSeekability()
        guard seconds.isFinite, canSeek, let player else { return }
        pendingRestore = nil
        let clamped = max(seekLowerBound, min(seconds, seekUpperBound))
        let generation = playbackGeneration
        let resume = isPlaying
        let token = UUID()
        seekToken = token
        seeking = true
        player.seek(to: CMTime(seconds: clamped + (chapters[chapterIndex].startSeconds ?? 0), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation, self.seekToken == token else { return }
                self.seeking = false
                guard finished else { return }
                let actual = player.currentTime().seconds
                if actual.isFinite { self.position = max(0, actual - (self.chapters[self.chapterIndex].startSeconds ?? 0)) }
                self.saveProgress()
                self.updateNowPlaying()
                if resume && self.wantsPlayback { player.playImmediately(atRate: self.rate) }
            }
        }
    }

    private func refreshSeekability() {
        guard let item = player?.currentItem, item.status == .readyToPlay else {
            canSeek = false
            return
        }
        let length = item.duration.seconds
        let start = chapters.indices.contains(chapterIndex) ? (chapters[chapterIndex].startSeconds ?? 0) : 0
        if length.isFinite, length > 0 { duration = chapters[chapterIndex].startSeconds == nil ? length : (chapters[chapterIndex].durationSeconds ?? length) }
        let ranges = item.seekableTimeRanges.map(\.timeRangeValue).filter {
            $0.start.seconds.isFinite && $0.duration.seconds.isFinite && $0.duration.seconds > 0
        }
        // A finite duration alone does not prove that a remote stream is seekable.
        if let range = ranges.first {
            seekLowerBound = max(0, range.start.seconds - start)
            seekUpperBound = min(duration > 0 ? duration : Double.greatestFiniteMagnitude, CMTimeRangeGetEnd(range).seconds - start)
            canSeek = seekUpperBound > seekLowerBound
        } else if let asset = item.asset as? AVURLAsset, asset.url.isFileURL, duration > 0 {
            seekLowerBound = 0
            seekUpperBound = duration
            canSeek = true
        } else { canSeek = false }
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = canSeek
    }

    func next() { if chapterIndex + 1 < chapters.count { playChapter(chapterIndex + 1) } }
    func previous() { playChapter(max(0, chapterIndex - 1)) }

    func setRate(_ newValue: Float) {
        rate = newValue
        if isPlaying { player?.rate = newValue }
        updateNowPlaying()
    }

    /// Best-effort timer, evaluated against real clock time.
    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerRemaining = nil
        guard let minutes, minutes > 0 else { return }
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerRemaining = deadline.timeIntervalSinceNow
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                guard let self else { return }
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 {
                    self.pause()
                    self.sleepTimerRemaining = nil
                    self.sleepTask = nil
                    return
                }
                self.sleepTimerRemaining = remaining
            }
        }
    }

    func downloadCurrentChapter() async {
        guard let book, chapters.indices.contains(chapterIndex) else { return }
        startDownload(book, tracks: [chapters[chapterIndex]])
    }

    func startDownload(_ selected: AudioBook, tracks: [AudioChapter]) {
        guard !tracks.isEmpty, downloadingBookID != selected.id else { return }
        downloadJobs.removeAll { $0.id == selected.id }
        downloadJobs.append(AudioDownloadJob(book: selected, tracks: tracks))
        saveToHistory(selected); persistDownloads(); pumpDownloads()
    }
    private func persistDownloads() {
        settings.set(try? JSONEncoder().encode(downloadJobs), forKey: "audio.downloadQueue.v1")
    }
    private func updateDownload(_ id: String, state: DownloadState) {
        if let index = downloadJobs.firstIndex(where: { $0.id == id }) { downloadJobs[index].state = state }
        persistDownloads()
    }
    private func pumpDownloads() {
        guard downloadTask == nil, let job = downloadJobs.first(where: { $0.state == .queued }) else { return }
        downloadError = nil; downloadBytes = 0; downloadExpectedBytes = 0
        downloadingBookID = job.id; totalDownloads = job.tracks.count
        completedDownloads = job.tracks.filter { localURL(for: $0) != nil }.count
        updateDownload(job.id, state: .downloading)
        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.downloadingChapter = nil; self.downloadingBookID = nil; self.downloadTask = nil
                self.pumpDownloads()
            }
            do {
                for track in job.tracks {
                    try Task.checkCancellation()
                    guard self.localURL(for: track) == nil else { continue }
                    self.downloadingChapter = track.id
                    try await self.download(track)
                    self.completedDownloads += 1
                }
                self.updateDownload(job.id, state: .downloaded)
            } catch is CancellationError { self.updateDownload(job.id, state: .paused) }
            catch {
                self.updateDownload(job.id, state: Task.isCancelled ? .paused : .failed)
                if !Task.isCancelled { self.downloadError = L10n.text("Не удалось скачать аудиокнигу. Сохранённые главы доступны. Повторите загрузку, чтобы продолжить.") + " " + L10n.errorDescription(error) }
            }
        }
    }
    func cancelDownload() {
        if let id = downloadingBookID { updateDownload(id, state: .paused) }
        downloadTask?.cancel()
    }
    func cancelDownload(_ id: String) {
        if downloadingBookID == id { cancelDownload() }
        else { updateDownload(id, state: .paused) }
    }

    private func download(_ track: AudioChapter) async throws {
        let permit = try await MediaTransferGate.shared.acquire()
        defer { Task { await MediaTransferGate.shared.release(permit) } }
        try Task.checkCancellation()
        var request = URLRequest(url: track.url)
        request.setValue("DarkReader/1.0 (iOS; audiobook download)", forHTTPHeaderField: "User-Agent")
        downloadBytes=0;downloadExpectedBytes=0
        let progress=AudioTransferProgress { [weak self] bytes,expected in
            Task { @MainActor in
                guard let self,self.downloadingChapter == track.id else {return}
                self.downloadBytes=bytes;self.downloadExpectedBytes=expected
            }
        }
        let resumeURL = try audioFolder().appendingPathComponent(safeFilename(for: track) + ".resume")
        let temporary: URL; let response: URLResponse
        do {
            if let resume = try? Data(contentsOf: resumeURL), !resume.isEmpty {
                (temporary, response) = try await downloadSession.download(resumeFrom: resume, delegate: progress)
            } else { (temporary, response) = try await downloadSession.download(for: request, delegate: progress) }
        } catch {
            if let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data { try? resume.write(to: resumeURL, options: .atomic) }
            else { try? FileManager.default.removeItem(at: resumeURL) }
            throw error
        }
        try? FileManager.default.removeItem(at: resumeURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AudioCatalogError.unavailable
        }
        let length = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        let expected = http.statusCode == 206 ? http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) } : (response.expectedContentLength > 0 ? response.expectedContentLength : nil)
        guard length > 0, length <= 2_000_000_000 else { throw ImportFormatError.oversized }
        if let expected, http.value(forHTTPHeaderField: "Content-Encoding") == nil, expected != length { throw ImportFormatError.corrupt }
        // AVFoundation identifies local formats from the extension: URLSession's .tmp
        // URL can report zero audio tracks for a valid MP3. Stage with its real suffix.
        let base=try audioFolder()
        let staged=base.appendingPathComponent(".partial-"+UUID().uuidString)
            .appendingPathExtension(URL(fileURLWithPath:safeFilename(for:track)).pathExtension)
        try FileManager.default.moveItem(at:temporary,to:staged)
        defer {try? FileManager.default.removeItem(at:staged)}
        let asset = AVURLAsset(url: staged)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw AudioCatalogError.noTracks
        }
        try Task.checkCancellation()
        let target = try audioFolder().appendingPathComponent(safeFilename(for: track))
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: target)
        }
        downloaded.insert(track.id)
        settings.set(Array(downloaded), forKey: downloadKey)
    }

    func localURL(for track: AudioChapter) -> URL? {
        if track.url.isFileURL { return track.url }
        guard downloaded.contains(track.id),
              let base = try? audioFolder() else { return nil }
        for name in [safeFilename(for: track), safeFilename(for: track, legacy: true)] {
            let file = base.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    private func audioFolder() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audiobooks", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func safeFilename(for track: AudioChapter, legacy: Bool = false) -> String {
        // FNV-1a, deterministic and independent of Swift's randomized Hasher.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in track.id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        let ext = ["mp3", "m4a", "m4b", "aac", "flac", "wav"].contains(track.url.pathExtension.lowercased()) ? track.url.pathExtension.lowercased() : "mp3"
        return String(hash, radix: 16) + "." + (legacy ? "mp3" : ext)
    }

    private func didAdvance(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0, !seeking else { return }
        refreshSeekability()
        if canSeek, let restore = pendingRestore {
            pendingRestore = nil
            seek(to: restore)
            return
        }
        position = max(0, seconds - (chapters[chapterIndex].startSeconds ?? 0))
        if position >= 10, !recordedChapter, let book {
            RecommendationProfile.record(title: book.title, author: book.author, weight: 3, genre: book.genres?.first, kind: .audio, series: book.series)
            recordedChapter = true
        }
        if let seconds = player?.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
            if chapters[chapterIndex].startSeconds == nil { duration = seconds }
        }
        if chapters[chapterIndex].startSeconds != nil, duration > 0, position >= duration {
            if chapterIndex + 1 < chapters.count { playChapter(chapterIndex + 1) }
            else { if let book { settings.set(true, forKey: "audio.finished.\(book.id)") }; pause() }
            return
        }
        saveProgress()
        updateNowPlaying()
    }

    func savedBookmarks(for selected: AudioBook) -> [Bookmark] {
        if book?.id == selected.id { return bookmarks }
        return settings.data(forKey: "audio.bookmarks.\(selected.id)")
            .flatMap { try? JSONDecoder().decode([Bookmark].self, from: $0) } ?? []
    }
    private func saveBookmarks(_ marks: [Bookmark], for selected: AudioBook) {
        guard let data = try? JSONEncoder().encode(marks) else { return }
        settings.set(data, forKey: "audio.bookmarks.\(selected.id)")
        if book?.id == selected.id { bookmarks = marks }
        else { objectWillChange.send() }
    }
    func addBookmark() {
        guard let book, chapters.indices.contains(chapterIndex) else { return }
        var marks = savedBookmarks(for: book)
        marks.append(Bookmark(chapterID: chapters[chapterIndex].id, position: position))
        saveBookmarks(marks, for: book)
    }
    func renameBookmark(_ id: UUID, for selected: AudioBook, name: String) {
        var marks = savedBookmarks(for: selected)
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[index].title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saveBookmarks(marks, for: selected)
    }
    func deleteBookmark(_ id: UUID, for selected: AudioBook) {
        saveBookmarks(savedBookmarks(for: selected).filter { $0.id != id }, for: selected)
    }
    func openBookmark(_ bookmark: Bookmark) {
        guard let index = chapters.firstIndex(where: { $0.id == bookmark.chapterID }) else { return }
        playChapter(index, resumePosition: bookmark.position)
    }

    private func saveProgress() {
        guard let book else { return }
        settings.set(position, forKey: "audio.position.\(book.id).\(chapterIndex)")
        if chapters.indices.contains(chapterIndex) {
            settings.set(position, forKey: "audio.trackPosition.\(book.id).\(chapters[chapterIndex].id)")
        }
    }

    private func stopObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func updateNowPlaying() {
        guard let book, chapters.indices.contains(chapterIndex) else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: chapters[chapterIndex].title,
            MPMediaItemPropertyAlbumTitle: book.title,
            MPMediaItemPropertyArtist: book.author,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0
        ]
    }

    private func setUpRemoteCommands() {
        let remote = MPRemoteCommandCenter.shared()
        remote.skipBackwardCommand.preferredIntervals = [15]
        remote.skipForwardCommand.preferredIntervals = [30]
        remote.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -15) }
            return .success
        }
        remote.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 30) }
            return .success
        }
        remote.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
        remote.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == false { self?.toggle() }
            }
            return .success
        }
        remote.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        remote.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        remote.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }
}
