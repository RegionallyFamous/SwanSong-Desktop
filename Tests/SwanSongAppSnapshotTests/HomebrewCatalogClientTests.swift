import Foundation
import SwanSongKit
@testable import SwanSongApp
import XCTest

final class HomebrewCatalogClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CatalogURLProtocol.reset()
    }

    override func tearDown() {
        CatalogURLProtocol.reset()
        super.tearDown()
    }

    func testInitializationDoesNotMakeARequest() {
        _ = makeClient()
        XCTAssertEqual(CatalogURLProtocol.requestCount, 0)
    }

    func testCatalogFetchesExactBodyAndDetachedSignatureWithIndependentRequests() async throws {
        let payload = Data(#"{"schemaVersion":1}"#.utf8)
        let signature = Data(#"{"schemaVersion":1,"signature":"fixture"}"#.utf8)
        CatalogURLProtocol.enqueue(.init(statusCode: 200, body: payload))
        CatalogURLProtocol.enqueue(.init(statusCode: 200, body: signature))

        let bundle = try await makeClient().fetchCatalogBundle()

        XCTAssertEqual(bundle.catalogData, payload)
        XCTAssertEqual(bundle.signatureData, signature)
        XCTAssertEqual(CatalogURLProtocol.requestCount, 2)
        XCTAssertEqual(
            CatalogURLProtocol.requestURLs.map(\.lastPathComponent),
            ["catalog-v1.json", "catalog-v1.sig.json"]
        )
        XCTAssertEqual(CatalogURLProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(
            CatalogURLProtocol.lastRequest?.value(forHTTPHeaderField: "User-Agent"),
            "SwanSong-Homebrew-Catalog/1"
        )
    }

    func testCatalogRejectsNon200Response() async {
        CatalogURLProtocol.enqueue(.init(statusCode: 503, body: Data("no".utf8)))

        await assertNetworkError(.unexpectedResponse) {
            try await self.makeClient().fetchCatalogBundle()
        }
    }

    func testCatalogRejectsAdvertisedOversizeBeforeReadingBody() async {
        CatalogURLProtocol.enqueue(
            .init(
                statusCode: 200,
                headers: ["Content-Length": "1048577"],
                body: Data()
            )
        )

        await assertNetworkError(.responseTooLarge) {
            try await self.makeClient().fetchCatalogBundle()
        }
    }

    func testCatalogRejectsStreamingOversizeWithoutLengthHeader() async {
        CatalogURLProtocol.enqueue(
            .init(
                statusCode: 200,
                body: Data(count: 1_024 * 1_024 + 1)
            )
        )

        await assertNetworkError(.responseTooLarge) {
            try await self.makeClient().fetchCatalogBundle()
        }
    }

    func testDetachedSignatureHasIndependentEightKiBLimit() async {
        CatalogURLProtocol.enqueue(.init(statusCode: 200, body: Data("{}".utf8)))
        CatalogURLProtocol.enqueue(.init(statusCode: 200, body: Data(count: 8 * 1_024 + 1)))

        await assertNetworkError(.responseTooLarge) {
            try await self.makeClient().fetchCatalogBundle()
        }
        XCTAssertEqual(CatalogURLProtocol.requestCount, 2)
    }

    func testAssetRejectsAdvertisedContentLengthMismatch() async {
        CatalogURLProtocol.enqueue(
            .init(
                statusCode: 200,
                headers: ["Content-Length": "3"],
                body: Data([1, 2, 3])
            )
        )

        await assertNetworkError(.byteCountMismatch) {
            try await self.makeClient().fetchAsset(self.asset(byteCount: 4))
        }
    }

    func testAssetRejectsTruncatedAndExcessBodiesWithoutLengthHeader() async {
        CatalogURLProtocol.enqueue(
            .init(statusCode: 200, body: Data([1, 2, 3]))
        )
        await assertNetworkError(.byteCountMismatch) {
            try await self.makeClient().fetchAsset(self.asset(byteCount: 4))
        }

        CatalogURLProtocol.enqueue(
            .init(statusCode: 200, body: Data([1, 2, 3, 4, 5]))
        )
        await assertNetworkError(.byteCountMismatch) {
            try await self.makeClient().fetchAsset(self.asset(byteCount: 4))
        }
    }

    func testSixteenMiBAssetUsesBoundedChunkPathWithoutIteratorScaleCost() async throws {
        let byteCount = 16 * 1_024 * 1_024
        XCTAssertEqual(GameROMValidationPolicy.maximumByteCount, byteCount)
        let payload = Data(repeating: 0x5a, count: byteCount)
        CatalogURLProtocol.enqueue(.init(statusCode: 200, body: payload))
        let clock = ContinuousClock()
        let started = clock.now

        let downloaded = try await makeClient().fetchAsset(
            asset(byteCount: byteCount)
        )

        let elapsed = started.duration(to: clock.now)
        XCTAssertEqual(downloaded, payload)
        XCTAssertLessThan(
            elapsed,
            .seconds(5),
            "A 16 MiB in-memory response should not perform one async iteration per byte"
        )
    }

    func testCancellationStopsAnInFlightCatalogRequest() async throws {
        CatalogURLProtocol.enqueue(
            .init(
                statusCode: 200,
                body: Data("late".utf8),
                delay: 2
            )
        )
        let client = makeClient()
        let task = Task { try await client.fetchCatalogBundle() }

        for _ in 0..<100 where CatalogURLProtocol.requestCount == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(CatalogURLProtocol.requestCount, 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled catalog request must not return bytes")
        } catch is CancellationError {
            // URLSession cancellation is normalized at the client boundary.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    func testProductionAssetTrustRequiresExactFirstPartyReleasePath() {
        let valid = URL(
            string: "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/game-v1.0.0/game.wsc"
        )!
        XCTAssertTrue(
            HomebrewCatalogClient.productionTrustsAssetSourceForTesting(valid)
        )

        let invalid = [
            "http://github.com/RegionallyFamous/swansong-story-forge/releases/download/game-v1.0.0/game.wsc",
            "https://name@github.com/RegionallyFamous/swansong-story-forge/releases/download/game-v1.0.0/game.wsc",
            "https://github.com:444/RegionallyFamous/swansong-story-forge/releases/download/game-v1.0.0/game.wsc",
            "https://github.com/RegionallyFamous/another-repository/releases/download/game-v1.0.0/game.wsc",
            "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/game-v1.0.0/game.wsc?raw=1",
            "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/game-v1.0.0/game.wsc#fragment",
            "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/%2e%2e/game.wsc",
            "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/game-v1.0.0/folder/game.wsc",
            "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/game-v1.0.0/game.zip",
        ].compactMap(URL.init(string:))

        XCTAssertEqual(invalid.count, 9)
        for url in invalid {
            XCTAssertFalse(
                HomebrewCatalogClient.productionTrustsAssetSourceForTesting(url),
                "Unexpectedly trusted \(url.absoluteString)"
            )
        }
    }

    func testInjectedSourceTrustStillPreflightsBeforeTransport() async {
        let foreignAsset = HomebrewCatalogAsset(
            url: URL(string: "https://other.test/game.wsc")!,
            byteCount: 4,
            sha256: String(repeating: "a", count: 64),
            fileExtension: "wsc",
            hardwareModel: .wonderSwanColor
        )

        await assertNetworkError(.invalidSource) {
            try await self.makeClient().fetchAsset(foreignAsset)
        }
        XCTAssertEqual(CatalogURLProtocol.requestCount, 0)
    }

    func testAssetExtensionContractIsCheckedBeforeTransport() async {
        let mismatch = HomebrewCatalogAsset(
            url: URL(string: "https://catalog.test/game.wsc")!,
            byteCount: 4,
            sha256: String(repeating: "a", count: 64),
            fileExtension: "ws",
            hardwareModel: .wonderSwan
        )
        let unsupported = HomebrewCatalogAsset(
            url: URL(string: "https://catalog.test/game.zip")!,
            byteCount: 4,
            sha256: String(repeating: "a", count: 64),
            fileExtension: "zip",
            hardwareModel: .wonderSwanColor
        )

        await assertNetworkError(.invalidSource) {
            try await self.makeClient().fetchAsset(mismatch)
        }
        await assertNetworkError(.invalidSource) {
            try await self.makeClient().fetchAsset(unsupported)
        }
        XCTAssertEqual(CatalogURLProtocol.requestCount, 0)
    }

    func testProductionRedirectTrustAllowsGitHubAssetsButRejectsBoundaryEscapes() {
        XCTAssertTrue(
            HomebrewCatalogClient.productionTrustsRedirectForTesting(
                URL(
                    string: "https://release-assets.githubusercontent.com/github-production-release-asset/123/file?sp=read&sig=token"
                )!
            )
        )
        XCTAssertTrue(
            HomebrewCatalogClient.productionTrustsRedirectForTesting(
                URL(
                    string: "https://raw.githubusercontent.com/RegionallyFamous/swansong-story-forge/main/distribution/catalog-v1.json"
                )!
            )
        )

        let denied = [
            "http://release-assets.githubusercontent.com/file?sig=token",
            "https://example.com/file",
            "https://name@release-assets.githubusercontent.com/file?sig=token",
            "https://release-assets.githubusercontent.com:444/file?sig=token",
            "https://release-assets.githubusercontent.com/file?sig=token#fragment",
            "https://raw.githubusercontent.com/file?unexpected=query",
            "https://release-assets.githubusercontent.com/%2e%2e/file?sig=token",
        ].compactMap(URL.init(string:))

        XCTAssertEqual(denied.count, 7)
        for url in denied {
            XCTAssertFalse(
                HomebrewCatalogClient.productionTrustsRedirectForTesting(url),
                "Unexpectedly trusted redirect \(url.absoluteString)"
            )
        }
    }

    func testTrustedRedirectIsFollowedAndUntrustedRedirectIsCancelled() async throws {
        CatalogURLProtocol.enqueue(
            .init(
                statusCode: 302,
                body: Data(),
                redirectURL: URL(string: "https://catalog.test/final.json")
            )
        )
        CatalogURLProtocol.enqueue(
            .init(statusCode: 200, body: Data("trusted".utf8))
        )
        CatalogURLProtocol.enqueue(
            .init(statusCode: 200, body: Data("signature".utf8))
        )
        let redirectedData = try await makeClient().fetchCatalogBundle()
        XCTAssertEqual(redirectedData.catalogData, Data("trusted".utf8))
        XCTAssertEqual(redirectedData.signatureData, Data("signature".utf8))
        XCTAssertEqual(CatalogURLProtocol.requestCount, 3)

        CatalogURLProtocol.reset()
        CatalogURLProtocol.enqueue(
            .init(
                statusCode: 302,
                body: Data(),
                redirectURL: URL(string: "https://outside.test/file.json")
            )
        )
        await assertNetworkError(.untrustedRedirect) {
            try await self.makeClient().fetchCatalogBundle()
        }
        XCTAssertEqual(CatalogURLProtocol.requestCount, 1)
    }

    private func makeClient() -> HomebrewCatalogClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        return HomebrewCatalogClient(
            testSourceURL: URL(string: "https://catalog.test/catalog-v1.json")!,
            sessionConfiguration: configuration,
            trustsSource: { url in
                url.scheme?.lowercased() == "https"
                    && url.host?.lowercased() == "catalog.test"
                    && url.user == nil
                    && url.password == nil
                    && url.port == nil
            }
        )
    }

    private func asset(byteCount: Int) -> HomebrewCatalogAsset {
        HomebrewCatalogAsset(
            url: URL(string: "https://catalog.test/game.wsc")!,
            byteCount: byteCount,
            sha256: String(repeating: "a", count: 64),
            fileExtension: "wsc",
            hardwareModel: .wonderSwanColor
        )
    }

    private func assertNetworkError<T>(
        _ expected: HomebrewCatalogNetworkError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? HomebrewCatalogNetworkError, expected)
        }
    }
}

private final class CatalogURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let delay: TimeInterval
        let redirectURL: URL?

        init(
            statusCode: Int,
            headers: [String: String] = [:],
            body: Data,
            delay: TimeInterval = 0,
            redirectURL: URL? = nil
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.delay = delay
            self.redirectURL = redirectURL
        }
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var stubs: [Stub] = []
        private var requests: [URLRequest] = []

        func reset() {
            lock.lock()
            stubs = []
            requests = []
            lock.unlock()
        }

        func enqueue(_ stub: Stub) {
            lock.lock()
            stubs.append(stub)
            lock.unlock()
        }

        func takeStub(for request: URLRequest) -> Stub? {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            guard !stubs.isEmpty else { return nil }
            return stubs.removeFirst()
        }

        var requestCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return requests.count
        }

        var lastRequest: URLRequest? {
            lock.lock()
            defer { lock.unlock() }
            return requests.last
        }

        var requestURLs: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return requests.compactMap(\.url)
        }
    }

    private static let storage = Storage()
    private var pendingDelivery: DispatchWorkItem?

    static var requestCount: Int { storage.requestCount }
    static var lastRequest: URLRequest? { storage.lastRequest }
    static var requestURLs: [URL] { storage.requestURLs }

    static func reset() {
        storage.reset()
    }

    static func enqueue(_ stub: Stub) {
        storage.enqueue(stub)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = Self.storage.takeStub(for: request) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            if let redirectURL = stub.redirectURL {
                self.client?.urlProtocol(
                    self,
                    wasRedirectedTo: URLRequest(url: redirectURL),
                    redirectResponse: response
                )
                return
            }
            self.client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            if !stub.body.isEmpty {
                self.client?.urlProtocol(self, didLoad: stub.body)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        pendingDelivery = work
        if stub.delay > 0 {
            DispatchQueue.global().asyncAfter(
                deadline: .now() + stub.delay,
                execute: work
            )
        } else {
            work.perform()
        }
    }

    override func stopLoading() {
        pendingDelivery?.cancel()
        pendingDelivery = nil
    }
}
