import Darwin
import Foundation
import SwanSongKit

@_silgen_name("flock")
private func swanSongFileLock(_ descriptor: Int32, _ operation: Int32) -> Int32

protocol HomebrewCatalogHighWaterStoring: Sendable {
    func load(catalogID: String) throws -> HomebrewCatalogHighWaterState?

    /// Commits `candidate` only if it is still monotonic relative to the
    /// durable state at commit time. Implementations must serialize the read,
    /// comparison, and write across processes.
    @discardableResult
    func advance(
        to candidate: HomebrewCatalogHighWaterState,
        publishingWhileLocked publication: @Sendable () throws -> Void
    ) throws -> HomebrewCatalogHighWaterState
}

extension HomebrewCatalogHighWaterStoring {
    @discardableResult
    func advance(
        to candidate: HomebrewCatalogHighWaterState
    ) throws -> HomebrewCatalogHighWaterState {
        try advance(to: candidate, publishingWhileLocked: {})
    }
}

enum HomebrewCatalogHighWaterStoreError: LocalizedError, Equatable {
    case corruptState
    case interprocessLock(Int32)
    case unsafeStorage

    var errorDescription: String? {
        switch self {
        case .corruptState:
            "The homebrew catalog anti-rollback state is invalid."
        case let .interprocessLock(code):
            "The homebrew catalog anti-rollback transaction could not be locked (\(code))."
        case .unsafeStorage:
            "The homebrew catalog trust folder is not a private folder owned by your account."
        }
    }
}

/// A BSD advisory lock whose ownership follows the open file description, so
/// separate SwanSong processes cannot interleave a high-water read and write.
/// The kernel releases the lock if a process exits or crashes.
struct HomebrewCatalogInterprocessLock: Sendable {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw HomebrewCatalogHighWaterStoreError.interprocessLock(errno)
        }

        let descriptor: Int32 = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.open(
                path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw HomebrewCatalogHighWaterStoreError.interprocessLock(errno)
        }
        defer { Darwin.close(descriptor) }

        var fileStatus = stat()
        guard fstat(descriptor, &fileStatus) == 0,
              fileStatus.st_uid == geteuid(),
              fileStatus.st_nlink == 1,
              fileStatus.st_mode & S_IFMT == S_IFREG else {
            throw HomebrewCatalogHighWaterStoreError.interprocessLock(EACCES)
        }

        while swanSongFileLock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                throw HomebrewCatalogHighWaterStoreError.interprocessLock(errno)
            }
        }
        defer { _ = swanSongFileLock(descriptor, LOCK_UN) }
        return try operation()
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("SwanSong", isDirectory: true)
            .appendingPathComponent("Trust", isDirectory: true)
            .appendingPathComponent("homebrew-catalog-high-water.lock")
    }
}

protocol HomebrewCatalogHighWaterBacking: Sendable {
    func load(catalogID: String) throws -> HomebrewCatalogHighWaterState?
    func store(_ state: HomebrewCatalogHighWaterState) throws
}

/// The transaction is generic so tests can exercise the exact production
/// locking and commit logic without reading or changing a user's trust state.
struct HomebrewCatalogLockedHighWaterStore<Backing: HomebrewCatalogHighWaterBacking>:
    HomebrewCatalogHighWaterStoring,
    Sendable {
    let backing: Backing
    let interprocessLock: HomebrewCatalogInterprocessLock

    func load(catalogID: String) throws -> HomebrewCatalogHighWaterState? {
        try interprocessLock.withExclusiveLock {
            try backing.load(catalogID: catalogID)
        }
    }

    @discardableResult
    func advance(
        to candidate: HomebrewCatalogHighWaterState,
        publishingWhileLocked publication: @Sendable () throws -> Void
    ) throws -> HomebrewCatalogHighWaterState {
        try validate(candidate)
        return try interprocessLock.withExclusiveLock {
            let current = try backing.load(catalogID: candidate.catalogID)
            let accepted = try monotonicState(candidate: candidate, current: current)
            if accepted != current {
                // Advance trust before publishing dependent cache bytes. A
                // crash between these writes may make the old cache unusable,
                // but it can never make a stale catalog trusted again.
                try backing.store(accepted)
                guard try backing.load(catalogID: candidate.catalogID) == accepted else {
                    throw HomebrewCatalogHighWaterStoreError.corruptState
                }
            }
            try publication()
            return accepted
        }
    }

    private func monotonicState(
        candidate: HomebrewCatalogHighWaterState,
        current: HomebrewCatalogHighWaterState?
    ) throws -> HomebrewCatalogHighWaterState {
        guard let current else { return candidate }
        try validate(current)
        guard candidate.highestRevision >= current.highestRevision else {
            throw HomebrewCatalogRollbackError.revisionDowngrade
        }
        if candidate.highestRevision == current.highestRevision {
            guard candidate.catalogSHA256 == current.catalogSHA256 else {
                throw HomebrewCatalogRollbackError.mutableRevision
            }
            return current
        }
        guard candidate.generatedAt >= current.generatedAt else {
            throw HomebrewCatalogRollbackError.nonmonotonicRevisionDate
        }
        return candidate
    }

    private func validate(_ state: HomebrewCatalogHighWaterState) throws {
        guard state.schemaVersion == HomebrewCatalogHighWaterState.schemaVersion,
              !state.catalogID.isEmpty,
              state.highestRevision >= 1,
              !state.catalogSHA256.isEmpty,
              !state.acceptedKeyID.isEmpty else {
            throw HomebrewCatalogHighWaterStoreError.corruptState
        }
    }
}

struct HomebrewCatalogFileHighWaterStore: HomebrewCatalogHighWaterStoring {
    private let transaction: HomebrewCatalogLockedHighWaterStore<
        HomebrewCatalogFileHighWaterBacking
    >

    init(
        stateURL: URL = HomebrewCatalogFileHighWaterBacking.defaultStateURL,
        lockURL: URL = HomebrewCatalogInterprocessLock.defaultFileURL
    ) {
        transaction = HomebrewCatalogLockedHighWaterStore(
            backing: HomebrewCatalogFileHighWaterBacking(stateURL: stateURL),
            interprocessLock: HomebrewCatalogInterprocessLock(fileURL: lockURL)
        )
    }

    func load(catalogID: String) throws -> HomebrewCatalogHighWaterState? {
        try transaction.load(catalogID: catalogID)
    }

    @discardableResult
    func advance(
        to candidate: HomebrewCatalogHighWaterState,
        publishingWhileLocked publication: @Sendable () throws -> Void
    ) throws -> HomebrewCatalogHighWaterState {
        try transaction.advance(
            to: candidate,
            publishingWhileLocked: publication
        )
    }
}

struct HomebrewCatalogFileHighWaterBacking: HomebrewCatalogHighWaterBacking {
    let stateURL: URL

    static var defaultStateURL: URL {
        HomebrewCatalogInterprocessLock.defaultFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("homebrew-catalog-high-water-v3.json")
    }

    func load(catalogID: String) throws -> HomebrewCatalogHighWaterState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        try validatePrivateRegularFile(stateURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(
            HomebrewCatalogHighWaterState.self,
            from: Data(contentsOf: stateURL, options: [.mappedIfSafe])
        ),
        state.schemaVersion == HomebrewCatalogHighWaterState.schemaVersion,
        state.catalogID == catalogID else {
            throw HomebrewCatalogHighWaterStoreError.corruptState
        }
        return state
    }

    func store(_ state: HomebrewCatalogHighWaterState) throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try validatePrivateDirectory(directory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw HomebrewCatalogHighWaterStoreError.corruptState
        }

        try data.write(to: stateURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateURL.path
        )
        try validatePrivateRegularFile(stateURL)
    }

    private func validatePrivateDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              attributes[.ownerAccountID] as? NSNumber == NSNumber(value: geteuid()) else {
            throw HomebrewCatalogHighWaterStoreError.unsafeStorage
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func validatePrivateRegularFile(_ url: URL) throws {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & S_IFMT == S_IFREG else {
            throw HomebrewCatalogHighWaterStoreError.unsafeStorage
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
