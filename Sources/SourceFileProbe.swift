import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Checks a short prefix and cancels the transfer, including when a server ignores
/// Range. A health check never downloads an entire book or audio chapter.
final class SourceFileProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Kind: Equatable { case book, audio, audioFile }
    private let kind: Kind
    private var continuation: CheckedContinuation<Bool, Never>?
    private var bytes = Data()
    private var validStatus = false
    private var session: URLSession?
    private let lock = NSLock()
    init(kind: Kind) { self.kind = kind }
    static func check(_ url: URL, kind: Kind) async -> Bool {
        guard url.scheme == "https" else { return false }
        let probe = SourceFileProbe(kind: kind)
        return await withCheckedContinuation { continuation in probe.start(url, continuation: continuation) }
    }
    private func start(_ url: URL, continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8; configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url); request.setValue(kind == .book ? "bytes=0-4095" : "bytes=0-63", forHTTPHeaderField: "Range")
        session.dataTask(with: request).resume()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, [200, 206].contains(response.statusCode), response.url?.scheme == "https" else {
            completionHandler(.cancel); finish(false); return
        }
        validStatus = true; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let limit = kind == .book ? 4096 : 64
        bytes.append(data.prefix(max(0, limit - bytes.count)))
        if accepted() { finish(true) }
        else if bytes.count >= limit { finish(false) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error == nil && accepted()) }
    private func accepted() -> Bool {
        guard validStatus else { return false }
        switch kind {
        case .book:
            return bytes.starts(with: [0x50, 0x4B]) || bytes.starts(with: Data("%PDF".utf8)) ||
                String(decoding: bytes, as: UTF8.self).contains("FictionBook") || bytes.starts(with: Data("{\\rtf".utf8)) || (bytes.count >= 68 && String(decoding: bytes[60..<68], as: UTF8.self) == "BOOKMOBI")
        case .audio, .audioFile:
            return bytes.starts(with: Data("ID3".utf8)) || (bytes.count > 2 && bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0) ||
                (bytes.count >= 8 && String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp") ||
                bytes.starts(with: Data("RIFF".utf8)) || bytes.starts(with: Data("fLaC".utf8)) || (kind == .audio && bytes.starts(with: Data("#EXTM3U".utf8)))
        }
    }
    private func finish(_ result: Bool) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; lock.unlock()
        guard let continuation else { return }
        session?.invalidateAndCancel(); session = nil; continuation.resume(returning: result)
    }
    static func playable(_ url: URL) async -> Bool {
        guard await check(url, kind: .audio) else { return false }
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: url)
        do {
            let playable = try await asset.load(.isPlayable)
            let protected = try await asset.load(.hasProtectedContent)
            return playable && !protected
        }
        catch { return false }
        #else
        return false
        #endif
    }
}
