import Foundation

struct AudioWebCatalog: Identifiable {
    let id = UUID()
    let url: URL
    static func search(host: String, query: String) -> AudioWebCatalog? {
        let path = host == "akniga.org" ? "/search/books/" : "/search/"
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = host
        parts.path = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/" : path
        if parts.path != "/" { parts.queryItems = [URLQueryItem(name: "q", value: query)] }
        return parts.url.map { AudioWebCatalog(url: $0) }
    }
}

