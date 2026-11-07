import Foundation
import AVFoundation
import MediaPlayer

/// A single playback engine shared across tabs. Playback survives closing its sheet.
@MainActor
final class AudioPlayerModel: ObservableObject {
    @Published private(set) var book: AudioBook?
    @Published private(set) var chapters: [AudioChapter] = []
    @Published private(set) var chapterIndex = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var rate: Float = 1
    @Published var error: String?
    @Published private(set) var sleepTimerRemaining: TimeInterval?
    private var sleepTask: Task<Void, Never>?
    @Published private(set) var downloadingChapter: String?
    @Published private(set) var downloaded: Set<String> = []

    private var player: AVPlayer?
    private var timeObserver: Any?
    private let settings = UserDefaults.standard
    private let downloadKey = "audio.offlineChapters"

    init() {
        downloaded = Set(settings.stringArray(forKey: downloadKey) ?? [])
        setUpRemoteCommands()
    }

    func open(_ selected: AudioBook, tracks: [AudioChapter]) {
        pause()
        book = selected
        saveToHistory(selected)
        chapters = tracks
        chapterIndex = 0
        let savedChapter = settings.integer(forKey: "audio.chapter.\(selected.id)")
        chapterIndex = max(0, min(savedChapter, max(0, tracks.count - 1)))
        playChapter(chapterIndex)
    }

    /// Save real played items so the Audiobooks section of Library survives relaunch.
    private func saveToHistory(_ item: AudioBook) {
        let key = "audio.historyJSON"
        let saved = settings.string(forKey: key) ?? "[]"
        let existing = (saved.data(using: .utf8)).flatMap {
            try? JSONDecoder().decode([AudioBook].self, from: $0)
        } ?? []
        let updated = [item] + existing.filter { $0.id != item.id }
        if let encoded = try? JSONEncoder().encode(Array(updated.prefix(40))) {
            settings.set(String(decoding: encoded, as: UTF8.self), forKey: key)
        }
    }

    func playChapter(_ index: Int) {
        guard let book, chapters.indices.contains(index) else { return }
        stopObserver()
        player?.pause()
        chapterIndex = index
        let track = chapters[index]
        settings.set(index, forKey: "audio.chapter.\(book.id)")

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
        let saved = settings.double(forKey: "audio.position.\(book.id).\(index)")
        if saved > 0 {
            player?.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
            position = saved
        }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.didAdvance(to: time.seconds) }
        }
        player?.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        if isPlaying { pause() }
        else {
            player?.playImmediately(atRate: rate)
            isPlaying = true
            updateNowPlaying()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        saveProgress()
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: max(0, position + seconds))
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        position = clamped
        saveProgress()
        updateNowPlaying()
    }

    func next() { playChapter(min(chapterIndex + 1, max(0, chapters.count - 1))) }
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
        guard chapters.indices.contains(chapterIndex) else { return }
        let track = chapters[chapterIndex]
        guard localURL(for: track) == nil else { return }
        downloadingChapter = track.id
        defer { downloadingChapter = nil }
        do {
            var request = URLRequest(url: track.url)
            request.timeoutInterval = 90
            let (temporary, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw AudioCatalogError.unavailable
            }
            let base = try audioFolder()
            let target = base.appendingPathComponent(safeFilename(for: track))
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: temporary, to: target)
            downloaded.insert(track.id)
            settings.set(Array(downloaded), forKey: downloadKey)
        } catch {
            self.error = "Не удалось сохранить главу. Проверьте подключение."
        }
    }

    func localURL(for track: AudioChapter) -> URL? {
        guard downloaded.contains(track.id),
              let base = try? audioFolder() else { return nil }
        let file = base.appendingPathComponent(safeFilename(for: track))
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private func audioFolder() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audiobooks", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func safeFilename(for track: AudioChapter) -> String {
        // FNV-1a, deterministic and independent of Swift's randomized Hasher.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in track.id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16) + ".mp3"
    }

    private func didAdvance(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        position = seconds
        if let seconds = player?.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
            duration = seconds
        }
        saveProgress()
        updateNowPlaying()
        if duration > 0, seconds >= duration - 0.3, chapterIndex + 1 < chapters.count {
            playChapter(chapterIndex + 1)
        }
    }

    private func saveProgress() {
        guard let book else { return }
        settings.set(position, forKey: "audio.position.\(book.id).\(chapterIndex)")
    }

    private func stopObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
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
