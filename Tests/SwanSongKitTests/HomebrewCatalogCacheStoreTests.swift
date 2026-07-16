import Darwin
import Foundation
@testable import SwanSongKit
import XCTest

final class HomebrewCatalogCacheStoreTests: XCTestCase {
    func testSignedBundleRoundTripsAtomicallyWithPrivatePermissions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bundle = signedBundle()

        let storedURL = try fixture.store.store(bundle)

        XCTAssertEqual(storedURL, fixture.store.cacheURL)
        XCTAssertEqual(storedURL.lastPathComponent, "SignedCatalog-v1.cache.json")
        XCTAssertEqual(try fixture.store.load(), bundle)
        XCTAssertEqual(try permissions(of: storedURL), 0o600)
        XCTAssertEqual(try permissions(of: storedURL.deletingLastPathComponent()), 0o700)
    }

    func testAbsentSignedCacheReturnsNilWithoutCreatingStorage() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        XCTAssertNil(try fixture.store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.directoryURL.path))
    }

    func testRemoveDeletesOnlyAValidPrivateCache() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.store.store(signedBundle())
        let unrelated = fixture.store.directoryURL.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)

        XCTAssertTrue(try fixture.store.remove())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.cacheURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertFalse(try fixture.store.remove())
    }

    func testLegacyUnsignedCatalogIsIgnored() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createStorage()
        let legacyURL = fixture.store.directoryURL.appendingPathComponent(
            HomebrewCatalogCacheStore.legacyUnsignedCacheFileName
        )
        try Data("unsigned".utf8).write(to: legacyURL)
        try setPermissions(0o600, at: legacyURL)

        XCTAssertNil(try fixture.store.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testInvalidComponentSizesAreRejectedWithoutReplacingCache() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = signedBundle()
        try fixture.store.store(original)

        let invalid = [
            HomebrewCatalogCachedBundle(catalogData: Data(), signatureData: Data("sig".utf8)),
            HomebrewCatalogCachedBundle(catalogData: Data("{}".utf8), signatureData: Data()),
            HomebrewCatalogCachedBundle(
                catalogData: Data(count: HomebrewCatalogValidator.maximumCatalogByteCount + 1),
                signatureData: Data("sig".utf8)
            ),
            HomebrewCatalogCachedBundle(
                catalogData: Data("{}".utf8),
                signatureData: Data(count: HomebrewCatalogSignatureEnvelope.maximumByteCount + 1)
            ),
        ]
        for bundle in invalid {
            XCTAssertThrowsError(try fixture.store.store(bundle)) { error in
                XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .invalidSignedBundle)
            }
        }
        XCTAssertEqual(try fixture.store.load(), original)
    }

    func testUnknownCacheKeysAndInvalidSchemaAreRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createStorage()
        let malformed = Data(
            #"{"schemaVersion":2,"catalogData":"e30=","signatureData":"c2ln","extra":true}"#.utf8
        )
        try malformed.write(to: fixture.store.cacheURL)
        try setPermissions(0o600, at: fixture.store.cacheURL)

        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .corruptCache)
        }
    }

    func testOversizedCacheOnDiskIsRejectedBeforeDecode() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createStorage()
        try Data(count: HomebrewCatalogCacheStore.maximumByteCount + 1)
            .write(to: fixture.store.cacheURL)
        try setPermissions(0o600, at: fixture.store.cacheURL)

        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .corruptCache)
        }
    }

    func testCacheSymlinkIsRefusedForLoadAndReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createStorage()
        let outside = fixture.root.appendingPathComponent("outside.json")
        let outsideData = Data("outside".utf8)
        try outsideData.write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.store.cacheURL,
            withDestinationURL: outside
        )

        assertUnsafe(try fixture.store.load())
        XCTAssertThrowsError(try fixture.store.store(signedBundle())) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .unsafeStorage)
        }
        XCTAssertThrowsError(try fixture.store.remove()) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .unsafeStorage)
        }
        XCTAssertEqual(try Data(contentsOf: outside), outsideData)
    }

    func testSymlinkedStorageDirectoryIsRefused() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.store.directoryURL,
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .unsafeStorage)
        }
        XCTAssertThrowsError(try fixture.store.store(signedBundle())) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .unsafeStorage)
        }
    }

    func testPublicOrHardLinkedCacheIsRefused() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.store.store(signedBundle())
        try setPermissions(0o644, at: fixture.store.cacheURL)
        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .unsafeStorage)
        }

        try FileManager.default.removeItem(at: fixture.store.cacheURL)
        let outside = fixture.root.appendingPathComponent("outside-hard-link.json")
        try Data("outside".utf8).write(to: outside)
        try setPermissions(0o600, at: outside)
        try FileManager.default.linkItem(at: outside, to: fixture.store.cacheURL)
        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .unsafeStorage)
        }
        XCTAssertThrowsError(try fixture.store.store(signedBundle())) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .unsafeStorage)
        }
    }

    private func signedBundle() -> HomebrewCatalogCachedBundle {
        HomebrewCatalogCachedBundle(
            catalogData: Data(#"{"schemaVersion":1}"#.utf8),
            signatureData: Data(#"{"schemaVersion":1}"#.utf8)
        )
    }

    private func assertUnsafe<T>(_ expression: @autoclosure () throws -> T) {
        XCTAssertThrowsError(try expression()) { error in
            XCTAssertEqual(error as? HomebrewCatalogCacheStoreError, .unsafeStorage)
        }
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    private func setPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path
        )
    }
}

private struct Fixture {
    let root: URL
    let store: HomebrewCatalogCacheStore

    init() throws {
        let unresolvedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: unresolvedRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        root = unresolvedRoot.resolvingSymlinksInPath()
        store = HomebrewCatalogCacheStore(
            directoryURL: root.appendingPathComponent("Homebrew", isDirectory: true)
        )
    }

    func createStorage() throws {
        try FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
