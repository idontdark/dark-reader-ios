import XCTest
import UIKit
@testable import DarkReader

private final class SlowCoverProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests = 0
    static var png = Data()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "covers.qa.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let bytes = Self.png
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline:.now()+0.3) {
            self.client?.urlProtocol(self,didReceive:HTTPURLResponse(url:self.request.url!,statusCode:200,httpVersion:nil,
                                                                   headerFields:["Content-Type":"image/png"])!,cacheStoragePolicy:.notAllowed)
            self.client?.urlProtocol(self,didLoad:bytes)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

final class CoverCacheTests: XCTestCase {
    @MainActor func testSlowCoverRequestsCoalesceAndPersistAcrossCacheInstances() async throws {
        let renderer = UIGraphicsImageRenderer(size:CGSize(width:16,height:16))
        let png = renderer.pngData { context in UIColor.purple.setFill(); context.fill(CGRect(x:0,y:0,width:16,height:16)) }
        SlowCoverProtocol.lock.lock();SlowCoverProtocol.requests = 0;SlowCoverProtocol.png = png;SlowCoverProtocol.lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowCoverProtocol.self]
        let session = URLSession(configuration:configuration)
        defer { session.invalidateAndCancel() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = URL(string:"https://covers.qa.invalid/cover.png")!
        let cache = CoverCache(session:session,folder:folder)
        async let first = cache.data(for:url)
        async let second = cache.data(for:url)
        let bytes = try await [first,second]
        XCTAssertEqual(bytes,[png,png])
        XCTAssertEqual(SlowCoverProtocol.requests,1)
        _ = try await cache.data(for:url)
        let restored = CoverCache(session:session,folder:folder)
        _ = try await restored.data(for:url)
        XCTAssertEqual(SlowCoverProtocol.requests,1,"Memory and disk hits must not start another slow request")
        print("COVER_CACHE_VERIFIED coalesced=2 network=1 disk-restored=true delay=300ms")
    }
}
