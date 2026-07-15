import CryptoKit
import Darwin
import Foundation

public enum GameArtworkSource: String, Codable, Equatable, Sendable {
    case automatic
    case userSelected
}

public struct GameArtworkManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generation: UUID
    public let gameID: UUID
    public let romChecksum: UInt16
    public let romFileSize: UInt64
    public let frameNumber: UInt64
    public let width: Int
    public let height: Int
    public let isVertical: Bool
    public let capturedAt: Date
    public let source: GameArtworkSource
    public let pngByteCount: Int
    public let pngSHA256: String

    public init(
        schemaVersion: Int = 1,
        generation: UUID = UUID(),
        gameID: UUID,
        romChecksum: UInt16,
        romFileSize: UInt64,
        frameNumber: UInt64,
        width: Int,
        height: Int,
        isVertical: Bool,
        capturedAt: Date = Date(),
        source: GameArtworkSource,
        pngByteCount: Int,
        pngSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.gameID = gameID
        self.romChecksum = romChecksum
        self.romFileSize = romFileSize
        self.frameNumber = frameNumber
        self.width = width
        self.height = height
        self.isVertical = isVertical
        self.capturedAt = capturedAt
        self.source = source
        self.pngByteCount = pngByteCount
        self.pngSHA256 = pngSHA256
    }
}

public struct GameArtworkRecord: Equatable, Sendable {
    public let manifest: GameArtworkManifest
    public let pngData: Data

    public init(manifest: GameArtworkManifest, pngData: Data) {
        self.manifest = manifest
        self.pngData = pngData
    }
}

public enum GameArtworkStoreError: LocalizedError, Equatable, Sendable {
    case imageTooLarge(maximumByteCount: Int, actualByteCount: Int)
    case invalidPNG
    case invalidMetadata
    case corruptArtwork
    case unsafeStorage

    public var errorDescription: String? {
        switch self {
        case let .imageTooLarge(maximum, actual):
            "The library artwork is \(actual) bytes; at most \(maximum) bytes are allowed."
        case .invalidPNG:
            "The library artwork is not a valid PNG image."
        case .invalidMetadata:
            "The library artwork metadata is invalid."
        case .corruptArtwork:
            "The saved library artwork is damaged or incomplete."
        case .unsafeStorage:
            "The library-artwork location is not private and safe."
        }
    }
}

/// Stores small, locally generated game-raster thumbnails independently from
/// Library.json. The manifest is committed last, so a reader observes either
/// the previous complete generation or the new complete generation.
public struct GameArtworkStore: Sendable {
    public static let maximumPNGByteCount = 2 * 1_024 * 1_024

    private static let manifestFileName = "Manifest.json"
    private static let maximumManifestByteCount = 64 * 1_024
    private static let maximumRasterDimension = 512

    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let root = SwanSongDataRootPolicy.defaultResolution(fileManager: fileManager).rootURL
        return Self(
            rootURL: root
                .appendingPathComponent("Artwork", isDirectory: true)
        )
    }

    @discardableResult
    public func save(
        _ pngData: Data,
        gameID: UUID,
        romChecksum: UInt16,
        romFileSize: UInt64,
        frameNumber: UInt64,
        isVertical: Bool,
        source: GameArtworkSource,
        capturedAt: Date = Date()
    ) throws -> GameArtworkRecord {
        guard pngData.count <= Self.maximumPNGByteCount else {
            throw GameArtworkStoreError.imageTooLarge(
                maximumByteCount: Self.maximumPNGByteCount,
                actualByteCount: pngData.count
            )
        }
        let dimensions = try Self.validatePNG(pngData)
        guard
            romFileSize > 0,
            dimensions.width > 0,
            dimensions.height > 0,
            dimensions.width != dimensions.height,
            isVertical == (dimensions.height > dimensions.width)
        else {
            throw GameArtworkStoreError.invalidMetadata
        }

        try prepareStorage()
        let gameDirectory = try prepareGameDirectory(gameID: gameID)
        let priorManifest = try? readManifest(in: gameDirectory)
        let manifest = GameArtworkManifest(
            gameID: gameID,
            romChecksum: romChecksum,
            romFileSize: romFileSize,
            frameNumber: frameNumber,
            width: dimensions.width,
            height: dimensions.height,
            isVertical: isVertical,
            capturedAt: capturedAt,
            source: source,
            pngByteCount: pngData.count,
            pngSHA256: Self.sha256(pngData)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        guard manifestData.count <= Self.maximumManifestByteCount else {
            throw GameArtworkStoreError.invalidMetadata
        }

        let pngURL = artworkURL(for: manifest.generation, in: gameDirectory)
        let pngTemporary = gameDirectory.appendingPathComponent(
            ".artwork-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let manifestURL = gameDirectory.appendingPathComponent(
            Self.manifestFileName,
            isDirectory: false
        )
        let manifestTemporary = gameDirectory.appendingPathComponent(
            ".manifest-\(UUID().uuidString).tmp",
            isDirectory: false
        )

        var pngCommitted = false
        var manifestCommitted = false
        defer {
            try? FileManager.default.removeItem(at: pngTemporary)
            try? FileManager.default.removeItem(at: manifestTemporary)
            if pngCommitted, !manifestCommitted,
               (try? secureRegularFileIfPresent(at: pngURL)) == true {
                try? FileManager.default.removeItem(at: pngURL)
            }
        }

        try writePrivateFile(pngData, to: pngTemporary)
        try validateGameDirectory(gameDirectory, gameID: gameID)
        guard try !secureRegularFileIfPresent(at: pngURL) else {
            throw GameArtworkStoreError.unsafeStorage
        }
        try Self.atomicRename(from: pngTemporary, to: pngURL)
        pngCommitted = true
        try synchronizeDirectory(gameDirectory)

        try writePrivateFile(manifestData, to: manifestTemporary)
        try validateGameDirectory(gameDirectory, gameID: gameID)
        _ = try secureRegularFileIfPresent(at: manifestURL, repairPermissions: true)
        try Self.atomicRename(from: manifestTemporary, to: manifestURL)
        manifestCommitted = true
        try synchronizeDirectory(gameDirectory)

        if let priorManifest, priorManifest.generation != manifest.generation {
            let oldArtwork = artworkURL(for: priorManifest.generation, in: gameDirectory)
            if try secureRegularFileIfPresent(at: oldArtwork) {
                try? FileManager.default.removeItem(at: oldArtwork)
            }
        }

        return GameArtworkRecord(manifest: manifest, pngData: pngData)
    }

    /// Returns nil when no artwork exists or when it belongs to an older ROM
    /// at this library identity. Malformed or unsafe stored data is an error.
    public func load(
        gameID: UUID,
        romChecksum: UInt16,
        romFileSize: UInt64
    ) throws -> GameArtworkRecord? {
        guard try storageExists() else { return nil }
        let gameDirectory = directoryURL(for: gameID)
        guard try itemStatusIfPresent(at: gameDirectory) != nil else { return nil }
        try validateGameDirectory(gameDirectory, gameID: gameID)

        let manifestURL = gameDirectory.appendingPathComponent(
            Self.manifestFileName,
            isDirectory: false
        )
        guard try secureRegularFileIfPresent(
            at: manifestURL,
            repairPermissions: true
        ) else { return nil }
        let manifest = try readManifest(in: gameDirectory)
        try validate(manifest, expectedGameID: gameID)
        guard
            manifest.romChecksum == romChecksum,
            manifest.romFileSize == romFileSize
        else { return nil }

        let pngURL = artworkURL(for: manifest.generation, in: gameDirectory)
        guard try secureRegularFileIfPresent(
            at: pngURL,
            repairPermissions: true
        ) else {
            throw GameArtworkStoreError.corruptArtwork
        }
        let pngData = try readPrivateFile(
            at: pngURL,
            maximumByteCount: Self.maximumPNGByteCount
        )
        guard
            pngData.count == manifest.pngByteCount,
            Self.sha256(pngData) == manifest.pngSHA256
        else {
            throw GameArtworkStoreError.corruptArtwork
        }
        let dimensions: (width: Int, height: Int)
        do {
            dimensions = try Self.validatePNG(pngData)
        } catch {
            throw GameArtworkStoreError.corruptArtwork
        }
        guard
            dimensions.width == manifest.width,
            dimensions.height == manifest.height,
            manifest.isVertical == (dimensions.height > dimensions.width)
        else {
            throw GameArtworkStoreError.corruptArtwork
        }
        return GameArtworkRecord(manifest: manifest, pngData: pngData)
    }

    public func remove(gameID: UUID) throws {
        guard try storageExists() else { return }
        let gameDirectory = directoryURL(for: gameID)
        guard try itemStatusIfPresent(at: gameDirectory) != nil else { return }
        try validateGameDirectory(gameDirectory, gameID: gameID)
        try FileManager.default.removeItem(at: gameDirectory)
        try synchronizeDirectory(rootURL)
    }

    @discardableResult
    public func prepareStorage() throws -> URL {
        let fileManager = FileManager.default
        let parent = rootURL.deletingLastPathComponent()
        if try itemStatusIfPresent(at: parent) == nil {
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard try secureDirectoryIfPresent(at: parent) else {
            throw GameArtworkStoreError.unsafeStorage
        }
        if try itemStatusIfPresent(at: rootURL) == nil {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard try secureDirectoryIfPresent(
            at: rootURL,
            requiredPermissions: 0o700,
            repairPermissions: true
        ) else {
            throw GameArtworkStoreError.unsafeStorage
        }
        return rootURL
    }

    public func directoryURL(for gameID: UUID) -> URL {
        rootURL.appendingPathComponent(gameID.uuidString, isDirectory: true)
    }

    private func prepareGameDirectory(gameID: UUID) throws -> URL {
        let directory = directoryURL(for: gameID)
        if try itemStatusIfPresent(at: directory) == nil {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try validateGameDirectory(directory, gameID: gameID)
        return directory
    }

    private func storageExists() throws -> Bool {
        guard try itemStatusIfPresent(at: rootURL) != nil else { return false }
        try validateExistingStorage()
        return true
    }

    private func validateExistingStorage() throws {
        let parent = rootURL.deletingLastPathComponent()
        guard
            try secureDirectoryIfPresent(at: parent),
            try secureDirectoryIfPresent(
                at: rootURL,
                requiredPermissions: 0o700,
                repairPermissions: true
            )
        else {
            throw GameArtworkStoreError.unsafeStorage
        }
    }

    private func validateGameDirectory(_ directory: URL, gameID: UUID) throws {
        guard directory == directoryURL(for: gameID),
              try secureDirectoryIfPresent(
                at: directory,
                requiredPermissions: 0o700,
                repairPermissions: true
              ) else {
            throw GameArtworkStoreError.unsafeStorage
        }
    }

    private func readManifest(in directory: URL) throws -> GameArtworkManifest {
        let url = directory.appendingPathComponent(
            Self.manifestFileName,
            isDirectory: false
        )
        guard try secureRegularFileIfPresent(
            at: url,
            repairPermissions: true
        ) else {
            throw GameArtworkStoreError.corruptArtwork
        }
        let data = try readPrivateFile(
            at: url,
            maximumByteCount: Self.maximumManifestByteCount
        )
        do {
            return try JSONDecoder().decode(GameArtworkManifest.self, from: data)
        } catch {
            throw GameArtworkStoreError.corruptArtwork
        }
    }

    private func validate(
        _ manifest: GameArtworkManifest,
        expectedGameID: UUID
    ) throws {
        guard
            manifest.schemaVersion == 1,
            manifest.gameID == expectedGameID,
            manifest.romFileSize > 0,
            manifest.pngByteCount > 0,
            manifest.pngByteCount <= Self.maximumPNGByteCount,
            manifest.width > 0,
            manifest.height > 0,
            manifest.width != manifest.height,
            manifest.width <= Self.maximumRasterDimension,
            manifest.height <= Self.maximumRasterDimension,
            manifest.isVertical == (manifest.height > manifest.width),
            manifest.pngSHA256.count == 64,
            manifest.pngSHA256.allSatisfy(\.isHexDigit)
        else {
            throw GameArtworkStoreError.corruptArtwork
        }
    }

    private func artworkURL(for generation: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(
            "\(generation.uuidString).png",
            isDirectory: false
        )
    }

    private func writePrivateFile(_ data: Data, to url: URL) throws {
        let descriptor = url.path.withCString { path in
            Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        guard try secureRegularFileIfPresent(at: url) else {
            throw GameArtworkStoreError.unsafeStorage
        }
    }

    private func readPrivateFile(
        at url: URL,
        maximumByteCount: Int
    ) throws -> Data {
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP { throw GameArtworkStoreError.unsafeStorage }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard
            fstat(descriptor, &status) == 0,
            Self.fileType(status.st_mode) == S_IFREG,
            status.st_uid == getuid(),
            status.st_nlink == 1,
            status.st_size >= 0,
            UInt64(status.st_size) <= UInt64(maximumByteCount)
        else {
            throw GameArtworkStoreError.unsafeStorage
        }
        if Self.permissions(status.st_mode) != 0o600 {
            guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0,
                  fstat(descriptor, &status) == 0,
                  Self.permissions(status.st_mode) == 0o600 else {
                throw GameArtworkStoreError.unsafeStorage
            }
        }
        let data = try handle.readToEnd() ?? Data()
        guard data.count <= maximumByteCount else {
            throw GameArtworkStoreError.unsafeStorage
        }
        return data
    }

    private func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func itemStatusIfPresent(at url: URL) throws -> stat? {
        var status = stat()
        let result = url.path.withCString { path in
            Darwin.lstat(path, &status)
        }
        if result == 0 { return status }
        if errno == ENOENT { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    @discardableResult
    private func secureDirectoryIfPresent(
        at url: URL,
        requiredPermissions: mode_t? = nil,
        repairPermissions: Bool = false
    ) throws -> Bool {
        guard var status = try itemStatusIfPresent(at: url) else { return false }
        guard Self.fileType(status.st_mode) == S_IFDIR,
              status.st_uid == getuid() else {
            throw GameArtworkStoreError.unsafeStorage
        }
        if let requiredPermissions,
           Self.permissions(status.st_mode) != requiredPermissions,
           repairPermissions {
            guard url.path.withCString({ Darwin.chmod($0, requiredPermissions) }) == 0,
                  let repaired = try itemStatusIfPresent(at: url) else {
                throw GameArtworkStoreError.unsafeStorage
            }
            status = repaired
        }
        if let requiredPermissions,
           Self.permissions(status.st_mode) != requiredPermissions {
            throw GameArtworkStoreError.unsafeStorage
        }
        return true
    }

    @discardableResult
    private func secureRegularFileIfPresent(
        at url: URL,
        repairPermissions: Bool = false
    ) throws -> Bool {
        guard var status = try itemStatusIfPresent(at: url) else { return false }
        guard
            Self.fileType(status.st_mode) == S_IFREG,
            status.st_uid == getuid(),
            status.st_nlink == 1
        else {
            throw GameArtworkStoreError.unsafeStorage
        }
        if Self.permissions(status.st_mode) != 0o600, repairPermissions {
            guard url.path.withCString({ Darwin.chmod($0, S_IRUSR | S_IWUSR) }) == 0,
                  let repaired = try itemStatusIfPresent(at: url) else {
                throw GameArtworkStoreError.unsafeStorage
            }
            status = repaired
        }
        guard Self.permissions(status.st_mode) == 0o600 else {
            throw GameArtworkStoreError.unsafeStorage
        }
        return true
    }

    private static func permissions(_ mode: mode_t) -> mode_t {
        mode & mode_t(0o777)
    }

    private static func fileType(_ mode: mode_t) -> mode_t {
        mode & mode_t(S_IFMT)
    }

    private static func validatePNG(_ data: Data) throws -> (width: Int, height: Int) {
        guard data.count >= 45 else { throw GameArtworkStoreError.invalidPNG }
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.prefix(signature.count).elementsEqual(signature) else {
            throw GameArtworkStoreError.invalidPNG
        }

        var offset = 8
        var isFirstChunk = true
        var dimensions: (width: Int, height: Int)?
        var sawImageData = false
        while offset <= data.count - 12 {
            let length = Int(readBigEndianUInt32(data, at: offset))
            guard length <= data.count - offset - 12 else {
                throw GameArtworkStoreError.invalidPNG
            }
            let typeStart = offset + 4
            let type = data[typeStart..<(typeStart + 4)]
            let chunkEnd = offset + 12 + length
            let expectedCRC = readBigEndianUInt32(data, at: offset + 8 + length)
            guard pngCRC(data, range: typeStart..<(typeStart + 4 + length))
                    == expectedCRC else {
                throw GameArtworkStoreError.invalidPNG
            }

            if isFirstChunk {
                guard length == 13, type.elementsEqual([73, 72, 68, 82]) else {
                    throw GameArtworkStoreError.invalidPNG
                }
                let width = Int(readBigEndianUInt32(data, at: offset + 8))
                let height = Int(readBigEndianUInt32(data, at: offset + 12))
                guard
                    width > 0,
                    height > 0,
                    width <= maximumRasterDimension,
                    height <= maximumRasterDimension
                else {
                    throw GameArtworkStoreError.invalidPNG
                }
                dimensions = (width, height)
                isFirstChunk = false
            } else if type.elementsEqual([73, 72, 68, 82]) {
                throw GameArtworkStoreError.invalidPNG
            } else if type.elementsEqual([73, 68, 65, 84]) {
                sawImageData = true
            } else if type.elementsEqual([73, 69, 78, 68]) {
                guard length == 0, chunkEnd == data.count,
                      let dimensions, sawImageData else {
                    throw GameArtworkStoreError.invalidPNG
                }
                return dimensions
            }
            offset = chunkEnd
        }
        throw GameArtworkStoreError.invalidPNG
    }

    private static func readBigEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    private static func pngCRC(_ data: Data, range: Range<Int>) -> UInt32 {
        var crc = UInt32.max
        for index in range {
            crc ^= UInt32(data[index])
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -Int32(crc & 1))
                crc = (crc >> 1) ^ (0xedb8_8320 & mask)
            }
        }
        return crc ^ UInt32.max
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func atomicRename(from source: URL, to destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
