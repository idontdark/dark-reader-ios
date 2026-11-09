import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum SourceKind: String, Codable, CaseIterable, Sendable { case books, audio }
enum SourceAdapter: String, Codable, Sendable { case flibusta, gutenberg, archiveBooks, librivox, archiveAudio, knigavuhe, akniga, html }
struct SourceDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let domain: String
    let kind: SourceKind
    let adapter: SourceAdapter
    let defaultEnabled: Bool
    var searchConfiguration: SourceSearchForm? = nil
    var homepage: URL { URL(string: "https://" + domain + "/")! }
}
struct SourceSearchForm: Codable, Hashable, Sendable {
    let url: URL
    let method: String
    let field: String
    var hidden: [String: String] = [:]
    func request(_ query: String) -> URLRequest {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let values = hidden.merging([field: query], uniquingKeysWith: { _, new in new })
        let items = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request: URLRequest
        if method.lowercased() == "post" {
            var body = URLComponents(); body.queryItems = items
            request = URLRequest(url: url); request.httpMethod = "POST"
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else {
            parts.queryItems = (parts.queryItems ?? []) + items
            request = URLRequest(url: parts.url!)
        }
        return request
    }
}
enum SourceCatalog {
    static let all: [SourceDescriptor] = generated
    static func source(_ id: String) -> SourceDescriptor? { all.first { $0.id == id } }
    static func identifier(_ domain: String, kind: SourceKind) -> String { kind.rawValue + ":" + domain }
}

struct BookOffer: Identifiable, Codable, Hashable, Sendable {
    let sourceID: String
    let sourceName: String
    let pageURL: URL
    var fileURL: URL?
    var format: String?
    var id: String { sourceID + ":" + (fileURL ?? pageURL).absoluteString }
}
struct AudioEdition: Identifiable, Codable, Hashable, Sendable {
    let providerID: String
    let pageURL: URL
    let narrator: String?
    let year: Int?
    let durationSeconds: Double?
    var nativeID: String? = nil
    var sourceCode: String? = nil
    var streamURL: URL? = nil
    var feedURL: URL? = nil
    var id: String { providerID + ":" + pageURL.absoluteString }
}
enum SourceHealthState: String, Codable, Sendable { case working, partial, unverified }
struct SourceHealthResult: Codable, Sendable {
    let state: SourceHealthState
    let checkedAt: Date
    let domainReachable: Bool
    let searchSucceeded: Bool
    let detailSucceeded: Bool
    let downloadSucceeded: Bool
    let playbackSucceeded: Bool
    let message: String
}

/// Failed checks never mutate enabled sources. Legacy custom catalogs are removed
/// at migration by the owner's explicit instruction, without touching library data.
enum SourcePreferences {
    static let key = "sources.enabled.v1"
    static let healthKey = "sources.health.v1"
    static let legacyKeys = ["savedOPDSCatalogs", "preferredAudioCatalogID", "catalogURL", "catalogQueryParameter", "catalogProvider"]
    static func migrate(_ defaults: UserDefaults = .standard) {
        if !defaults.bool(forKey: "sources.migrated.v1"), let raw = defaults.string(forKey: "preferredGenresJSON")?.data(using: .utf8),
           var genres = try? JSONDecoder().decode([String].self, from: raw), genres.contains("fantasy"), !genres.contains("science_fiction") {
            genres.append("science_fiction")
            if let data = try? JSONEncoder().encode(genres) { defaults.set(String(decoding: data, as: UTF8.self), forKey: "preferredGenresJSON") }
        }
        for key in legacyKeys { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: "sources.migrated.v1")
    }
    static func enabled(_ kind: SourceKind, defaults: UserDefaults = .standard) -> [SourceDescriptor] {
        let explicit = (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
        let oldDisabled = Set((defaults.string(forKey: "disabledAudioSources") ?? "").split(separator: ",").map(String.init))
        return SourceCatalog.all.filter { source in
            guard source.kind == kind else { return false }
            if let selected = explicit[source.id] { return selected }
            let legacy = ["librivox.org": "librivox", "archive.org": "archive", "knigavuhe.org": "knigavuhe", "akniga.org": "akniga"][source.domain]
            return source.defaultEnabled && !(kind == .audio && legacy.map { oldDisabled.contains($0) } == true)
        }
    }
    static func set(_ source: SourceDescriptor, enabled: Bool, defaults: UserDefaults = .standard) {
        var explicit = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
        explicit[source.id] = enabled
        defaults.set(try? JSONEncoder().encode(explicit), forKey: key)
    }
    static func health(_ defaults: UserDefaults = .standard) -> [String: SourceHealthResult] {
        defaults.data(forKey: healthKey).flatMap { try? JSONDecoder().decode([String: SourceHealthResult].self, from: $0) } ?? [:]
    }
    static func saveHealth(_ result: SourceHealthResult, source: SourceDescriptor, defaults: UserDefaults = .standard) {
        var values = health(defaults); values[source.id] = result
        defaults.set(try? JSONEncoder().encode(values), forKey: healthKey)
    }
}
