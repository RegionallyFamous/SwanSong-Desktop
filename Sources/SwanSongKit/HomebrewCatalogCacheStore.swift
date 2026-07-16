import Darwin
import Foundation

public enum HomebrewCatalogCacheStoreError: LocalizedError, Equatable, Sendable {
    case invalidSignedBundle
    case unsafeStorage
    case corruptCache

    public var errorDescription: String? {
        switch self {
        case .invalidSignedBundle:
            "The authenticated homebrew catalog cache bundle is invalid or exceeds its size limit."
        case .unsafeStorage:
            "The homebrew catalog cache is not a private, regular file."
        case .corruptCache:
            "The cached homebrew catalog is incomplete or exceeds the cache size limit."
        }
    }
}

public struct HomebrewCatalogCachedBundle: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let catalogData: Data
    public let signatureData: Data

    public init(catalogData: Data, signatureData: Data) {
        self.schemaVersion = Self.schemaVersion
        self.catalogData = catalogData
        self.signatureData = signatureData
    }
}

/// Atomic private storage for the exact catalog bytes and their detached
/// signature. Loading this container never implies authenticity: callers must
/// reverify `signatureData` over `catalogData` every time it is opened.
public struct HomebrewCatalogCacheStore: Sendable {
    public static let maximumByteCount = 1_500_000
    public static let cacheFileName = "SignedCatalog-v1.cache.json"
    public static let legacyUnsignedCacheFileName = "Catalog-v1.json"

    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let dataRoot = SwanSongDataRootPolicy.defaultResolution(
            fileManager: fileManager
        ).rootURL
        return Self(
            directoryURL: dataRoot.appendingPathComponent(
                "Homebrew",
                isDirectory: true
            )
        )
    }

    public var cacheURL: URL {
        directoryURL.appendingPathComponent(Self.cacheFileName)
    }

    /// Returns the untrusted wire bundle, or `nil` when no signed cache has
    /// been written. The legacy unsigned cache filename is never consulted.
    public func load() throws -> HomebrewCatalogCachedBundle? {
        guard try storageExistsForLoading() else { return nil }

        var pathStatus = stat()
        let pathResult = cacheURL.path.withCString {
            Darwin.lstat($0, &pathStatus)
        }
        guard pathResult == 0 else {
            if errno == ENOENT { return nil }
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        guard Self.isPrivateRegularFile(pathStatus) else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }

        let descriptor = cacheURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        let reader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? reader.close() }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              Self.isPrivateRegularFile(before) else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        guard before.st_size > 0,
              before.st_size <= off_t(Self.maximumByteCount) else {
            throw HomebrewCatalogCacheStoreError.corruptCache
        }

        let data: Data
        do {
            data = try readBounded(from: reader)
        } catch let error as HomebrewCatalogCacheStoreError {
            throw error
        } catch {
            throw HomebrewCatalogCacheStoreError.corruptCache
        }

        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              Self.isPrivateRegularFile(after) else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        guard before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size),
              !data.isEmpty,
              data.count <= Self.maximumByteCount else {
            throw HomebrewCatalogCacheStoreError.corruptCache
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HomebrewCatalogCacheStoreError.corruptCache
        }
        guard let root = object as? [String: Any],
              Set(root.keys) == ["schemaVersion", "catalogData", "signatureData"] else {
            throw HomebrewCatalogCacheStoreError.corruptCache
        }
        let bundle: HomebrewCatalogCachedBundle
        do {
            bundle = try JSONDecoder().decode(
                HomebrewCatalogCachedBundle.self,
                from: data
            )
        } catch {
            throw HomebrewCatalogCacheStoreError.corruptCache
        }
        guard bundle.schemaVersion == HomebrewCatalogCachedBundle.schemaVersion,
              !bundle.catalogData.isEmpty,
              bundle.catalogData.count <= HomebrewCatalogValidator.maximumCatalogByteCount,
              !bundle.signatureData.isEmpty,
              bundle.signatureData.count <= HomebrewCatalogSignatureEnvelope.maximumByteCount else {
            throw HomebrewCatalogCacheStoreError.corruptCache
        }
        return bundle
    }

    /// Atomically replaces both detached artifacts in one cache transaction.
    /// The caller must authenticate and validate them before calling this API.
    @discardableResult
    public func store(_ bundle: HomebrewCatalogCachedBundle) throws -> URL {
        guard bundle.schemaVersion == HomebrewCatalogCachedBundle.schemaVersion,
              !bundle.catalogData.isEmpty,
              bundle.catalogData.count <= HomebrewCatalogValidator.maximumCatalogByteCount,
              !bundle.signatureData.isEmpty,
              bundle.signatureData.count <= HomebrewCatalogSignatureEnvelope.maximumByteCount else {
            throw HomebrewCatalogCacheStoreError.invalidSignedBundle
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(bundle)
        } catch {
            throw HomebrewCatalogCacheStoreError.invalidSignedBundle
        }
        guard data.count <= Self.maximumByteCount else {
            throw HomebrewCatalogCacheStoreError.invalidSignedBundle
        }

        try prepareStorage()
        try validateReplaceableCacheIfPresent()

        let temporary = directoryURL.appendingPathComponent(
            ".catalog-write-\(UUID().uuidString).tmp"
        )
        let descriptor = temporary.path.withCString {
            Darwin.open(
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var committed = false
        defer {
            try? writer.close()
            if !committed {
                try? FileManager.default.removeItem(at: temporary)
            }
        }

        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        do {
            try writer.write(contentsOf: data)
            try writer.synchronize()
            try writer.close()
        } catch {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }

        try validatePrivateRegularFile(at: temporary, byteCount: data.count)
        try validateExistingStorage()
        try validateReplaceableCacheIfPresent()
        try Self.atomicRename(from: temporary, to: cacheURL)
        committed = true
        try validatePrivateRegularFile(at: cacheURL, byteCount: data.count)
        try synchronizeDirectory()
        return cacheURL
    }

    /// Removes only the authenticated catalog cache. The anti-rollback high
    /// water mark is intentionally stored separately and must survive cache
    /// deletion so an older signed revision cannot be reintroduced later.
    @discardableResult
    public func remove() throws -> Bool {
        guard try storageExistsForLoading() else { return false }

        var status = stat()
        let result = cacheURL.path.withCString { Darwin.lstat($0, &status) }
        if result != 0 {
            if errno == ENOENT { return false }
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        guard Self.isPrivateRegularFile(status) else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        guard cacheURL.path.withCString({ Darwin.unlink($0) }) == 0 else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        try synchronizeDirectory()
        return true
    }

    private func storageExistsForLoading() throws -> Bool {
        var status = stat()
        let result = directoryURL.path.withCString {
            Darwin.lstat($0, &status)
        }
        guard result == 0 else {
            if errno == ENOENT { return false }
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        guard Self.isPrivateDirectory(status) else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        try validateParentDirectory()
        return true
    }

    private func prepareStorage() throws {
        let fileManager = FileManager.default
        let parent = directoryURL.deletingLastPathComponent()

        var parentStatus = stat()
        let parentResult = parent.path.withCString {
            Darwin.lstat($0, &parentStatus)
        }
        if parentResult != 0 {
            guard errno == ENOENT else {
                throw HomebrewCatalogCacheStoreError.unsafeStorage
            }
            do {
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw HomebrewCatalogCacheStoreError.unsafeStorage
            }
        }
        try validateParentDirectory()

        var directoryStatus = stat()
        let directoryResult = directoryURL.path.withCString {
            Darwin.lstat($0, &directoryStatus)
        }
        if directoryResult != 0 {
            guard errno == ENOENT else {
                throw HomebrewCatalogCacheStoreError.unsafeStorage
            }
            do {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw HomebrewCatalogCacheStoreError.unsafeStorage
            }
        }

        guard directoryURL.path.withCString({
            Darwin.lstat($0, &directoryStatus)
        }) == 0,
        (directoryStatus.st_mode & S_IFMT) == S_IFDIR,
        directoryStatus.st_uid == getuid() else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        if Int(directoryStatus.st_mode & 0o777) != 0o700 {
            guard directoryURL.path.withCString({
                Darwin.chmod($0, 0o700)
            }) == 0 else {
                throw HomebrewCatalogCacheStoreError.unsafeStorage
            }
        }
        try validateExistingStorage()
    }

    private func validateExistingStorage() throws {
        try validateParentDirectory()
        var status = stat()
        guard directoryURL.path.withCString({
            Darwin.lstat($0, &status)
        }) == 0,
        Self.isPrivateDirectory(status) else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
    }

    private func validateParentDirectory() throws {
        let parent = directoryURL.deletingLastPathComponent()
        var status = stat()
        guard parent.path.withCString({ Darwin.lstat($0, &status) }) == 0,
              (status.st_mode & S_IFMT) == S_IFDIR,
              status.st_uid == getuid() else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
    }

    private func validateReplaceableCacheIfPresent() throws {
        var status = stat()
        let result = cacheURL.path.withCString { Darwin.lstat($0, &status) }
        if result != 0 {
            if errno == ENOENT { return }
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        guard Self.isPrivateRegularFile(status) else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
    }

    private func validatePrivateRegularFile(
        at url: URL,
        byteCount: Int
    ) throws {
        var status = stat()
        guard url.path.withCString({ Darwin.lstat($0, &status) }) == 0,
              Self.isPrivateRegularFile(status),
              Int(status.st_size) == byteCount else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
    }

    private func readBounded(from reader: FileHandle) throws -> Data {
        var data = Data()
        while true {
            let remaining = Self.maximumByteCount + 1 - data.count
            guard remaining > 0 else {
                throw HomebrewCatalogCacheStoreError.corruptCache
            }
            let chunk = try reader.read(
                upToCount: min(64 * 1_024, remaining)
            ) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > Self.maximumByteCount {
                throw HomebrewCatalogCacheStoreError.corruptCache
            }
        }
        return data
    }

    private func synchronizeDirectory() throws {
        let descriptor = directoryURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
    }

    private static func isPrivateDirectory(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFDIR
            && status.st_uid == getuid()
            && Int(status.st_mode & 0o777) == 0o700
    }

    private static func isPrivateRegularFile(_ status: stat) -> Bool {
        (status.st_mode & S_IFMT) == S_IFREG
            && status.st_uid == getuid()
            && status.st_nlink == 1
            && Int(status.st_mode & 0o777) == 0o600
    }

    private static func atomicRename(from source: URL, to destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw HomebrewCatalogCacheStoreError.unsafeStorage
        }
    }
}
