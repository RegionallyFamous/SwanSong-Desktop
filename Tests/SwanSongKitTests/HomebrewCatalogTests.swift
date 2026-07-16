import Foundation
import SwanSongKit
import XCTest

final class HomebrewCatalogTests: XCTestCase {
    func testStrictFirstPartyCatalogValidationAndDecoding() throws {
        let data = makeROM(color: true)
        let release = makeRelease(data: data)
        let catalog = makeCatalog(entry: makeEntry(releases: [release]))

        try HomebrewCatalogValidator.validate(catalog, sourceURL: catalogSourceURL)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(catalog)
        XCTAssertEqual(
            try HomebrewCatalogValidator.decode(encoded, sourceURL: catalogSourceURL),
            catalog
        )

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["unexpected"] = true
        let unknownKeyData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try HomebrewCatalogValidator.decode(unknownKeyData, sourceURL: catalogSourceURL)
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .invalidJSONSchema("document")
            )
        }
    }

    func testCatalogRejectsWrongSchemaIdentityAndDuplicateEntries() throws {
        let release = makeRelease(data: makeROM(color: true))
        let entry = makeEntry(releases: [release])

        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                HomebrewCatalog(
                    schemaVersion: 2,
                    catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
                    revision: 1,
                    generatedAt: Date(),
                    repositoryURL: HomebrewCatalogValidator.firstPartyRepositoryURL,
                    entries: [entry]
                ),
                sourceURL: catalogSourceURL
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .unsupportedSchemaVersion(2)
            )
        }

        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                HomebrewCatalog(
                    catalogID: "somewhere-else",
                    revision: 1,
                    generatedAt: Date(),
                    repositoryURL: HomebrewCatalogValidator.firstPartyRepositoryURL,
                    entries: [entry]
                ),
                sourceURL: catalogSourceURL
            )
        )

        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                makeCatalog(entries: [entry, entry]),
                sourceURL: catalogSourceURL
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .duplicateEntryID(entry.id)
            )
        }

        let sameDate = try XCTUnwrap(release.releasedAt)
        let secondRelease = makeRelease(
            data: changingROM(makeROM(color: true), byteAt: 0, to: 0x61),
            version: "1.10.0",
            releasedAt: sameDate,
            tag: "test-game-v1.10.0"
        )
        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                makeCatalog(entry: makeEntry(releases: [release, secondRelease])),
                sourceURL: catalogSourceURL
            )
        ) { error in
            XCTAssertEqual(error as? HomebrewCatalogError, .duplicateReleaseDate)
        }

        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                HomebrewCatalog(
                    catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
                    revision: 0,
                    generatedAt: Date(),
                    repositoryURL: HomebrewCatalogValidator.firstPartyRepositoryURL,
                    entries: [entry]
                ),
                sourceURL: catalogSourceURL
            )
        ) { error in
            XCTAssertEqual(error as? HomebrewCatalogError, .invalidRevision(0))
        }

        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                HomebrewCatalog(
                    catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
                    revision: 1,
                    generatedAt: Date().addingTimeInterval(2 * 24 * 60 * 60),
                    repositoryURL: HomebrewCatalogValidator.firstPartyRepositoryURL,
                    entries: [entry]
                ),
                sourceURL: catalogSourceURL
            )
        ) { error in
            XCTAssertEqual(error as? HomebrewCatalogError, .invalidGeneratedAt)
        }
    }

    func testCatalogRejectsNonFirstPartyAndMismatchedAssetContracts() throws {
        let data = makeROM(color: true)
        let digest = ManagedGameStore.sha256(data)
        let foreignAsset = HomebrewCatalogAsset(
            url: URL(string: "https://example.com/test-game.wsc")!,
            byteCount: data.count,
            sha256: digest,
            fileExtension: "wsc",
            hardwareModel: .wonderSwanColor
        )
        let foreignRelease = HomebrewCatalogRelease(
            version: "1.0.0",
            saveCompatibilityID: "test-game-save-v1",
            releasedAt: Date(timeIntervalSince1970: 1_750_000_000),
            releaseURL: releaseURL(tag: "test-game-v1.0.0"),
            asset: foreignAsset
        )
        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                makeCatalog(entry: makeEntry(releases: [foreignRelease])),
                sourceURL: catalogSourceURL
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .invalidAssetURL(foreignAsset.url)
            )
        }

        let wrongModelAsset = HomebrewCatalogAsset(
            url: assetURL(tag: "test-game-v1.0.0", fileName: "test-game.wsc"),
            byteCount: data.count,
            sha256: digest,
            fileExtension: "wsc",
            hardwareModel: .wonderSwan
        )
        let wrongModelRelease = HomebrewCatalogRelease(
            version: "1.0.0",
            saveCompatibilityID: "test-game-save-v1",
            releasedAt: Date(timeIntervalSince1970: 1_750_000_000),
            releaseURL: releaseURL(tag: "test-game-v1.0.0"),
            asset: wrongModelAsset
        )
        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                makeCatalog(entry: makeEntry(releases: [wrongModelRelease])),
                sourceURL: catalogSourceURL
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .assetFileExtensionMismatch
            )
        }

        let validCatalog = makeCatalog(entry: makeEntry(releases: [makeRelease(data: data)]))
        XCTAssertThrowsError(
            try HomebrewCatalogValidator.validate(
                validCatalog,
                sourceURL: URL(string: "https://example.com/catalog-v1.json")!
            )
        )
    }

    func testCatalogRejectsInvalidAssetSizeDigestExtensionAndModel() throws {
        let data = makeROM(color: true)
        let digest = ManagedGameStore.sha256(data)
        let cases: [(HomebrewCatalogAsset, HomebrewCatalogError)] = [
            (
                HomebrewCatalogAsset(
                    url: assetURL(tag: "test-game-v1.0.0", fileName: "test-game.wsc"),
                    byteCount: data.count + 1,
                    sha256: digest,
                    fileExtension: "wsc",
                    hardwareModel: .wonderSwanColor
                ),
                .invalidAssetByteCount(data.count + 1)
            ),
            (
                HomebrewCatalogAsset(
                    url: assetURL(tag: "test-game-v1.0.0", fileName: "test-game.wsc"),
                    byteCount: data.count,
                    sha256: digest.uppercased(),
                    fileExtension: "wsc",
                    hardwareModel: .wonderSwanColor
                ),
                .invalidAssetSHA256(digest.uppercased())
            ),
            (
                HomebrewCatalogAsset(
                    url: assetURL(tag: "test-game-v1.0.0", fileName: "test-game.zip"),
                    byteCount: data.count,
                    sha256: digest,
                    fileExtension: "zip",
                    hardwareModel: .wonderSwanColor
                ),
                .invalidAssetFileExtension("zip")
            ),
            (
                HomebrewCatalogAsset(
                    url: assetURL(tag: "test-game-v1.0.0", fileName: "test-game.wsc"),
                    byteCount: data.count,
                    sha256: digest,
                    fileExtension: "wsc",
                    hardwareModel: .automatic
                ),
                .invalidAssetHardwareModel(.automatic)
            ),
        ]

        for (asset, expectedError) in cases {
            let release = HomebrewCatalogRelease(
                version: "1.0.0",
                saveCompatibilityID: "test-game-save-v1",
                releasedAt: Date(timeIntervalSince1970: 1_750_000_000),
                releaseURL: releaseURL(tag: "test-game-v1.0.0"),
                asset: asset
            )
            XCTAssertThrowsError(
                try HomebrewCatalogValidator.validate(
                    makeCatalog(entry: makeEntry(releases: [release])),
                    sourceURL: catalogSourceURL
                )
            ) { error in
                XCTAssertEqual(error as? HomebrewCatalogError, expectedError)
            }
        }


        let pc2Data = makeROM(color: false)
        let pc2Release = makeRelease(
            data: pc2Data,
            tag: "test-game-pc2-v1.0.0",
            fileExtension: "pc2",
            hardwareModel: .pocketChallengeV2
        )
        XCTAssertNoThrow(
            try HomebrewCatalogValidator.validate(
                makeCatalog(entry: makeEntry(releases: [pc2Release])),
                sourceURL: catalogSourceURL
            )
        )
    }

    func testInstallCreatesManagedGameAndOrigin() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let data = makeROM(color: true)
        let release = makeRelease(data: data)
        let entry = makeEntry(releases: [release])

        let result = try HomebrewCatalogInstaller(assetData: data).install(
            entry: entry,
            release: release,
            into: [],
            managedStore: fixture.managedStore
        )

        XCTAssertEqual(result.action, .installed)
        XCTAssertEqual(result.games.count, 1)
        XCTAssertNotNil(result.createdReference)
        let game = try XCTUnwrap(result.games.first)
        XCTAssertEqual(game.id, result.gameID)
        XCTAssertEqual(game.title, entry.title)
        XCTAssertEqual(game.managedROM, result.createdReference)
        XCTAssertEqual(game.preferredHardwareModel, .wonderSwanColor)
        XCTAssertEqual(
            game.homebrewCatalogOrigin,
            HomebrewCatalogOrigin(
                catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
                entryID: entry.id,
                version: release.version,
                releasedAt: release.releasedAt,
                saveCompatibilityID: release.saveCompatibilityID,
                assetSHA256: release.asset.sha256
            )
        )
        XCTAssertEqual(
            try fixture.managedStore.load(try XCTUnwrap(game.managedROM)),
            data
        )
    }

    func testInstallAdoptsExactManagedDigestAndPreservesMetadata() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let data = makeROM(color: true)
        let release = makeRelease(data: data)
        let entry = makeEntry(releases: [release])
        let metadata = try GameROMValidationPolicy.validateLibraryImage(data)
        let existingInstall = try fixture.managedStore.install(
            LibraryGameImportImage(
                data: data,
                suggestedTitle: "Local Copy",
                sourceFileName: "local.wsc",
                metadata: metadata,
                sha256: ManagedGameStore.sha256(data),
                hardwareModel: .wonderSwanColor
            )
        )
        let id = UUID()
        let lastPlayedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let addedAt = Date(timeIntervalSince1970: 1_740_000_000)
        let evidence = GameCompatibilityEvidence(
            reachedVideoAt: lastPlayedAt,
            verdict: .works,
            note: "My note",
            updatedAt: lastPlayedAt
        )
        let existing = GameRecord(
            id: id,
            title: "My Custom Title",
            fileURL: existingInstall.fileURL,
            metadata: metadata,
            lastPlayedAt: lastPlayedAt,
            isFavorite: true,
            addedAt: addedAt,
            managedROM: existingInstall.reference,
            sourceFileName: "local.wsc",
            artworkPreference: .procedural,
            compatibilityEvidence: evidence,
            preferredHardwareModel: .wonderSwanColor
        )

        let result = try HomebrewCatalogInstaller(assetData: data).install(
            entry: entry,
            release: release,
            into: [existing],
            managedStore: fixture.managedStore
        )

        XCTAssertEqual(result.action, .adopted)
        XCTAssertNil(result.createdReference)
        XCTAssertEqual(result.gameID, id)
        let adopted = try XCTUnwrap(result.games.first)
        XCTAssertEqual(adopted.id, id)
        XCTAssertEqual(adopted.title, existing.title)
        XCTAssertEqual(adopted.lastPlayedAt, lastPlayedAt)
        XCTAssertTrue(adopted.isFavorite)
        XCTAssertEqual(adopted.addedAt, addedAt)
        XCTAssertEqual(adopted.artworkPreference, .procedural)
        XCTAssertEqual(adopted.compatibilityEvidence, evidence)
        XCTAssertEqual(adopted.homebrewCatalogOrigin?.entryID, entry.id)
    }

    func testCompatibleUpdatePreservesUUIDAndUserMetadata() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let originalData = makeROM(color: true)
        let originalRelease = makeRelease(data: originalData)
        let entry = makeEntry(releases: [originalRelease])
        let initial = try HomebrewCatalogInstaller(assetData: originalData).install(
            entry: entry,
            release: originalRelease,
            into: [],
            managedStore: fixture.managedStore
        )
        var existing = try XCTUnwrap(initial.games.first)
        existing.isFavorite = true
        existing.artworkPreference = .procedural
        existing.compatibilityEvidence = GameCompatibilityEvidence(
            verdict: .issues,
            note: "Retain this",
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let originalID = existing.id
        let originalReference = existing.managedROM

        let updatedData = changingROM(originalData, byteAt: 0, to: 0x7f)
        let updatedRelease = makeRelease(
            data: updatedData,
            version: "1.1.0",
            saveCompatibilityID: originalRelease.saveCompatibilityID,
            tag: "test-game-v1.1.0"
        )
        let updatedEntry = makeEntry(releases: [updatedRelease])
        let result = try HomebrewCatalogInstaller(assetData: updatedData).install(
            entry: updatedEntry,
            release: updatedRelease,
            into: [existing],
            managedStore: fixture.managedStore
        )

        XCTAssertEqual(result.action, .updated)
        XCTAssertEqual(result.gameID, originalID)
        XCTAssertNotNil(result.createdReference)
        let updated = try XCTUnwrap(result.games.first)
        XCTAssertEqual(updated.id, originalID)
        XCTAssertTrue(updated.isFavorite)
        XCTAssertEqual(updated.artworkPreference, .procedural)
        XCTAssertEqual(updated.compatibilityEvidence, existing.compatibilityEvidence)
        XCTAssertNotEqual(updated.managedROM, originalReference)
        XCTAssertEqual(updated.homebrewCatalogOrigin?.version, "1.1.0")
    }

    func testUpdateBlocksChangedSaveCompatibilityBeforeWritingAsset() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let originalData = makeROM(color: true)
        let originalRelease = makeRelease(data: originalData)
        let entry = makeEntry(releases: [originalRelease])
        let initial = try HomebrewCatalogInstaller(assetData: originalData).install(
            entry: entry,
            release: originalRelease,
            into: [],
            managedStore: fixture.managedStore
        )

        let updatedData = changingROM(originalData, byteAt: 0, to: 0x44)
        let incompatibleRelease = makeRelease(
            data: updatedData,
            version: "2.0.0",
            saveCompatibilityID: "test-game-save-v2",
            tag: "test-game-v2.0.0"
        )
        XCTAssertThrowsError(
            try HomebrewCatalogInstaller(assetData: updatedData).install(
                entry: makeEntry(releases: [incompatibleRelease]),
                release: incompatibleRelease,
                into: initial.games,
                managedStore: fixture.managedStore
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .changedSaveCompatibility(
                    existing: originalRelease.saveCompatibilityID,
                    requested: incompatibleRelease.saveCompatibilityID
                )
            )
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.managedStore.rootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.filter { !$0.lastPathComponent.hasPrefix(".") }.count, 1)
    }

    func testInstallerRejectsMutableVersionAndDownloadedDigestMismatch() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let originalData = makeROM(color: true)
        let originalRelease = makeRelease(data: originalData)
        let initial = try HomebrewCatalogInstaller(assetData: originalData).install(
            entry: makeEntry(releases: [originalRelease]),
            release: originalRelease,
            into: [],
            managedStore: fixture.managedStore
        )

        let changedData = changingROM(originalData, byteAt: 0, to: 0x25)
        let mutableRelease = makeRelease(data: changedData, version: "1.0.0")
        XCTAssertThrowsError(
            try HomebrewCatalogInstaller(assetData: changedData).install(
                entry: makeEntry(releases: [mutableRelease]),
                release: mutableRelease,
                into: initial.games,
                managedStore: fixture.managedStore
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .mutableReleaseVersion("1.0.0")
            )
        }

        XCTAssertThrowsError(
            try HomebrewCatalogInstaller(assetData: Data(repeating: 0, count: originalData.count))
                .install(
                    entry: makeEntry(releases: [originalRelease]),
                    release: originalRelease,
                    into: [],
                    managedStore: fixture.managedStore
                )
        ) { error in
            XCTAssertEqual(error as? HomebrewCatalogError, .assetSHA256Mismatch)
        }

        let wrongSizeCodeData = makeROM(color: true, romSizeCode: 0x01)
        let wrongSizeCodeRelease = makeRelease(data: wrongSizeCodeData)
        XCTAssertThrowsError(
            try HomebrewCatalogInstaller(assetData: wrongSizeCodeData).install(
                entry: makeEntry(releases: [wrongSizeCodeRelease]),
                release: wrongSizeCodeRelease,
                into: [],
                managedStore: fixture.managedStore
            )
        ) { error in
            XCTAssertEqual(error as? HomebrewCatalogError, .invalidAssetContents)
        }
    }

    func testUpdateRejectsHardwareSaveTypeAndRTCContractChanges() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let originalData = makeROM(color: true)
        let originalRelease = makeRelease(data: originalData)
        let initial = try HomebrewCatalogInstaller(assetData: originalData).install(
            entry: makeEntry(releases: [originalRelease]),
            release: originalRelease,
            into: [],
            managedStore: fixture.managedStore
        )
        let incompatibleAssets: [(Data, String, EngineHardwareModel, String)] = [
            (makeROM(color: false), "ws-model", .wonderSwan, "ws"),
            (makeROM(color: true, saveType: 0x02), "save-type", .wonderSwanColor, "wsc"),
            (makeROM(color: true, mapper: 1), "rtc", .wonderSwanColor, "wsc"),
        ]

        for (data, suffix, model, fileExtension) in incompatibleAssets {
            let release = makeRelease(
                data: data,
                version: "1.1.0-\(suffix)",
                tag: "test-game-v1.1.0-\(suffix)",
                fileExtension: fileExtension,
                hardwareModel: model
            )
            XCTAssertThrowsError(
                try HomebrewCatalogInstaller(assetData: data).install(
                    entry: makeEntry(releases: [release]),
                    release: release,
                    into: initial.games,
                    managedStore: fixture.managedStore
                ),
                "Expected \(suffix) persistence contract to be rejected"
            ) { error in
                XCTAssertEqual(
                    error as? HomebrewCatalogError,
                    .changedPersistenceContract
                )
            }
        }
    }

    func testPocketChallengeHashChangingUpdateRequiresMigration() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let originalData = makeROM(color: false)
        let originalRelease = makeRelease(
            data: originalData,
            fileExtension: "pcv2",
            hardwareModel: .pocketChallengeV2
        )
        let initial = try HomebrewCatalogInstaller(assetData: originalData).install(
            entry: makeEntry(releases: [originalRelease]),
            release: originalRelease,
            into: [],
            managedStore: fixture.managedStore
        )
        let updatedData = changingROM(originalData, byteAt: 0, to: 0x33)
        let updatedRelease = makeRelease(
            data: updatedData,
            version: "1.1.0",
            tag: "test-game-v1.1.0",
            fileExtension: "pcv2",
            hardwareModel: .pocketChallengeV2
        )

        XCTAssertThrowsError(
            try HomebrewCatalogInstaller(assetData: updatedData).install(
                entry: makeEntry(releases: [updatedRelease]),
                release: updatedRelease,
                into: initial.games,
                managedStore: fixture.managedStore
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .pocketChallengeUpdateRequiresMigration
            )
        }
    }

    func testLegacyGameRecordWithoutCatalogOriginStillDecodes() throws {
        let data = makeROM(color: false)
        let metadata = try GameROMValidationPolicy.validateLibraryImage(data)
        let game = GameRecord(
            title: "Legacy",
            fileURL: URL(fileURLWithPath: "/tmp/legacy.ws"),
            metadata: metadata
        )
        let encoded = try JSONEncoder().encode(game)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "homebrewCatalogOrigin")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(GameRecord.self, from: legacy)

        XCTAssertEqual(decoded.id, game.id)
        XCTAssertNil(decoded.homebrewCatalogOrigin)
    }

    func testAssetChangingUpdateRejectsOlderPublishedRelease() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let installedData = makeROM(color: true)
        let installedRelease = makeRelease(
            data: installedData,
            version: "2.0.0",
            releasedAt: Date(timeIntervalSince1970: 1_760_000_000),
            tag: "test-game-v2.0.0"
        )
        let initial = try HomebrewCatalogInstaller(assetData: installedData).install(
            entry: makeEntry(releases: [installedRelease]),
            release: installedRelease,
            into: [],
            managedStore: fixture.managedStore
        )
        XCTAssertEqual(
            initial.games.first?.homebrewCatalogOrigin?.releasedAt,
            installedRelease.releasedAt
        )

        let olderData = changingROM(installedData, byteAt: 0, to: 0x51)
        let olderRelease = makeRelease(
            data: olderData,
            version: "1.5.0",
            releasedAt: Date(timeIntervalSince1970: 1_750_000_000),
            tag: "test-game-v1.5.0"
        )
        XCTAssertThrowsError(
            try HomebrewCatalogInstaller(assetData: olderData).install(
                entry: makeEntry(releases: [olderRelease]),
                release: olderRelease,
                into: initial.games,
                managedStore: fixture.managedStore
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .releaseDowngrade(installed: "2.0.0", requested: "1.5.0")
            )
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.managedStore.rootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.filter { !$0.lastPathComponent.hasPrefix(".") }.count, 1)
    }

    func testOriginWithoutReleasedAtStillDecodesForOlderLibraries() throws {
        let origin = HomebrewCatalogOrigin(
            catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
            entryID: "test-game",
            version: "1.0.0",
            saveCompatibilityID: "test-game-save-v1",
            assetSHA256: String(repeating: "a", count: 64)
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(origin))
                as? [String: Any]
        )
        object.removeValue(forKey: "releasedAt")

        let decoded = try JSONDecoder().decode(
            HomebrewCatalogOrigin.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded, origin)
        XCTAssertNil(decoded.releasedAt)
    }

    func testAssetChangingUpdateFailsClosedWithoutInstalledReleaseHistory() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let installedData = makeROM(color: true)
        let installedRelease = makeRelease(
            data: installedData,
            version: "1.0.0",
            tag: "test-game-v1.0.0"
        )
        let initial = try HomebrewCatalogInstaller(assetData: installedData).install(
            entry: makeEntry(releases: [installedRelease]),
            release: installedRelease,
            into: [],
            managedStore: fixture.managedStore
        )
        var legacyGames = initial.games
        legacyGames[0].homebrewCatalogOrigin = HomebrewCatalogOrigin(
            catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
            entryID: "test-game",
            version: installedRelease.version,
            saveCompatibilityID: installedRelease.saveCompatibilityID,
            assetSHA256: installedRelease.asset.sha256
        )

        let candidateData = changingROM(installedData, byteAt: 0, to: 0x52)
        let candidateRelease = makeRelease(
            data: candidateData,
            version: "2.0.0",
            releasedAt: Date(timeIntervalSince1970: 1_760_000_000),
            tag: "test-game-v2.0.0"
        )
        XCTAssertThrowsError(
            try HomebrewCatalogInstaller(assetData: candidateData).install(
                entry: makeEntry(releases: [candidateRelease]),
                release: candidateRelease,
                into: legacyGames,
                managedStore: fixture.managedStore
            )
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogError,
                .releaseDowngrade(installed: "1.0.0", requested: "2.0.0")
            )
        }
    }

    private let catalogSourceURL = URL(
        string: "https://raw.githubusercontent.com/RegionallyFamous/swansong-story-forge/main/distribution/catalog-v1.json"
    )!

    private let immutableCommit = String(repeating: "a", count: 40)

    private func makeCatalog(
        entry: HomebrewCatalogEntry
    ) -> HomebrewCatalog {
        makeCatalog(entries: [entry])
    }

    private func makeCatalog(
        entries: [HomebrewCatalogEntry]
    ) -> HomebrewCatalog {
        HomebrewCatalog(
            catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
            revision: 1,
            generatedAt: Date(
                timeIntervalSince1970: floor(Date().timeIntervalSince1970)
            ),
            repositoryURL: HomebrewCatalogValidator.firstPartyRepositoryURL,
            entries: entries
        )
    }

    private func makeEntry(
        releases: [HomebrewCatalogRelease]
    ) -> HomebrewCatalogEntry {
        HomebrewCatalogEntry(
            id: "test-game",
            title: "Test Game",
            developer: "Regionally Famous",
            summary: "A deterministic WonderSwan test game.",
            description: "A first-party fixture used to prove the catalog installation transaction.",
            sourceURL: URL(
                string: "https://github.com/RegionallyFamous/swansong-story-forge/tree/\(immutableCommit)/games/test-game"
            )!,
            provenanceURL: URL(
                string: "https://github.com/RegionallyFamous/swansong-story-forge/blob/\(immutableCommit)/games/test-game/reports/release-report.json"
            )!,
            licenseName: "MIT License",
            licenseURL: URL(
                string: "https://github.com/RegionallyFamous/swansong-story-forge/blob/\(immutableCommit)/LICENSE"
            )!,
            releases: releases
        )
    }

    private func makeRelease(
        data: Data,
        version: String = "1.0.0",
        releasedAt: Date = Date(timeIntervalSince1970: 1_750_000_000),
        saveCompatibilityID: String = "test-game-save-v1",
        tag: String = "test-game-v1.0.0",
        fileExtension: String = "wsc",
        hardwareModel: EngineHardwareModel = .wonderSwanColor
    ) -> HomebrewCatalogRelease {
        HomebrewCatalogRelease(
            version: version,
            saveCompatibilityID: saveCompatibilityID,
            releasedAt: releasedAt,
            releaseURL: releaseURL(tag: tag),
            asset: HomebrewCatalogAsset(
                url: assetURL(tag: tag, fileName: "test-game.\(fileExtension)"),
                byteCount: data.count,
                sha256: ManagedGameStore.sha256(data),
                fileExtension: fileExtension,
                hardwareModel: hardwareModel
            )
        )
    }

    private func releaseURL(tag: String) -> URL {
        URL(
            string: "https://github.com/RegionallyFamous/swansong-story-forge/releases/tag/\(tag)"
        )!
    }

    private func assetURL(tag: String, fileName: String) -> URL {
        URL(
            string: "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/\(tag)/\(fileName)"
        )!
    }

    private func makeROM(
        color: Bool,
        saveType: UInt8 = 0x01,
        mapper: UInt8 = 0,
        romSizeCode: UInt8 = 0
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 128 * 1_024)
        let footer = bytes.count - 16
        bytes[footer] = 0xea
        bytes[footer + 7] = color ? 1 : 0
        bytes[footer + 10] = romSizeCode
        bytes[footer + 11] = saveType
        bytes[footer + 12] = 0x04
        bytes[footer + 13] = mapper
        let checksum = bytes[..<(bytes.count - 2)].reduce(UInt16(0)) {
            $0 &+ UInt16($1)
        }
        bytes[bytes.count - 2] = UInt8(truncatingIfNeeded: checksum)
        bytes[bytes.count - 1] = UInt8(truncatingIfNeeded: checksum >> 8)
        return Data(bytes)
    }

    private func changingROM(
        _ data: Data,
        byteAt index: Int,
        to value: UInt8
    ) -> Data {
        var bytes = [UInt8](data)
        bytes[index] = value
        let checksum = bytes[..<(bytes.count - 2)].reduce(UInt16(0)) {
            $0 &+ UInt16($1)
        }
        bytes[bytes.count - 2] = UInt8(truncatingIfNeeded: checksum)
        bytes[bytes.count - 1] = UInt8(truncatingIfNeeded: checksum >> 8)
        return Data(bytes)
    }
}

private struct StoreFixture {
    let rootURL: URL
    let managedStore: ManagedGameStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwanSong-HomebrewCatalogTests-\(UUID().uuidString)", isDirectory: true)
        managedStore = ManagedGameStore(
            rootURL: rootURL.appendingPathComponent("Games", isDirectory: true)
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
