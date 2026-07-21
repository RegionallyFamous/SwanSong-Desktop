import Foundation
import SwanSongKit
@testable import SwanSongApp
import XCTest

final class HomebrewCatalogHighWaterStoreTests: XCTestCase {
    func testProductionFileStoreUsesPrivateOwnerOnlyFiles() throws {
        let fixture = try HighWaterFixture()
        defer { fixture.remove() }
        let store = HomebrewCatalogFileHighWaterStore(
            stateURL: fixture.stateURL,
            lockURL: fixture.lockURL
        )
        let expected = state(revision: 3)
        XCTAssertEqual(try store.advance(to: expected), expected)
        XCTAssertEqual(try store.load(catalogID: expected.catalogID), expected)

        let statePermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: fixture.stateURL.path)[.posixPermissions]
                as? NSNumber
        )
        let directoryPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: fixture.rootURL.path)[.posixPermissions]
                as? NSNumber
        )
        XCTAssertEqual(statePermissions.intValue & 0o777, 0o600)
        XCTAssertEqual(directoryPermissions.intValue & 0o777, 0o700)
    }

    func testCompetingStoreInstancesCannotCommitARevisionRollback() async throws {
        let fixture = try HighWaterFixture()
        defer { fixture.remove() }
        let first = fixture.store()
        let second = fixture.store()

        for revision in stride(from: 1, through: 100, by: 2) {
            let lower = state(revision: revision)
            let higher = state(revision: revision + 1)
            let lowerTask = Task.detached {
                try? first.advance(to: lower)
            }
            let higherTask = Task.detached {
                try? second.advance(to: higher)
            }
            _ = await (lowerTask.value, higherTask.value)

            XCTAssertEqual(
                try first.load(catalogID: lower.catalogID)?.highestRevision,
                revision + 1
            )
        }

        XCTAssertThrowsError(try second.advance(to: state(revision: 99))) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogRollbackError,
                .revisionDowngrade
            )
        }
        XCTAssertEqual(
            try first.load(catalogID: "first-party-homebrew")?.highestRevision,
            100
        )
    }

    func testEqualRevisionWithDifferentBytesFailsClosedAtCommitTime() throws {
        let fixture = try HighWaterFixture()
        defer { fixture.remove() }
        let first = fixture.store()
        let second = fixture.store()
        _ = try first.advance(to: state(revision: 4, digest: "aaaa"))

        XCTAssertThrowsError(
            try second.advance(to: state(revision: 4, digest: "bbbb"))
        ) { error in
            XCTAssertEqual(
                error as? HomebrewCatalogRollbackError,
                .mutableRevision
            )
        }
        XCTAssertEqual(
            try first.load(catalogID: "first-party-homebrew")?.catalogSHA256,
            "aaaa"
        )
    }

    func testStaleCompetingPublisherCannotOverwriteNewerCache() async throws {
        let fixture = try HighWaterFixture()
        defer { fixture.remove() }
        let newerStore = fixture.store()
        let staleStore = fixture.store()
        let cacheURL = fixture.rootURL.appendingPathComponent("catalog-cache")
        let newerHasPublished = DispatchSemaphore(value: 0)
        let releaseNewerTransaction = DispatchSemaphore(value: 0)

        let newerTask = Task.detached {
            try newerStore.advance(
                to: stateForTest(revision: 8),
                publishingWhileLocked: {
                    try Data("revision-8".utf8).write(
                        to: cacheURL,
                        options: .atomic
                    )
                    newerHasPublished.signal()
                    releaseNewerTransaction.wait()
                }
            )
        }
        XCTAssertEqual(newerHasPublished.wait(timeout: .now() + 2), .success)

        let staleTask = Task.detached { () -> HomebrewCatalogRollbackError? in
            do {
                try staleStore.advance(
                    to: stateForTest(revision: 7),
                    publishingWhileLocked: {
                        try Data("revision-7".utf8).write(
                            to: cacheURL,
                            options: .atomic
                        )
                    }
                )
                return nil
            } catch let error as HomebrewCatalogRollbackError {
                return error
            }
        }
        releaseNewerTransaction.signal()

        _ = try await newerTask.value
        let staleResult = try await staleTask.value
        XCTAssertEqual(staleResult, .revisionDowngrade)
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: cacheURL), as: UTF8.self),
            "revision-8"
        )
        XCTAssertEqual(
            try newerStore.load(catalogID: "first-party-homebrew")?.highestRevision,
            8
        )
    }

    func testInterprocessLockWaitsForExternalProcessOwner() async throws {
        let fixture = try HighWaterFixture()
        defer { fixture.remove() }
        let readyURL = fixture.rootURL.appendingPathComponent("child-ready")
        let releaseURL = fixture.rootURL.appendingPathComponent("child-release")
        let acquiredURL = fixture.rootURL.appendingPathComponent("swift-acquired")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            "-c",
            """
            import fcntl, os, pathlib, sys, time
            lock, ready, release = sys.argv[1:]
            fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
            fcntl.flock(fd, fcntl.LOCK_EX)
            pathlib.Path(ready).touch()
            while not pathlib.Path(release).exists():
                time.sleep(0.005)
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
            """,
            fixture.lockURL.path,
            readyURL.path,
            releaseURL.path,
        ]
        try process.run()
        defer {
            try? Data().write(to: releaseURL, options: .atomic)
            if process.isRunning { process.terminate() }
        }
        try await waitForFile(readyURL)

        let lock = HomebrewCatalogInterprocessLock(fileURL: fixture.lockURL)
        let waiter = Task.detached {
            try lock.withExclusiveLock {
                try Data().write(to: acquiredURL, options: .atomic)
            }
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: acquiredURL.path),
            "Swift entered the transaction while another process owned the lock."
        )

        try Data().write(to: releaseURL, options: .atomic)
        try await waiter.value
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: acquiredURL.path))
    }

    private func state(
        revision: Int,
        digest: String? = nil
    ) -> HomebrewCatalogHighWaterState {
        HomebrewCatalogHighWaterState(
            catalogID: "first-party-homebrew",
            highestRevision: revision,
            catalogSHA256: digest ?? "digest-\(revision)",
            generatedAt: Date(timeIntervalSince1970: TimeInterval(revision)),
            acceptedKeyID: "test-key"
        )
    }

    private func waitForFile(_ url: URL) async throws {
        for _ in 0..<400 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CocoaError(.fileReadUnknown)
    }
}

private func stateForTest(revision: Int) -> HomebrewCatalogHighWaterState {
    HomebrewCatalogHighWaterState(
        catalogID: "first-party-homebrew",
        highestRevision: revision,
        catalogSHA256: "digest-\(revision)",
        generatedAt: Date(timeIntervalSince1970: TimeInterval(revision)),
        acceptedKeyID: "test-key"
    )
}

private struct HighWaterFixture {
    let rootURL: URL
    let stateURL: URL
    let lockURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwanSongHighWaterTests-\(UUID().uuidString)")
        stateURL = rootURL.appendingPathComponent("state.json")
        lockURL = rootURL.appendingPathComponent("transaction.lock")
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    func store() -> HomebrewCatalogLockedHighWaterStore<TestFileHighWaterBacking> {
        HomebrewCatalogLockedHighWaterStore(
            backing: TestFileHighWaterBacking(stateURL: stateURL),
            interprocessLock: HomebrewCatalogInterprocessLock(fileURL: lockURL)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct TestFileHighWaterBacking: HomebrewCatalogHighWaterBacking {
    let stateURL: URL

    func load(catalogID: String) throws -> HomebrewCatalogHighWaterState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(
            HomebrewCatalogHighWaterState.self,
            from: Data(contentsOf: stateURL)
        )
        return state.catalogID == catalogID ? state : nil
    }

    func store(_ state: HomebrewCatalogHighWaterState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }
}
