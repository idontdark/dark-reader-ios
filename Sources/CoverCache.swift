import SwiftUI
import UIKit
import CryptoKit
import ImageIO

actor CoverCache {
    static let shared = CoverCache()
    private var memory: [URL: Data] = [:]
    private var pending: [URL: Task<Data, Error>] = [:]
    private let thumbnails = NSCache<NSString, UIImage>()
    private let folder: URL
    private let session: URLSession
    init(session: URLSession = .shared, folder: URL? = nil) {
        self.session = session
        self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
        thumbnails.totalCostLimit = 24 * 1024 * 1024
    }

    func data(for url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        if let data = memory[url] { return data }
        if let task = pending[url] { return try await task.value }
        let filename = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let target = folder.appendingPathComponent(filename)
        let task = Task<Data, Error> {
            if let cached = try? Data(contentsOf: target), CGImageSourceCreateWithData(cached as CFData, nil) != nil { return cached }
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("image/webp,image/jpeg,image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 8_000_000, CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw ReaderError.noResults }
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

    func image(for url: URL, maxPixelSize: Int) async throws -> UIImage {
        let size = min(1600, max(64, maxPixelSize))
        let key = (url.absoluteString + "#" + String(size)) as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let data = try await data(for: url)
        try Task.checkCancellation()
        if let cached = thumbnails.object(forKey: key) { return cached }
        // ImageIO decodes only the pixels required by this card, on the cache actor.
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ReaderError.noResults }
        let image = UIImage(cgImage: cgImage)
        thumbnails.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    func prefetch(_ urls: [URL]) async {
        // Only a handful of near-visible cards, never an entire remote catalog.
        await withTaskGroup(of: Void.self) { group in
            for url in Array(Set(urls)).prefix(8) {
                group.addTask { _ = try? await self.data(for: url) }
            }
        }
    }
}

struct CachedCover<Content: View, Placeholder: View>: View {
    let url: URL?
    var pointSize: CGFloat = 180
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: UIImage?
    @State private var loadedURL:URL?
    @State private var failed=false
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        Group {
            if let loaded { content(Image(uiImage: loaded)) }
            else { placeholder().overlay {if url != nil && !failed {ProgressView().controlSize(.mini).tint(ReaderStyle.secondary)}} }
        }
        .task(id: url) {
            if loaded != nil && loadedURL == url {return}
            loaded = nil
            failed=false
            guard let url else {failed=true;return}
            do {
                let image=try await CoverCache.shared.image(for:url,maxPixelSize:Int(ceil(pointSize * displayScale)))
                try Task.checkCancellation()
                loaded=image;loadedURL=url;failed=false
            } catch {if !Task.isCancelled {failed=true}}
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
