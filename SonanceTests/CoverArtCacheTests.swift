import XCTest
import AppKit
@testable import Sonance

/// Proves the M1 acceptance criterion that repeated requests for the same `(coverArt id, size)`
/// trigger exactly one network fetch — subsequent reads come from the in-memory and on-disk tiers.
final class CoverArtCacheTests: XCTestCase {
    private var tempDirName: String = ""

    override func setUp() async throws {
        try await super.setUp()
        // Each test runs against its own disk cache directory so order does not matter.
        tempDirName = "SonanceTests/covers-\(UUID().uuidString)"
        StubURLProtocol.reset()
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        try await super.tearDown()
    }

    func testSecondLookupIsMemoryHit() async {
        let (cache, client, _) = makeCacheAndClient()
        StubURLProtocol.responder = { _ in Self.solidPNGData(red: true) }

        let first = await cache.image(for: "abc", size: 300, client: client)
        XCTAssertNotNil(first)

        let second = await cache.image(for: "abc", size: 300, client: client)
        XCTAssertNotNil(second)

        let stats = await cache.diagnostics()
        XCTAssertEqual(stats.networkLoads, 1, "second request must not refetch")
        XCTAssertEqual(stats.memoryHits, 1, "second request should be a memory hit")
        XCTAssertEqual(StubURLProtocol.callCount, 1, "URLSession should be called only once")
    }

    func testFreshCacheReadsFromDiskOnSecondInstance() async throws {
        let dirName = tempDirName  // shared across the two cache instances
        let session = Self.stubbedSession()
        let creds = ServerCredentials(serverURL: "http://example.test", username: "u", password: "p")
        let client = SubsonicClient(credentials: creds, urlSession: session)
        StubURLProtocol.responder = { _ in Self.solidPNGData(red: true) }

        let warmCache = CoverArtCache(directoryName: dirName)
        _ = await warmCache.image(for: "abc", size: 300, client: client)
        XCTAssertEqual(StubURLProtocol.callCount, 1)

        // Simulate relaunch: fresh actor, fresh in-memory cache, same on-disk directory.
        let coldCache = CoverArtCache(directoryName: dirName)
        let img = await coldCache.image(for: "abc", size: 300, client: client)
        XCTAssertNotNil(img)
        XCTAssertEqual(StubURLProtocol.callCount, 1, "disk hit must not trigger another network fetch")

        let stats = await coldCache.diagnostics()
        XCTAssertEqual(stats.diskHits, 1)
        XCTAssertEqual(stats.networkLoads, 0)

        await coldCache.clear()
    }

    func testConcurrentRequestsForSameKeyDedupe() async {
        let (cache, client, _) = makeCacheAndClient()
        // Slow-ish response so multiple awaiters overlap.
        StubURLProtocol.responder = { _ in
            // 50 ms simulated latency
            Thread.sleep(forTimeInterval: 0.05)
            return Self.solidPNGData(red: false)
        }

        async let a = cache.image(for: "shared", size: 300, client: client)
        async let b = cache.image(for: "shared", size: 300, client: client)
        async let c = cache.image(for: "shared", size: 300, client: client)
        let results = await (a, b, c)
        XCTAssertNotNil(results.0)
        XCTAssertNotNil(results.1)
        XCTAssertNotNil(results.2)

        XCTAssertEqual(StubURLProtocol.callCount, 1, "in-flight requests must collapse to one network call")
    }

    func testDifferentSizesAreCachedIndependently() async {
        let (cache, client, _) = makeCacheAndClient()
        StubURLProtocol.responder = { _ in Self.solidPNGData(red: true) }

        _ = await cache.image(for: "abc", size: 96, client: client)
        _ = await cache.image(for: "abc", size: 300, client: client)
        XCTAssertEqual(StubURLProtocol.callCount, 2)

        // Second pass: both sizes should be memory hits.
        _ = await cache.image(for: "abc", size: 96, client: client)
        _ = await cache.image(for: "abc", size: 300, client: client)
        XCTAssertEqual(StubURLProtocol.callCount, 2)
    }

    func testCoverArtURLIsStableAcrossCalls() {
        let creds = ServerCredentials(serverURL: "http://example.test", username: "u", password: "p")
        let client = SubsonicClient(credentials: creds)
        let a = client.coverArtURL(id: "abc", size: 300)
        let b = client.coverArtURL(id: "abc", size: 300)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b, "coverArtURL must be stable across calls on the same client instance")

        let streamA = client.streamURL(id: "abc")
        let streamB = client.streamURL(id: "abc")
        XCTAssertEqual(streamA, streamB, "streamURL must also be stable")

        // Different clients (e.g. signed in twice) regenerate salt+token.
        let other = SubsonicClient(credentials: creds)
        XCTAssertNotEqual(a, other.coverArtURL(id: "abc", size: 300))
    }

    // MARK: - Helpers

    private func makeCacheAndClient() -> (CoverArtCache, SubsonicClient, URLSession) {
        let session = Self.stubbedSession()
        let creds = ServerCredentials(serverURL: "http://example.test", username: "u", password: "p")
        let client = SubsonicClient(credentials: creds, urlSession: session)
        let cache = CoverArtCache(directoryName: tempDirName)
        return (cache, client, session)
    }

    private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func solidPNGData(red: Bool) -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        let color: NSColor = red ? .red : .blue
        color.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }
}

/// Test-only stub. Intercepts every request and returns whatever `responder` produces.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: ((URLRequest) -> Data?)?
    nonisolated(unsafe) private static var _callCount = 0
    private static let lock = NSLock()

    static var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _callCount = 0
        responder = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._callCount += 1
        let responder = Self.responder
        Self.lock.unlock()

        let data = responder?(request) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
