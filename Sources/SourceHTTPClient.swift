import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum SourceError: LocalizedError {
    case unavailable, unexpectedContent, noSearch, noEnabledSources
    var errorDescription: String? {
        switch self {
        case .unavailable: "Источник сейчас не отвечает. Остальные источники продолжают работать."
        case .unexpectedContent: "Источник вернул неподдерживаемые данные."
        case .noSearch: "Поиск этого источника пока не подтверждён."
        case .noEnabledSources: "Включите хотя бы один источник в настройках."
        }
    }
}
struct SourceResponse: Sendable { let data: Data; let url: URL; let contentType: String }
actor SourceHTTPClient {
    static let shared = SourceHTTPClient()
    private var cache: [String: (Date, SourceResponse)] = [:]
    private var nextRequest: [String: Date] = [:]
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func load(_ original: URLRequest, cached: Bool = true) async throws -> SourceResponse {
        guard let url = original.url, url.scheme == "https", let host = url.host else { throw SourceError.unavailable }
        let key = (original.httpMethod ?? "GET") + url.absoluteString + (original.httpBody?.base64EncodedString() ?? "")
        if cached, let (date, response) = cache[key], Date().timeIntervalSince(date) < 300 { return response }
        let scheduled = max(Date(), nextRequest[host] ?? .distantPast)
        nextRequest[host] = scheduled.addingTimeInterval(host == "librivox.org" ? 1 : 0.4)
        let delay = scheduled.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        var request = original; request.timeoutInterval = 12
        request.setValue("DarkReader/1.0 (+https://idontdark.github.io/dark-reader/)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/html,application/atom+xml,application/xml;q=0.9", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = http.url, final.scheme == "https", data.count <= 8_000_000 else { throw SourceError.unavailable }
        let result = SourceResponse(data: data, url: final, contentType: http.mimeType ?? "")
        if cache.count > 24 || cache.values.reduce(0, { $0 + $1.1.data.count }) + data.count > 24_000_000 { cache.removeAll() }
        cache[key] = (Date(), result)
        return result
    }
    func load(_ url: URL, cached: Bool = true) async throws -> SourceResponse { try await load(URLRequest(url: url), cached: cached) }
    func json(_ url: URL) async throws -> [String: Any] {
        let response = try await load(url)
        guard let result = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { throw SourceError.unexpectedContent }
        return result
    }
    static func html(_ response: SourceResponse) -> String? {
        String(data: response.data, encoding: .utf8) ?? String(data: response.data, encoding: .windowsCP1251)
    }
}
