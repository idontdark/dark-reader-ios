import Foundation

/// Two verified OPDS endpoints, exposed as one source. Never disables TLS verification.
actor FlibustaCatalog {
    static let shared = FlibustaCatalog()
    private var preferredHost = "flibusta.is"
    private let hosts = ["flibusta.is", "flibusta.site"]

    func search(_ query: String, mode: String, onPage: CatalogSearchProgress? = nil) async throws -> [CatalogBook] {
        let order = [preferredHost] + hosts.filter { $0 != preferredHost }
        var lastError: Error = ReaderError.invalidCatalogURL
        for host in order {
            try Task.checkCancellation()
            do {
                let type = mode == "author" ? "authors" : "books"
                let books = try await OPDSClient(searchEndpoint: "https://\(host)/opds/search?searchType=\(type)",
                                                 queryParameter: "searchTerm").search(query, onPage: onPage)
                preferredHost = host
                return books
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        throw lastError
    }
}
