import SwiftUI
import UIKit
import CryptoKit

actor CoverCache {
    static let shared = CoverCache()
    private var memory: [URL: Data] = [:]
    private var pending: [URL: Task<Data, Error>] = [:]
    private let folder: URL
    private let session: URLSession
    init(session: URLSession = .shared, folder: URL? = nil) {
        self.session = session
        self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
    }

    func data(for url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        if let data = memory[url] { return data }
        if let task = pending[url] { return try await task.value }
        let filename = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let target = folder.appendingPathComponent(filename)
        let task = Task<Data, Error> {
            if let cached = try? Data(contentsOf: target), UIImage(data: cached) != nil { return cached }
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 8_000_000, UIImage(data: data) != nil else { throw ReaderError.noResults }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Bound disk cache. Covers can always be fetched again.
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            if files.count > 250 {
                for file in files.sorted(by: {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
                    ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }).prefix(50) { try? FileManager.default.removeItem(at: file) }
            }
            try? data.write(to: target, options: .atomic)
            return data
        }
        pending[url] = task
        defer { pending[url] = nil }
        let data = try await task.value
        if memory.count >= 60 || memory.values.reduce(0, { $0 + $1.count }) + data.count > 24_000_000 { memory.removeAll() }
        memory[url] = data
        return data
    }
}

struct CachedCover<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: UIImage?
    var body: some View {
        Group {
            if let loaded { content(Image(uiImage: loaded)) }
            else { placeholder() }
        }
        .task(id: url) {
            loaded = nil
            guard let url, let data = try? await CoverCache.shared.data(for: url),
                  !Task.isCancelled else { return }
            loaded = UIImage(data: data)
        }
    }
}

enum CoverSize {
    static func url(_ url: URL?, detailed: Bool) -> URL? {
        guard detailed, let url else { return url }
        return URL(string: url.absoluteString.replacingOccurrences(of: "-M.jpg", with: "-L.jpg")
            .replacingOccurrences(of: ".cover.medium.jpg", with: ".cover.large.jpg")) ?? url
    }
}
