import Foundation
@preconcurrency import CryptoKit
import SwanSongKit
@testable import SwanSongApp
import XCTest

private let testHomebrewCatalogConsentDefaultsKey =
    "SwanSong.homebrewCatalogConsent.v1"

@MainActor
final class AppModelHomebrewTransactionTests: XCTestCase {
    func testInitializationIsOfflineUntilExplicitCatalogLoad() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }

        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 0)
        XCTAssertNil(fixture.model.homebrewCatalog)

        let catalog = makeCatalog(assetData: makeROM())
        let catalogData = try encode(catalog)
        let signatureData = try TestCatalogSigning.signatureData(for: catalogData)
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: catalogData)
        )
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: signatureData)
        )
        fixture.model.homebrewCatalogConsentGranted = true
        fixture.model.refreshHomebrewCatalog()
        try await waitUntil("explicit catalog request did not finish") {
            !fixture.model.homebrewCatalogIsLoading
        }

        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 2)
        XCTAssertEqual(
            AppModelHomebrewURLProtocol.requestURLs,
            [HomebrewCatalogClient.catalogURL, HomebrewCatalogClient.signatureURL]
        )
        XCTAssertEqual(fixture.model.homebrewCatalog, catalog)
        XCTAssertEqual(fixture.model.selectedHomebrewEntryID, catalog.entries.first?.id)
        XCTAssertNil(fixture.model.homebrewCatalogIssue)
        XCTAssertEqual(
            try fixture.cacheStore.load(),
            HomebrewCatalogCachedBundle(
                catalogData: catalogData,
                signatureData: signatureData
            )
        )
    }

    func testMissingProductionTrustAnchorNeverRequestsTheCatalog() throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(
            client: makeClient(),
            signatureVerifier: HomebrewCatalogSignatureVerifier(trustedKeys: [])
        )
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }

        XCTAssertFalse(fixture.model.homebrewCatalogIsConfigured)
        fixture.model.enableHomebrewCatalog()
        fixture.model.homebrewCatalogConsentGranted = true
        fixture.model.refreshHomebrewCatalog()

        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 0)
        XCTAssertFalse(fixture.model.homebrewCatalogIsLoading)
        XCTAssertNil(fixture.model.homebrewCatalog)
        XCTAssertNotNil(fixture.model.homebrewCatalogIssue)
    }

    func testStoppingCatalogUseClearsConsentAndCacheWithoutChangingLibrary() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let catalog = makeCatalog(assetData: makeROM())
        try await load(catalog, into: fixture)
        fixture.model.homebrewCatalogConsentGranted = true
        let gamesBefore = fixture.model.games
        let highWaterBefore = try XCTUnwrap(fixture.highWaterStore.snapshot())

        fixture.model.stopUsingHomebrewCatalog()

        XCTAssertFalse(fixture.model.homebrewCatalogConsentGranted)
        XCTAssertNil(fixture.model.homebrewCatalog)
        XCTAssertNil(try fixture.cacheStore.load())
        XCTAssertNotNil(fixture.model.presentedNotice)
        XCTAssertEqual(fixture.model.games, gamesBefore)
        XCTAssertEqual(
            try fixture.highWaterStore.snapshot(),
            highWaterBefore,
            "Stopping catalog use must retain signed-catalog rollback protection."
        )
    }

    func testStoppingWhileCatalogRequestIsSuspendedKeepsCacheAbsent() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let catalogData = try encode(makeCatalog(assetData: makeROM()))
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: catalogData, delay: 0.25)
        )
        AppModelHomebrewURLProtocol.enqueue(
            .init(
                statusCode: 200,
                body: try TestCatalogSigning.signatureData(for: catalogData)
            )
        )

        fixture.model.homebrewCatalogConsentGranted = true
        fixture.model.refreshHomebrewCatalog()
        try await waitUntil("suspended catalog request did not start") {
            AppModelHomebrewURLProtocol.requestCount == 1
                && fixture.model.homebrewCatalogIsLoading
        }

        fixture.model.stopUsingHomebrewCatalog()
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertFalse(fixture.model.homebrewCatalogConsentGranted)
        XCTAssertFalse(fixture.model.homebrewCatalogIsLoading)
        XCTAssertNil(fixture.model.homebrewCatalog)
        XCTAssertNil(try fixture.cacheStore.load())
        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 1)
    }

    func testCancelledRefreshCannotClearOwnershipOfNewRefresh() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let firstData = try encode(makeCatalog(assetData: makeROM()))
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: firstData, delay: 1)
        )
        AppModelHomebrewURLProtocol.enqueue(
            .init(
                statusCode: 200,
                body: try TestCatalogSigning.signatureData(for: firstData)
            )
        )
        fixture.model.homebrewCatalogConsentGranted = true
        fixture.model.refreshHomebrewCatalog()
        try await waitUntil("first suspended refresh did not start") {
            AppModelHomebrewURLProtocol.requestCount == 1
        }

        fixture.model.stopUsingHomebrewCatalog()
        AppModelHomebrewURLProtocol.reset()
        let secondCatalog = makeCatalog(
            assetData: makeROM(),
            revision: 2,
            generatedAt: Date(timeIntervalSince1970: 1_750_000_200)
        )
        let secondData = try encode(secondCatalog)
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: secondData, delay: 0.25)
        )
        AppModelHomebrewURLProtocol.enqueue(
            .init(
                statusCode: 200,
                body: try TestCatalogSigning.signatureData(for: secondData)
            )
        )
        fixture.model.enableHomebrewCatalog()
        try await waitUntil("replacement refresh did not start") {
            AppModelHomebrewURLProtocol.requestCount == 1
                && fixture.model.homebrewCatalogIsLoading
        }

        // Give the cancelled task time to execute its defer while the
        // replacement request is still deliberately suspended.
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertTrue(fixture.model.homebrewCatalogIsLoading)
        fixture.model.refreshHomebrewCatalog()
        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 1)

        try await waitUntil("replacement refresh did not publish") {
            fixture.model.homebrewCatalog == secondCatalog
                && !fixture.model.homebrewCatalogIsLoading
        }
        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 2)
        XCTAssertEqual(
            try fixture.cacheStore.load()?.catalogData,
            secondData
        )
    }

    func testStoppingCatalogUseRefusesAnActiveInstall() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let rom = makeROM()
        let catalog = makeCatalog(assetData: rom)
        try await load(catalog, into: fixture)
        let entry = try XCTUnwrap(catalog.entries.first)
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: rom, delay: 0.25)
        )

        fixture.model.installHomebrew(entry)
        XCTAssertEqual(fixture.model.homebrewInstallingEntryID, entry.id)
        fixture.model.stopUsingHomebrewCatalog()

        XCTAssertTrue(fixture.model.homebrewCatalogConsentGranted)
        XCTAssertEqual(fixture.model.homebrewCatalog, catalog)
        XCTAssertNotNil(try fixture.cacheStore.load())
        XCTAssertTrue(
            fixture.model.presentedNotice?.contains("Finish or cancel") == true
        )

        fixture.model.cancelHomebrewInstall()
        try await waitUntil("cancelled install did not finish") {
            fixture.model.homebrewInstallingEntryID == nil
                && !fixture.model.gameImportIsBusy
        }
        XCTAssertTrue(fixture.model.games.isEmpty)
        XCTAssertNil(fixture.model.homebrewInstallIssue)
        XCTAssertNil(fixture.model.homebrewInstallIssueEntryID)
    }

    func testMismatchedCatalogSignaturePairRetriesOnceThenPublishes() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let catalogData = try encode(makeCatalog(assetData: makeROM()))
        let staleSignature = try TestCatalogSigning.signatureData(
            for: Data("stale-catalog".utf8)
        )
        let validSignature = try TestCatalogSigning.signatureData(for: catalogData)
        AppModelHomebrewURLProtocol.enqueue(.init(statusCode: 200, body: catalogData))
        AppModelHomebrewURLProtocol.enqueue(.init(statusCode: 200, body: staleSignature))
        AppModelHomebrewURLProtocol.enqueue(.init(statusCode: 200, body: catalogData))
        AppModelHomebrewURLProtocol.enqueue(.init(statusCode: 200, body: validSignature))

        fixture.model.homebrewCatalogConsentGranted = true
        fixture.model.refreshHomebrewCatalog()
        try await waitUntil("catalog/signature retry did not finish") {
            !fixture.model.homebrewCatalogIsLoading
        }

        XCTAssertNotNil(fixture.model.homebrewCatalog)
        XCTAssertNil(fixture.model.homebrewCatalogIssue)
        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 4)
        XCTAssertEqual(try fixture.cacheStore.load()?.signatureData, validSignature)
    }

    func testInvalidSignatureAfterRetryIsNeverDecodedCachedOrPublished() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let catalogData = try encode(makeCatalog(assetData: makeROM()))
        let invalidSignature = try TestCatalogSigning.signatureData(
            for: Data("different-catalog".utf8)
        )
        for _ in 0..<2 {
            AppModelHomebrewURLProtocol.enqueue(.init(statusCode: 200, body: catalogData))
            AppModelHomebrewURLProtocol.enqueue(
                .init(statusCode: 200, body: invalidSignature)
            )
        }

        fixture.model.homebrewCatalogConsentGranted = true
        fixture.model.refreshHomebrewCatalog()
        try await waitUntil("invalid catalog/signature retry did not finish") {
            !fixture.model.homebrewCatalogIsLoading
        }

        XCTAssertNil(fixture.model.homebrewCatalog)
        XCTAssertNil(try fixture.cacheStore.load())
        XCTAssertNotNil(fixture.model.homebrewCatalogIssue)
        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 4)
    }

    func testCachedCatalogIsReverifiedAtLaunchAndInvalidCacheIsIgnored() throws {
        AppModelHomebrewURLProtocol.reset()
        let catalogData = try encode(makeCatalog(assetData: makeROM()))
        let fixture = try Fixture(
            client: makeClient(),
            cachedBundle: HomebrewCatalogCachedBundle(
                catalogData: catalogData,
                signatureData: try TestCatalogSigning.signatureData(
                    for: Data("not-the-cached-catalog".utf8)
                )
            )
        )
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }

        XCTAssertNil(fixture.model.homebrewCatalog)
        XCTAssertNil(try fixture.highWaterStore.snapshot())
        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 0)
    }

    func testSignedRevisionDowngradeKeepsPublishedCatalogAndAtomicCache() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let newest = makeCatalog(
            assetData: makeROM(),
            revision: 2,
            generatedAt: Date(timeIntervalSince1970: 1_750_000_200)
        )
        try await load(newest, into: fixture)
        let cacheBefore = try XCTUnwrap(fixture.cacheStore.load())
        let older = makeCatalog(
            assetData: makeROM(),
            revision: 1,
            generatedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
        let olderData = try encode(older)
        AppModelHomebrewURLProtocol.enqueue(.init(statusCode: 200, body: olderData))
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: try TestCatalogSigning.signatureData(for: olderData))
        )

        fixture.model.refreshHomebrewCatalog()
        try await waitUntil("signed revision downgrade did not finish") {
            !fixture.model.homebrewCatalogIsLoading
        }

        XCTAssertEqual(fixture.model.homebrewCatalog, newest)
        XCTAssertEqual(try fixture.cacheStore.load(), cacheBefore)
        XCTAssertNotNil(fixture.model.homebrewCatalogIssue)
        XCTAssertEqual(try fixture.highWaterStore.snapshot()?.highestRevision, 2)
    }

    func testValidCatalogROMInstallsIntoManagedLibraryWithOrigin() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let rom = makeROM()
        let catalog = makeCatalog(assetData: rom)
        let entry = try XCTUnwrap(catalog.entries.first)
        let release = try XCTUnwrap(entry.releases.first)
        try await load(catalog, into: fixture)
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: rom)
        )

        fixture.model.installHomebrew(entry)
        try await waitUntil("valid homebrew install did not finish") {
            fixture.model.homebrewInstallingEntryID == nil
                && !fixture.model.gameImportIsBusy
        }

        let game = try XCTUnwrap(fixture.model.games.only)
        let reference = try XCTUnwrap(game.managedROM)
        XCTAssertEqual(game.title, entry.title)
        XCTAssertEqual(game.sourceFileName, release.asset.url.lastPathComponent)
        XCTAssertEqual(game.preferredHardwareModel, release.asset.hardwareModel)
        XCTAssertEqual(
            game.homebrewCatalogOrigin,
            HomebrewCatalogOrigin(
                catalogID: catalog.catalogID,
                entryID: entry.id,
                version: release.version,
                releasedAt: release.releasedAt,
                saveCompatibilityID: release.saveCompatibilityID,
                assetSHA256: release.asset.sha256
            )
        )
        XCTAssertEqual(try fixture.managedStore.load(reference), rom)
        XCTAssertEqual(try fixture.libraryStore.load().games, fixture.model.games)
        XCTAssertEqual(fixture.model.selectedGameID, game.id)
        XCTAssertEqual(fixture.model.presentedNotice, "Added \(entry.title) to Library.")
        XCTAssertNil(fixture.model.homebrewInstallIssue)
        XCTAssertEqual(AppModelHomebrewURLProtocol.requestCount, 3)
    }

    func testInstallUsesCanonicalCatalogEntryInsteadOfCallerFields() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let rom = makeROM()
        let catalog = makeCatalog(assetData: rom)
        let canonicalEntry = try XCTUnwrap(catalog.entries.first)
        let canonicalRelease = try XCTUnwrap(canonicalEntry.releases.first)
        try await load(catalog, into: fixture)
        let forgedCallerEntry = HomebrewCatalogEntry(
            id: canonicalEntry.id,
            title: "Forged Caller Title",
            developer: "Untrusted Caller",
            summary: "This object shares only the catalog identity.",
            description: "Its fields and empty release list must not control installation.",
            sourceURL: canonicalEntry.sourceURL,
            provenanceURL: canonicalEntry.provenanceURL,
            licenseName: canonicalEntry.licenseName,
            licenseURL: canonicalEntry.licenseURL,
            releases: []
        )
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: rom)
        )

        fixture.model.installHomebrew(forgedCallerEntry)
        try await waitUntil("canonical homebrew install did not finish") {
            fixture.model.homebrewInstallingEntryID == nil
                && !fixture.model.gameImportIsBusy
                && !fixture.model.games.isEmpty
        }

        let game = try XCTUnwrap(fixture.model.games.only)
        XCTAssertEqual(game.title, canonicalEntry.title)
        XCTAssertEqual(game.homebrewCatalogOrigin?.entryID, canonicalEntry.id)
        XCTAssertEqual(game.homebrewCatalogOrigin?.version, canonicalRelease.version)
        XCTAssertEqual(AppModelHomebrewURLProtocol.requestURLs.last, canonicalRelease.asset.url)
        XCTAssertEqual(
            fixture.model.presentedNotice,
            "Added \(canonicalEntry.title) to Library."
        )
    }

    func testHashMismatchLeavesLibraryAndManagedStoreUnchanged() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let publishedROM = makeROM()
        let catalog = makeCatalog(assetData: publishedROM)
        let entry = try XCTUnwrap(catalog.entries.first)
        try await load(catalog, into: fixture)
        let documentBefore = try fixture.libraryStore.load()
        var mismatchedROM = publishedROM
        mismatchedROM[0] ^= 0xff
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: mismatchedROM)
        )

        fixture.model.installHomebrew(entry)
        try await waitUntil("hash-mismatch install did not finish") {
            fixture.model.homebrewInstallingEntryID == nil
                && !fixture.model.gameImportIsBusy
        }

        XCTAssertTrue(fixture.model.games.isEmpty)
        XCTAssertEqual(try fixture.libraryStore.load(), documentBefore)
        XCTAssertEqual(try fixture.managedFileNames(), [])
        XCTAssertTrue(
            fixture.model.homebrewInstallIssue?.contains(
                "does not match its published SHA-256 digest"
            ) == true
        )
        XCTAssertEqual(fixture.model.homebrewInstallIssueEntryID, entry.id)
    }

    func testConcurrentLibraryMutationRollsBackDownloadedManagedROM() async throws {
        AppModelHomebrewURLProtocol.reset()
        let fixture = try Fixture(client: makeClient())
        defer {
            fixture.remove()
            AppModelHomebrewURLProtocol.reset()
        }
        let homebrewROM = makeROM()
        let catalog = makeCatalog(assetData: homebrewROM)
        let entry = try XCTUnwrap(catalog.entries.first)
        try await load(catalog, into: fixture)
        AppModelHomebrewURLProtocol.enqueue(
            .init(statusCode: 200, body: homebrewROM, delay: 0.15)
        )

        fixture.model.installHomebrew(entry)
        try await waitUntil("asset request did not begin") {
            AppModelHomebrewURLProtocol.requestCount == 3
        }

        let concurrentROM = makeROM(color: false)
        let concurrentURL = fixture.rootURL.appendingPathComponent("Concurrent.ws")
        try concurrentROM.write(to: concurrentURL, options: .atomic)
        let concurrentGame = GameRecord(
            title: "Concurrent Import",
            fileURL: concurrentURL,
            metadata: try EngineSession.inspect(rom: concurrentROM)
        )
        fixture.model.games = [concurrentGame]
        try fixture.libraryStore.save(
            GameLibraryDocument(games: [concurrentGame])
        )

        try await waitUntil("concurrent-mutation install did not finish") {
            fixture.model.homebrewInstallingEntryID == nil
                && !fixture.model.gameImportIsBusy
        }

        XCTAssertEqual(fixture.model.games, [concurrentGame])
        XCTAssertEqual(try fixture.libraryStore.load().games, [concurrentGame])
        XCTAssertEqual(try fixture.managedFileNames(), [])
        XCTAssertTrue(
            fixture.model.homebrewInstallIssue?.contains(
                "The library changed while the game was downloading"
            ) == true
        )
        XCTAssertEqual(fixture.model.homebrewInstallIssueEntryID, entry.id)
    }

    private func load(
        _ catalog: HomebrewCatalog,
        into fixture: Fixture
    ) async throws {
        let catalogData = try encode(catalog)
        AppModelHomebrewURLProtocol.enqueue(.init(statusCode: 200, body: catalogData))
        AppModelHomebrewURLProtocol.enqueue(
            .init(
                statusCode: 200,
                body: try TestCatalogSigning.signatureData(for: catalogData)
            )
        )
        fixture.model.homebrewCatalogConsentGranted = true
        fixture.model.refreshHomebrewCatalog()
        try await waitUntil("catalog load did not finish") {
            !fixture.model.homebrewCatalogIsLoading
        }
        XCTAssertEqual(fixture.model.homebrewCatalog, catalog)
        XCTAssertNil(fixture.model.homebrewCatalogIssue)
    }

    private func makeClient() -> HomebrewCatalogClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppModelHomebrewURLProtocol.self]
        return HomebrewCatalogClient(
            testSourceURL: HomebrewCatalogClient.catalogURL,
            sessionConfiguration: configuration,
            trustsSource: { url in
                guard url.scheme?.lowercased() == "https",
                      url.user == nil,
                      url.password == nil,
                      url.port == nil else { return false }
                return ["raw.githubusercontent.com", "github.com"].contains(
                    url.host?.lowercased() ?? ""
                )
            }
        )
    }

    private func makeCatalog(
        assetData: Data,
        revision: Int = 1,
        generatedAt: Date = Date(timeIntervalSince1970: 1_750_000_100)
    ) -> HomebrewCatalog {
        let id = "transaction-fixture"
        let version = "1.0.0"
        let tag = "\(id)-v\(version)"
        let commit = String(repeating: "a", count: 40)
        let releasedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let entry = HomebrewCatalogEntry(
            id: id,
            title: "Transaction Fixture",
            developer: "Regionally Famous",
            summary: "A deterministic WonderSwan Color transaction fixture.",
            description: "A local test game used to prove the complete catalog download and managed-library transaction.",
            sourceURL: URL(
                string: "https://github.com/RegionallyFamous/swansong-story-forge/tree/\(commit)/games/\(id)"
            )!,
            provenanceURL: URL(
                string: "https://github.com/RegionallyFamous/swansong-story-forge/blob/\(commit)/games/\(id)/reports/release-report.json"
            )!,
            licenseName: "MIT License",
            licenseURL: URL(
                string: "https://github.com/RegionallyFamous/swansong-story-forge/blob/\(commit)/LICENSE"
            )!,
            releases: [
                HomebrewCatalogRelease(
                    version: version,
                    saveCompatibilityID: "transaction-fixture-save-v1",
                    releasedAt: releasedAt,
                    releaseURL: URL(
                        string: "https://github.com/RegionallyFamous/swansong-story-forge/releases/tag/\(tag)"
                    )!,
                    asset: HomebrewCatalogAsset(
                        url: URL(
                            string: "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/\(tag)/\(id).wsc"
                        )!,
                        byteCount: assetData.count,
                        sha256: ManagedGameStore.sha256(assetData),
                        fileExtension: "wsc",
                        hardwareModel: .wonderSwanColor
                    )
                ),
            ]
        )
        return HomebrewCatalog(
            catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
            revision: revision,
            generatedAt: generatedAt,
            repositoryURL: HomebrewCatalogValidator.firstPartyRepositoryURL,
            entries: [entry]
        )
    }

    private func makeROM(color: Bool = true) -> Data {
        var bytes = [UInt8](repeating: 0, count: 128 * 1_024)
        let footer = bytes.count - 16
        bytes[footer] = 0xea
        bytes[footer + 7] = color ? 1 : 0
        bytes[footer + 10] = 0
        bytes[footer + 11] = 0x01
        bytes[footer + 12] = 0x04
        let checksum = bytes[..<(bytes.count - 2)].reduce(UInt16(0)) {
            $0 &+ UInt16($1)
        }
        bytes[bytes.count - 2] = UInt8(truncatingIfNeeded: checksum)
        bytes[bytes.count - 1] = UInt8(truncatingIfNeeded: checksum >> 8)
        return Data(bytes)
    }

    private func encode(_ catalog: HomebrewCatalog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(catalog)
    }

    private func waitUntil(
        _ failureMessage: String,
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail(failureMessage)
                throw WaitTimeout()
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private struct WaitTimeout: Error {}

@MainActor
private struct Fixture {
    let rootURL: URL
    let libraryStore: GameLibraryStore
    let managedStore: ManagedGameStore
    let cacheStore: HomebrewCatalogCacheStore
    let highWaterStore = TestHomebrewCatalogHighWaterStore()
    let model: AppModel
    let preservedCatalogConsent: Any?

    init(
        client: HomebrewCatalogClient,
        cachedBundle: HomebrewCatalogCachedBundle? = nil,
        signatureVerifier: HomebrewCatalogSignatureVerifier = TestCatalogSigning.verifier
    ) throws {
        preservedCatalogConsent = UserDefaults.standard.object(
            forKey: testHomebrewCatalogConsentDefaultsKey
        )
        UserDefaults.standard.removeObject(
            forKey: testHomebrewCatalogConsentDefaultsKey
        )
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-AppModelHomebrew-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        libraryStore = GameLibraryStore(
            fileURL: rootURL.appendingPathComponent("Library.json")
        )
        managedStore = ManagedGameStore(
            rootURL: rootURL.appendingPathComponent("Games", isDirectory: true)
        )
        cacheStore = HomebrewCatalogCacheStore(
            directoryURL: rootURL.appendingPathComponent("Homebrew", isDirectory: true)
        )
        if let cachedBundle {
            try cacheStore.store(cachedBundle)
        }
        model = AppModel(
            store: libraryStore,
            saveStore: GameSaveStore(
                rootURL: rootURL.appendingPathComponent("Saves", isDirectory: true)
            ),
            stateStore: GameStateStore(
                rootURL: rootURL.appendingPathComponent("States", isDirectory: true)
            ),
            managedGameStore: managedStore,
            homebrewCatalogClientOverride: client,
            homebrewCatalogCacheStore: cacheStore,
            homebrewCatalogSignatureVerifier: signatureVerifier,
            homebrewCatalogHighWaterStore: highWaterStore,
            homebrewCatalogMinimumRevision: 1,
            artworkStore: GameArtworkStore(
                rootURL: rootURL.appendingPathComponent("Artwork", isDirectory: true)
            ),
            controllerProfileStore: ControllerProfileStore(
                fileURL: rootURL.appendingPathComponent("ControllerProfile.json")
            ),
            translationWorkspaceStore: TranslationWorkspaceStore(
                fileURL: rootURL.appendingPathComponent("TranslationWorkspace.json")
            ),
            engineCanExecuteOverride: false
        )
    }

    func managedFileNames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: managedStore.rootURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            atPath: managedStore.rootURL.path
        ).sorted()
    }

    func remove() {
        if let preservedCatalogConsent {
            UserDefaults.standard.set(
                preservedCatalogConsent,
                forKey: testHomebrewCatalogConsentDefaultsKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: testHomebrewCatalogConsentDefaultsKey
            )
        }
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private enum TestCatalogSigning {
    static let keyID = "ed25519-appmodel-test-9d61b19d"
    static let privateKey: Curve25519.Signing.PrivateKey = {
        try! Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(testHex: "9d61b19deffd5a60ba844af492ec2cc4" +
                "4449c5697b326919703bac031cae7f60")
        )
    }()
    static let verifier = HomebrewCatalogSignatureVerifier(
        trustedKeys: [
            .init(keyID: keyID, rawPublicKey: privateKey.publicKey.rawRepresentation),
        ]
    )

    static func signatureData(for catalogData: Data) throws -> Data {
        try HomebrewCatalogSignatureEnvelope(
            catalogSHA256: HomebrewCatalogSignatureVerifier.sha256(catalogData),
            catalogByteCount: catalogData.count,
            signatures: [
                .init(
                    keyID: keyID,
                    signature: try privateKey.signature(for: catalogData)
                        .base64EncodedString()
                ),
            ]
        ).encoded()
    }
}

private final class TestHomebrewCatalogHighWaterStore: HomebrewCatalogHighWaterStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var state: HomebrewCatalogHighWaterState?

    func load(catalogID: String) throws -> HomebrewCatalogHighWaterState? {
        lock.lock()
        defer { lock.unlock() }
        guard state?.catalogID == catalogID else { return nil }
        return state
    }

    @discardableResult
    func advance(
        to state: HomebrewCatalogHighWaterState,
        publishingWhileLocked publication: @Sendable () throws -> Void
    ) throws -> HomebrewCatalogHighWaterState {
        lock.lock()
        defer { lock.unlock() }
        if let current = self.state {
            guard state.highestRevision >= current.highestRevision else {
                throw HomebrewCatalogRollbackError.revisionDowngrade
            }
            if state.highestRevision == current.highestRevision {
                guard state.catalogSHA256 == current.catalogSHA256 else {
                    throw HomebrewCatalogRollbackError.mutableRevision
                }
                try publication()
                return current
            }
            guard state.generatedAt >= current.generatedAt else {
                throw HomebrewCatalogRollbackError.nonmonotonicRevisionDate
            }
        }
        self.state = state
        try publication()
        return state
    }

    func snapshot() throws -> HomebrewCatalogHighWaterState? {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}

private extension Data {
    init(testHex: String) {
        self.init()
        var index = testHex.startIndex
        while index < testHex.endIndex {
            let next = testHex.index(index, offsetBy: 2)
            append(UInt8(testHex[index..<next], radix: 16)!)
            index = next
        }
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

private final class AppModelHomebrewURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let body: Data
        let delay: TimeInterval

        init(statusCode: Int, body: Data, delay: TimeInterval = 0) {
            self.statusCode = statusCode
            self.body = body
            self.delay = delay
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

        var requestURLs: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return requests.compactMap(\.url)
        }
    }

    private static let storage = Storage()
    private var pendingDelivery: DispatchWorkItem?

    static var requestCount: Int { storage.requestCount }
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
                headerFields: nil
            )!
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
