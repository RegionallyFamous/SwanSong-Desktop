import CryptoKit
import Darwin
import Foundation

public enum ManagedGameStoreError: LocalizedError, Equatable, Sendable {
    case unsafeStorage
    case invalidReference
    case invalidROM
    case changedManagedCopy
    case wrongRepairImage

    public var errorDescription: String? {
        switch self {
        case .unsafeStorage:
            "The managed-game location is not a private, regular folder."
        case .invalidReference:
            "The library contains an invalid managed-game reference."
        case .invalidROM:
            "The managed game is not a valid WonderSwan ROM."
        case .changedManagedCopy:
            "The private managed copy has changed. Choose Repair and select the exact original game file."
        case .wrongRepairImage:
            "That file is a different game or revision. Choose the exact ROM originally added to this library entry."
        }
    }
}

public enum ManagedGameHealth: String, Equatable, Sendable {
    case healthy
    case missing
    case changed
    case invalidReference
}

public struct ManagedGameReference: Codable, Hashable, Sendable {
    public let sha256: String
    public let byteCount: Int
    public let fileExtension: String

    public init(sha256: String, byteCount: Int, fileExtension: String) {
        self.sha256 = sha256
        self.byteCount = byteCount
        self.fileExtension = fileExtension.lowercased()
    }

    public var fileName: String { "\(sha256).\(fileExtension)" }

    public var isValid: Bool {
        sha256.count == 64
            && sha256.allSatisfy {
                ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0))
            }
            && byteCount >= GameROMValidationPolicy.minimumByteCount
            && byteCount <= GameROMValidationPolicy.maximumByteCount
            && ["ws", "wsc", "pcv2"].contains(fileExtension)
    }
}

public struct ManagedGameInstallResult: Sendable {
    public let reference: ManagedGameReference
    public let fileURL: URL
    public let created: Bool

    public init(reference: ManagedGameReference, fileURL: URL, created: Bool) {
        self.reference = reference
        self.fileURL = fileURL
        self.created = created
    }
}

public struct ManagedGameStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let root = SwanSongDataRootPolicy.defaultResolution(fileManager: fileManager).rootURL
        return Self(
            rootURL: root
                .appendingPathComponent("Games", isDirectory: true)
        )
    }

    public func install(_ image: LibraryGameImportImage) throws -> ManagedGameInstallResult {
        let metadata = try GameROMValidationPolicy.validateLibraryImage(image.data)
        guard metadata == image.metadata,
              Self.sha256(image.data) == image.sha256,
              Self.hardwareModelIsCompatible(image.hardwareModel, metadata: metadata) else {
            throw ManagedGameStoreError.invalidROM
        }
        try prepareStorage()
        let reference = ManagedGameReference(
            sha256: image.sha256,
            byteCount: image.data.count,
            fileExtension: image.hardwareModel == .pocketChallengeV2
                ? "pcv2"
                : metadata.isColor ? "wsc" : "ws"
        )
        guard reference.isValid else { throw ManagedGameStoreError.invalidReference }
        let destination = try url(for: reference)

        if fileExistsWithoutFollowingLinks(destination) {
            _ = try load(reference)
            return ManagedGameInstallResult(
                reference: reference,
                fileURL: destination,
                created: false
            )
        }

        let temporary = rootURL.appendingPathComponent(
            ".game-install-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let descriptor = temporary.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw ManagedGameStoreError.unsafeStorage }
        let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var committed = false
        defer {
            try? writer.close()
            if !committed { try? FileManager.default.removeItem(at: temporary) }
        }
        do {
            try writer.write(contentsOf: image.data)
            try writer.synchronize()
            try writer.close()
        } catch {
            throw ManagedGameStoreError.unsafeStorage
        }
        try validateRegularFile(at: temporary, reference: nil, requiredPermissions: 0o600)
        try validateExistingStorage()

        let linkResult = temporary.path.withCString { source in
            destination.path.withCString { target in Darwin.link(source, target) }
        }
        if linkResult == 0 {
            try FileManager.default.removeItem(at: temporary)
            committed = true
            try validateRegularFile(at: destination, reference: reference, requiredPermissions: 0o600)
            _ = try load(reference)
            return ManagedGameInstallResult(
                reference: reference,
                fileURL: destination,
                created: true
            )
        }
        if errno == EEXIST {
            try FileManager.default.removeItem(at: temporary)
            committed = true
            _ = try load(reference)
            return ManagedGameInstallResult(
                reference: reference,
                fileURL: destination,
                created: false
            )
        }
        throw ManagedGameStoreError.unsafeStorage
    }

    public func load(_ reference: ManagedGameReference) throws -> Data {
        guard reference.isValid else { throw ManagedGameStoreError.invalidReference }
        try validateExistingStorage()
        let location = try url(for: reference)
        let descriptor = location.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else {
            if errno == ENOENT { throw CocoaError(.fileReadNoSuchFile) }
            throw ManagedGameStoreError.changedManagedCopy
        }
        let reader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? reader.close() }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == getuid(),
              status.st_nlink == 1,
              Int(status.st_size) == reference.byteCount,
              Int(status.st_mode & 0o777) == 0o600 else {
            throw ManagedGameStoreError.changedManagedCopy
        }
        let data = try reader.readToEnd() ?? Data()
        guard data.count == reference.byteCount,
              Self.sha256(data) == reference.sha256 else {
            throw ManagedGameStoreError.changedManagedCopy
        }
        let metadata = try GameROMValidationPolicy.validateLibraryImage(data)
        guard Self.extensionIsCompatible(reference.fileExtension, metadata: metadata) else {
            throw ManagedGameStoreError.changedManagedCopy
        }
        return data
    }

    public func health(of reference: ManagedGameReference) -> ManagedGameHealth {
        guard reference.isValid else { return .invalidReference }

        // Health checks are deliberately read-only. In particular, do not call
        // `load` here: storage validation may harden directory permissions, and
        // a background library scan should never mutate the user's filesystem.
        var rootStatus = stat()
        let rootResult = rootURL.path.withCString { Darwin.lstat($0, &rootStatus) }
        guard rootResult == 0 else {
            return errno == ENOENT ? .missing : .changed
        }
        guard (rootStatus.st_mode & S_IFMT) == S_IFDIR,
              rootStatus.st_uid == getuid(),
              Int(rootStatus.st_mode & 0o777) == 0o700 else {
            return .changed
        }
        let parent = rootURL.deletingLastPathComponent()
        var parentStatus = stat()
        guard parent.path.withCString({ Darwin.lstat($0, &parentStatus) }) == 0,
              (parentStatus.st_mode & S_IFMT) == S_IFDIR,
              parentStatus.st_uid == getuid() else {
            return .changed
        }

        let location: URL
        do {
            location = try url(for: reference)
        } catch {
            return .changed
        }
        let descriptor = location.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            return errno == ENOENT ? .missing : .changed
        }
        let reader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? reader.close() }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == getuid(),
              status.st_nlink == 1,
              Int(status.st_size) == reference.byteCount,
              Int(status.st_mode & 0o777) == 0o600,
              let data = try? reader.readToEnd(),
              data.count == reference.byteCount,
              Self.sha256(data) == reference.sha256,
              let metadata = try? GameROMValidationPolicy.validateLibraryImage(data),
              Self.extensionIsCompatible(reference.fileExtension, metadata: metadata) else {
            return .changed
        }
        return .healthy
    }

    /// Replaces a missing or damaged managed copy only when the user-selected
    /// source proves it is the exact same ROM bytes. The content reference and
    /// library identity therefore remain stable, preserving saves and artwork.
    @discardableResult
    public func repair(
        _ image: LibraryGameImportImage,
        matching reference: ManagedGameReference
    ) throws -> URL {
        guard reference.isValid else { throw ManagedGameStoreError.invalidReference }
        let metadata = try GameROMValidationPolicy.validateLibraryImage(image.data)
        guard metadata == image.metadata,
              image.sha256 == reference.sha256,
              image.data.count == reference.byteCount,
              Self.sha256(image.data) == reference.sha256,
              Self.extensionIsCompatible(reference.fileExtension, metadata: metadata),
              image.hardwareModel == Self.hardwareModel(
                for: reference.fileExtension,
                metadata: metadata
              ) else {
            throw ManagedGameStoreError.wrongRepairImage
        }
        try prepareStorage()
        let destination = try url(for: reference)
        try validateReplaceableDestinationIfPresent(at: destination)

        let temporary = rootURL.appendingPathComponent(
            ".game-repair-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let descriptor = temporary.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw ManagedGameStoreError.unsafeStorage }
        let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var committed = false
        defer {
            try? writer.close()
            if !committed { try? FileManager.default.removeItem(at: temporary) }
        }
        do {
            try writer.write(contentsOf: image.data)
            try writer.synchronize()
            try writer.close()
        } catch {
            throw ManagedGameStoreError.unsafeStorage
        }
        try validateRegularFile(at: temporary, reference: nil, requiredPermissions: 0o600)
        try validateExistingStorage()
        try validateReplaceableDestinationIfPresent(at: destination)
        try Self.atomicRename(from: temporary, to: destination)
        committed = true
        try synchronizeDirectory()
        _ = try load(reference)
        return destination
    }

    public func url(for reference: ManagedGameReference) throws -> URL {
        guard reference.isValid else { throw ManagedGameStoreError.invalidReference }
        return rootURL.appendingPathComponent(reference.fileName, isDirectory: false)
    }

    public func isManaged(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        guard normalized.deletingLastPathComponent() == rootURL else { return false }
        return Self.canonicalNameParts(normalized.lastPathComponent) != nil
    }

    public func remove(_ reference: ManagedGameReference) throws {
        guard reference.isValid else { throw ManagedGameStoreError.invalidReference }
        guard try storageExists() else { return }
        let location = try url(for: reference)
        guard fileExistsWithoutFollowingLinks(location) else { return }
        _ = try load(reference)
        try FileManager.default.removeItem(at: location)
    }

    public func prune(retaining references: [ManagedGameReference]) throws {
        guard try storageExists() else { return }
        // A malformed library reference is an integrity problem, not proof
        // that its canonical bytes are unowned. Fail closed so startup cleanup
        // can never delete the only copy before the UI reports the bad record.
        guard references.allSatisfy(\.isValid) else { return }
        let retained = Set(references.map(\.fileName))
        for candidate in try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            guard !retained.contains(candidate.lastPathComponent),
                  let parts = Self.canonicalNameParts(candidate.lastPathComponent) else { continue }
            var status = stat()
            guard candidate.path.withCString({ Darwin.lstat($0, &status) }) == 0,
                  (status.st_mode & S_IFMT) == S_IFREG,
                  status.st_uid == getuid(),
                  status.st_nlink == 1,
                  status.st_size >= off_t(GameROMValidationPolicy.minimumByteCount),
                  status.st_size <= off_t(GameROMValidationPolicy.maximumByteCount) else {
                continue
            }
            let reference = ManagedGameReference(
                sha256: parts.sha256,
                byteCount: Int(status.st_size),
                fileExtension: parts.fileExtension
            )
            // Only delete a canonical content-addressed file whose bytes prove
            // that SwanSong created it. Unknown and tampered files are left alone.
            guard (try? load(reference)) != nil else { continue }
            try FileManager.default.removeItem(at: candidate)
        }
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    public func prepareStorage() throws -> URL {
        let fileManager = FileManager.default
        let parent = rootURL.deletingLastPathComponent()
        if !fileExistsWithoutFollowingLinks(parent) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try validateDirectory(at: parent, requiredPermissions: nil)
        if !fileExistsWithoutFollowingLinks(rootURL) {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try validateDirectory(at: rootURL, requiredPermissions: 0o700)
        return rootURL
    }

    private func storageExists() throws -> Bool {
        guard fileExistsWithoutFollowingLinks(rootURL) else { return false }
        try validateExistingStorage()
        return true
    }

    private func validateExistingStorage() throws {
        try validateDirectory(at: rootURL.deletingLastPathComponent(), requiredPermissions: nil)
        try validateDirectory(at: rootURL, requiredPermissions: 0o700)
    }

    private func validateDirectory(at url: URL, requiredPermissions: Int?) throws {
        var status = stat()
        guard url.path.withCString({ Darwin.lstat($0, &status) }) == 0,
              (status.st_mode & S_IFMT) == S_IFDIR,
              status.st_uid == getuid() else {
            throw ManagedGameStoreError.unsafeStorage
        }
        if let requiredPermissions,
           Int(status.st_mode & 0o777) != requiredPermissions {
            guard url.path.withCString({ Darwin.chmod($0, mode_t(requiredPermissions)) }) == 0 else {
                throw ManagedGameStoreError.unsafeStorage
            }
            guard url.path.withCString({ Darwin.lstat($0, &status) }) == 0,
                  Int(status.st_mode & 0o777) == requiredPermissions else {
                throw ManagedGameStoreError.unsafeStorage
            }
        }
    }

    private func validateRegularFile(
        at url: URL,
        reference: ManagedGameReference?,
        requiredPermissions: Int
    ) throws {
        var status = stat()
        guard url.path.withCString({ Darwin.lstat($0, &status) }) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == getuid(),
              status.st_nlink == 1,
              Int(status.st_mode & 0o777) == requiredPermissions else {
            throw ManagedGameStoreError.unsafeStorage
        }
        if let reference, Int(status.st_size) != reference.byteCount {
            throw ManagedGameStoreError.changedManagedCopy
        }
    }

    private func validateReplaceableDestinationIfPresent(at url: URL) throws {
        var status = stat()
        let result = url.path.withCString { Darwin.lstat($0, &status) }
        if result != 0 {
            if errno == ENOENT { return }
            throw ManagedGameStoreError.unsafeStorage
        }
        guard (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == getuid(),
              status.st_nlink == 1 else {
            throw ManagedGameStoreError.unsafeStorage
        }
    }

    private func fileExistsWithoutFollowingLinks(_ url: URL) -> Bool {
        var status = stat()
        return url.path.withCString { Darwin.lstat($0, &status) } == 0
    }

    private func synchronizeDirectory() throws {
        let descriptor = rootURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw ManagedGameStoreError.unsafeStorage }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ManagedGameStoreError.unsafeStorage
        }
    }

    private static func canonicalNameParts(
        _ name: String
    ) -> (sha256: String, fileExtension: String)? {
        let url = URL(fileURLWithPath: name)
        let fileExtension = url.pathExtension.lowercased()
        let digest = url.deletingPathExtension().lastPathComponent
        guard ["ws", "wsc", "pcv2"].contains(fileExtension),
              digest.count == 64,
              digest.allSatisfy({
                  ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0))
              }) else {
            return nil
        }
        return (digest, fileExtension)
    }

    private static func extensionIsCompatible(
        _ fileExtension: String,
        metadata: ROMMetadata
    ) -> Bool {
        switch fileExtension {
        case "wsc": metadata.isColor
        case "ws", "pcv2": !metadata.isColor
        default: false
        }
    }

    private static func hardwareModel(
        for fileExtension: String,
        metadata: ROMMetadata
    ) -> EngineHardwareModel {
        fileExtension == "pcv2"
            ? .pocketChallengeV2
            : metadata.isColor ? .wonderSwanColor : .wonderSwan
    }

    private static func hardwareModelIsCompatible(
        _ hardwareModel: EngineHardwareModel,
        metadata: ROMMetadata
    ) -> Bool {
        switch hardwareModel {
        case .automatic:
            return false
        case .wonderSwan, .pocketChallengeV2:
            return !metadata.isColor
        case .wonderSwanColor, .swanCrystal:
            return metadata.isColor
        }
    }

    private static func atomicRename(from source: URL, to destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else { throw ManagedGameStoreError.unsafeStorage }
    }
}
