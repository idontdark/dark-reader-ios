import Foundation

enum DownloadState: String, Codable, Sendable {
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
struct AudioDownloadJob: Identifiable, Codable, Sendable {
    let book: AudioBook
    var tracks: [AudioChapter]
    var state: DownloadState = .queued
    var id: String { book.id }
}

/// Books and audio share one transfer budget. Waiting callers can be cancelled
/// without occupying a slot or blocking unrelated queued work.
actor MediaTransferGate {
    static let shared = MediaTransferGate(limit: 3)
    private let limit: Int
    private var active = Set<UUID>()
    private var waiting: [(UUID, CheckedContinuation<UUID, Error>)] = []
    init(limit: Int) { self.limit = max(1, limit) }
    func acquire() async throws -> UUID {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if active.count < limit { active.insert(id); continuation.resume(returning: id) }
                else { waiting.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func release(_ id: UUID) {
        guard active.remove(id) != nil else { return }
        if !waiting.isEmpty {
            let next = waiting.removeFirst(); active.insert(next.0); next.1.resume(returning: next.0)
        }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
}
