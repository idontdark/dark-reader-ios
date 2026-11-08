import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Runs the production OPDS client and query policy on macOS, without an iOS simulator.
final class CatalogFixtureProtocol: URLProtocol {
    static var pages: [String: (Int, String)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "catalog.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = Self.pages[request.url!.path] ?? (404, "missing")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url:request.url!,statusCode:response.0,httpVersion:nil,headerFields:["Content-Type":"application/atom+xml"])!, cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CatalogRegressions {
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: " + name) }
        print("PASS: " + name)
    }
    static func feed(_ id: String, next: String? = nil) -> String {
        """
        <feed xmlns="http://www.w3.org/2005/Atom">
        \(next.map { "<link rel=\"next\" href=\"\($0)\"/>" } ?? "")
        <entry><id>\(id)</id><title>Книга \(id)</title><author><name>Автор</name></author>
        <summary type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>Первый абзац.</p><p>Второй абзац.</p></div></summary>
        <link rel="http://opds-spec.org/acquisition" type="application/epub+zip" href="/\(id).epub"/></entry></feed>
        """
    }
    static func main() async throws {
        check(SearchQueryPolicy.variants("Praise").contains("Похвали меня"), "translated title alias")
        check(SearchQueryPolicy.variants("Ритуал Шантель Тессье").contains("Лорд и Избранная"), "published edition title")
        check(SearchQueryPolicy.normalized("Ёж — «Книга»") == "еж книга", "punctuation and yo normalization")
        check(SearchQueryPolicy.score(title:"Синие бабочки [litres]",author:"Тодд Джек",query:"Синие бабочки") >
              SearchQueryPolicy.score(title:"Жёлтые бабочки",author:"Другой автор",query:"Синие бабочки"), "exact title ranks first")
        check(SearchQueryPolicy.score(title:"Praise",author:"Сара Кейт",query:"Похвали меня") == 10_000, "original and translation have equal identity rank")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogFixtureProtocol.self]
        let session = URLSession(configuration:configuration)
        defer { session.invalidateAndCancel() }
        let client = OPDSClient(searchEndpoint:"https://catalog.test/one",queryParameter:"q",session:session)
        CatalogFixtureProtocol.pages = ["/one":(200,feed("a",next:"/two")),"/two":(200,feed("b",next:"/one"))]
        let books = try await client.browse(URL(string:"https://catalog.test/one")!,maxPages:5)
        check(books.map(\.id) == ["a","b"], "next page followed and pagination cycle stopped")
        check(books[0].summary?.contains("Второй абзац.") == true, "nested XHTML description retained")
        check(books[0].epubURL?.absoluteString == "https://catalog.test/a.epub", "relative acquisition URL resolved")
        CatalogFixtureProtocol.pages["/two"] = (200,feed("a"))
        let duplicates = try await client.browse(URL(string:"https://catalog.test/one")!,maxPages:5)
        check(duplicates.count == 1, "duplicate editions removed across pages")
        CatalogFixtureProtocol.pages["/two"] = (503,"unavailable")
        let partial = try await client.browse(URL(string:"https://catalog.test/one")!,maxPages:5)
        check(partial.map(\.id) == ["a"], "later page failure preserves available results")
        CatalogFixtureProtocol.pages["/one"] = (503,"unavailable")
        do {
            _ = try await client.browse(URL(string:"https://catalog.test/one")!,maxPages:5)
            fatalError("First page failure was swallowed")
        } catch { print("PASS: unavailable source throws rather than returning an empty search") }
    }
}
