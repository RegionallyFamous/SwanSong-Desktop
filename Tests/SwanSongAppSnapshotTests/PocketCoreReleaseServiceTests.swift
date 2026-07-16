import Foundation
import SwanSongKit
import XCTest
@testable import SwanSongApp

@MainActor
final class PocketCoreReleaseServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PocketReleaseURLProtocol.reset()
    }

    override func tearDown() {
        PocketReleaseURLProtocol.reset()
        super.tearDown()
    }

    func testInitializationAndPageConstructionStayOffline() {
        _ = makeService()
        _ = PocketCoreSetupModel(service: makeService())
        XCTAssertEqual(PocketReleaseURLProtocol.requestCount, 0)
    }

    func testMissingOfficialReleaseReturnsUnavailable() async throws {
        PocketReleaseURLProtocol.respond(statusCode: 404, body: Data("{}".utf8))

        let release = try await makeService().latestRelease()

        XCTAssertNil(release)
        XCTAssertEqual(PocketReleaseURLProtocol.requestCount, 1)
        XCTAssertEqual(
            PocketReleaseURLProtocol.lastRequest?.url,
            PocketCoreReleaseService.latestReleaseURL
        )
        XCTAssertEqual(
            PocketReleaseURLProtocol.lastRequest?.value(forHTTPHeaderField: "User-Agent"),
            "SwanSong-Desktop"
        )
    }

    func testMutableStableReleaseFailsBeforeAnyAssetRequest() async {
        let body = Data(
            #"{"tag_name":"1.0.0","html_url":"https://github.com/RegionallyFamous/swansong-core/releases/tag/1.0.0","draft":false,"prerelease":false,"immutable":false,"assets":[]}"#
                .utf8
        )
        PocketReleaseURLProtocol.respond(statusCode: 200, body: body)

        do {
            _ = try await makeService().latestRelease()
            XCTFail("A mutable GitHub release must not be offered")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("immutable"))
        }
        XCTAssertEqual(PocketReleaseURLProtocol.requestCount, 1)
    }

    func testOversizedReleaseMetadataIsStoppedAtTheStreamingLimit() async {
        PocketReleaseURLProtocol.respond(
            statusCode: 200,
            body: Data(repeating: 0x20, count: 2 * 1_024 * 1_024 + 1)
        )

        do {
            _ = try await makeService().latestRelease()
            XCTFail("Oversized release metadata must be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("safety limit"))
        }
        XCTAssertEqual(PocketReleaseURLProtocol.requestCount, 1)
    }

    func testProductionRedirectPolicyOnlyAllowsExpectedGitHubHosts() {
        XCTAssertTrue(
            PocketCoreReleaseService.productionTrustsRedirectForTesting(
                URL(
                    string: "https://release-assets.githubusercontent.com/github-production-release-asset/123/core.zip?token=example"
                )!
            )
        )
        XCTAssertTrue(
            PocketCoreReleaseService.productionTrustsRedirectForTesting(
                URL(string: "https://github.com/RegionallyFamous/swansong-core/releases/download/v1/core.zip")!
            )
        )
        XCTAssertFalse(
            PocketCoreReleaseService.productionTrustsRedirectForTesting(
                URL(string: "https://downloads.example.com/core.zip")!
            )
        )
        XCTAssertFalse(
            PocketCoreReleaseService.productionTrustsRedirectForTesting(
                URL(string: "https://api.github.com/repos/example?redirect=1")!
            )
        )
        XCTAssertFalse(
            PocketCoreReleaseService.productionTrustsRedirectForTesting(
                URL(string: "https://github.com/RegionallyFamous/%2e%2e/other/core.zip")!
            )
        )
    }

    func testVerifiedImmutableReleaseIsAssembledFromBoundedAssets() async throws {
        let fixture = makeValidReleaseFixture()
        PocketReleaseURLProtocol.respond(
            to: PocketCoreReleaseService.latestReleaseURL,
            statusCode: 200,
            body: fixture.release
        )
        PocketReleaseURLProtocol.respond(
            to: fixture.manifestURL,
            statusCode: 200,
            body: fixture.manifest
        )
        PocketReleaseURLProtocol.respond(
            to: fixture.checksumsURL,
            statusCode: 200,
            body: fixture.checksums
        )

        let availableRelease = try await makeService().latestRelease()
        let release = try XCTUnwrap(availableRelease)

        XCTAssertEqual(release.metadata.version, "1.2.3")
        XCTAssertEqual(release.metadata.packageFilename, fixture.packageFilename)
        XCTAssertEqual(release.packageDownloadURL, fixture.packageURL)
        XCTAssertEqual(PocketReleaseURLProtocol.requestCount, 3)
    }

    func testPackageDownloadRejectsAnIncompleteTransferBeforeExtraction() async {
        let packageURL = URL(
            string: "https://github.com/RegionallyFamous/swansong-core/releases/download/v1.2.3/core.zip"
        )!
        PocketReleaseURLProtocol.respond(
            to: packageURL,
            statusCode: 200,
            body: Data([0x50, 0x4B])
        )
        let release = AvailablePocketCoreRelease(
            metadata: PocketCoreReleaseMetadata(
                version: "1.2.3",
                releaseDate: "2026-07-16",
                sourceCommit: String(repeating: "a", count: 40),
                packageFilename: "core.zip",
                packageByteCount: 3,
                packageSHA256: String(repeating: "b", count: 64)
            ),
            releaseTag: "v1.2.3",
            packageDownloadURL: packageURL,
            releasePageURL: URL(
                string: "https://github.com/RegionallyFamous/swansong-core/releases/tag/v1.2.3"
            )!
        )

        do {
            _ = try await makeService().downloadPackage(release)
            XCTFail("An incomplete package transfer must not reach extraction")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("did not match"))
        }
        XCTAssertEqual(PocketReleaseURLProtocol.requestCount, 1)
    }

    private func makeService() -> PocketCoreReleaseService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PocketReleaseURLProtocol.self]
        return PocketCoreReleaseService(
            session: URLSession(configuration: configuration)
        )
    }

    private func makeValidReleaseFixture() -> (
        release: Data,
        manifest: Data,
        checksums: Data,
        manifestURL: URL,
        checksumsURL: URL,
        packageURL: URL,
        packageFilename: String
    ) {
        let packageFilename = "RegionallyFamous.SwanSong_1.2.3_2026-07-16.zip"
        let packageHash = String(repeating: "b", count: 64)
        let manifest = Data(
            """
            {
              "release_manifest": {
                "magic": "SWAN_SONG_STABLE_RELEASE_V1",
                "core_id": "RegionallyFamous.SwanSong",
                "repository_url": "https://github.com/RegionallyFamous/swansong-core",
                "version": "1.2.3",
                "date_release": "2026-07-16",
                "source_commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "release_policy": {
                  "magic": "SWAN_SONG_RELEASE_POLICY_V2",
                  "core_id": "RegionallyFamous.SwanSong",
                  "repository_url": "https://github.com/RegionallyFamous/swansong-core",
                  "identity_authorized": true,
                  "distribution_and_licensing_authorized": true
                },
                "verification": {
                  "both_quartus_audits_pass": true,
                  "distinct_signed_quartus_runs": true,
                  "rbf_and_build_id_reproduced": true,
                  "hardware_qa_accepted": true,
                  "known_title_compatibility_accepted": true,
                  "release_evidence_v2_validated": true,
                  "release_package_validated": true,
                  "release_stage_applied_and_reverified": true,
                  "corresponding_source_archived": true
                },
                "artifacts": {
                  "\(packageFilename)": {
                    "filename": "\(packageFilename)",
                    "size": 3,
                    "sha256": "\(packageHash)"
                  }
                }
              }
            }
            """.utf8
        )
        let checksums = Data(
            """
            \(packageHash)  \(packageFilename)
            \(PocketCoreReleaseVerifier.digest(manifest))  release-manifest.json

            """.utf8
        )
        let base = "https://github.com/RegionallyFamous/swansong-core/releases/download/v1.2.3"
        let manifestURL = URL(string: "\(base)/release-manifest.json")!
        let checksumsURL = URL(string: "\(base)/SHA256SUMS")!
        let packageURL = URL(string: "\(base)/\(packageFilename)")!
        let releaseObject: [String: Any] = [
            "tag_name": "v1.2.3",
            "html_url": "https://github.com/RegionallyFamous/swansong-core/releases/tag/v1.2.3",
            "draft": false,
            "prerelease": false,
            "immutable": true,
            "assets": [
                [
                    "name": "release-manifest.json",
                    "browser_download_url": manifestURL.absoluteString,
                    "size": manifest.count,
                ],
                [
                    "name": "SHA256SUMS",
                    "browser_download_url": checksumsURL.absoluteString,
                    "size": checksums.count,
                ],
                [
                    "name": packageFilename,
                    "browser_download_url": packageURL.absoluteString,
                    "size": 3,
                ],
            ],
        ]
        return (
            try! JSONSerialization.data(withJSONObject: releaseObject),
            manifest,
            checksums,
            manifestURL,
            checksumsURL,
            packageURL,
            packageFilename
        )
    }
}

private final class PocketReleaseURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [URL: (statusCode: Int, body: Data)] = [:]
        private var requests: [URLRequest] = []

        func reset() {
            lock.lock()
            responses = [:]
            requests = []
            lock.unlock()
        }

        func setResponse(to url: URL, statusCode: Int, body: Data) {
            lock.lock()
            responses[url] = (statusCode, body)
            lock.unlock()
        }

        func takeResponse(for request: URLRequest) -> (Int, Data)? {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            guard let url = request.url,
                  let response = responses.removeValue(forKey: url) else {
                return nil
            }
            return (response.statusCode, response.body)
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
    }

    private static let storage = Storage()

    static var requestCount: Int { storage.requestCount }
    static var lastRequest: URLRequest? { storage.lastRequest }

    static func reset() {
        storage.reset()
    }

    static func respond(statusCode: Int, body: Data) {
        respond(
            to: PocketCoreReleaseService.latestReleaseURL,
            statusCode: statusCode,
            body: body
        )
    }

    static func respond(to url: URL, statusCode: Int, body: Data) {
        storage.setResponse(to: url, statusCode: statusCode, body: body)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let (statusCode, body) = Self.storage.takeResponse(for: request),
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: [:]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
