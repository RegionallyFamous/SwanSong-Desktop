import Darwin
import Foundation
import Security
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
    case keychain(OSStatus)
    case corruptState
    case interprocessLock(Int32)

    var errorDescription: String? {
        switch self {
        case .keychain:
            "SwanSong couldn’t safely save Homebrew’s catalog check in your Mac’s Keychain. Make sure your Mac is unlocked, then try again."
        case .corruptState:
            "The homebrew catalog anti-rollback state in Keychain is invalid."
        case let .interprocessLock(code):
            "The homebrew catalog anti-rollback transaction could not be locked (\(code))."
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

    private static var defaultFileURL: URL {
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
/// locking and commit logic without reading or changing a developer's Keychain.
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

struct HomebrewCatalogKeychainHighWaterStore: HomebrewCatalogHighWaterStoring {
    private let transaction: HomebrewCatalogLockedHighWaterStore<
        HomebrewCatalogKeychainHighWaterBacking
    >

    init() {
        transaction = HomebrewCatalogLockedHighWaterStore(
            backing: HomebrewCatalogKeychainHighWaterBacking(),
            interprocessLock: HomebrewCatalogInterprocessLock()
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

struct HomebrewCatalogKeychainHighWaterBacking: HomebrewCatalogHighWaterBacking {
    private static let service = "com.regionallyfamous.SwanSong.HomebrewCatalogTrust"

    func load(catalogID: String) throws -> HomebrewCatalogHighWaterState? {
        var query = baseQuery(catalogID: catalogID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw HomebrewCatalogHighWaterStoreError.keychain(status)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(
            HomebrewCatalogHighWaterState.self,
            from: data
        ),
        state.schemaVersion == HomebrewCatalogHighWaterState.schemaVersion,
        state.catalogID == catalogID else {
            throw HomebrewCatalogHighWaterStoreError.corruptState
        }
        return state
    }

    func store(_ state: HomebrewCatalogHighWaterState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw HomebrewCatalogHighWaterStoreError.corruptState
        }

        let query = baseQuery(catalogID: state.catalogID)
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(
            query as CFDictionary,
            update as CFDictionary
        )
        if status == errSecItemNotFound {
            let insertion = insertionQuery(
                catalogID: state.catalogID,
                data: data
            )
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw HomebrewCatalogHighWaterStoreError.keychain(status)
        }
    }

    /// SwanSong is distributed directly with Developer ID and does not ship a
    /// provisioning profile. On macOS, opting into the data-protection
    /// Keychain without its provisioned application-identifier entitlement
    /// fails every operation with `errSecMissingEntitlement` (-34018).
    ///
    /// The traditional macOS Keychain remains encrypted and ACL-protected, and
    /// is the entitlement-free Keychain intended for this distribution model.
    /// Keep this query free of data-protection-only attributes so notarized
    /// builds can persist the anti-rollback record they require.
    func baseQuery(catalogID: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: catalogID,
        ]
    }

    func insertionQuery(
        catalogID: String,
        data: Data
    ) -> [CFString: Any] {
        var query = baseQuery(catalogID: catalogID)
        query[kSecValueData] = data
        return query
    }
}
