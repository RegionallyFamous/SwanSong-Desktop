import Darwin
import CryptoKit
import Foundation

public struct GameRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var fileURL: URL
    public var metadata: ROMMetadata
    public var lastPlayedAt: Date?
    public var isFavorite: Bool
    public var addedAt: Date?
    /// Present for library-managed imports. Legacy and Translation Lab records
    /// continue to use `fileURL` directly until explicitly migrated.
    public var managedROM: ManagedGameReference?
    public var sourceFileName: String?
    public var artworkPreference: GameArtworkPreference?
    public var compatibilityEvidence: GameCompatibilityEvidence?
    /// Present when a managed copy came from SwanSong's verified first-party
    /// homebrew catalog. The stable entry identity lets catalog updates keep the
    /// existing library UUID, saves, states, artwork, and user metadata.
    public var homebrewCatalogOrigin: HomebrewCatalogOrigin?
    /// Present when SwanSong built this managed copy from a source-free,
    /// release-certified translation patch and the exact required original.
    public var translationPatchOrigin: TranslationPatchOrigin?
    /// Stored only when the cartridge footer cannot identify the hardware.
    /// Pocket Challenge V2 software uses the monochrome WonderSwan footer
    /// shape but requires a distinct system, mapper, keypad, and flash path.
    public var preferredHardwareModel: EngineHardwareModel?

    public init(
        id: UUID = UUID(),
        title: String,
        fileURL: URL,
        metadata: ROMMetadata,
        lastPlayedAt: Date? = nil,
        isFavorite: Bool = false,
        addedAt: Date? = Date(),
        managedROM: ManagedGameReference? = nil,
        sourceFileName: String? = nil,
        artworkPreference: GameArtworkPreference? = nil,
        compatibilityEvidence: GameCompatibilityEvidence? = nil,
        homebrewCatalogOrigin: HomebrewCatalogOrigin? = nil,
        translationPatchOrigin: TranslationPatchOrigin? = nil,
        preferredHardwareModel: EngineHardwareModel? = nil
    ) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.metadata = metadata
        self.lastPlayedAt = lastPlayedAt
        self.isFavorite = isFavorite
        self.addedAt = addedAt
        self.managedROM = managedROM
        self.sourceFileName = sourceFileName
        self.artworkPreference = artworkPreference
        self.compatibilityEvidence = compatibilityEvidence
        self.homebrewCatalogOrigin = homebrewCatalogOrigin
        self.translationPatchOrigin = translationPatchOrigin
        self.preferredHardwareModel = preferredHardwareModel
    }

    public var resolvedHardwareModel: EngineHardwareModel {
        if let preferredHardwareModel, preferredHardwareModel != .automatic {
            return preferredHardwareModel
        }
        return metadata.isColor ? .wonderSwanColor : .wonderSwan
    }

    public var systemTitle: String {
        switch resolvedHardwareModel {
        case .pocketChallengeV2: "Pocket Challenge V2"
        case .wonderSwanColor: "WonderSwan Color"
        case .swanCrystal: "SwanCrystal"
        case .automatic, .wonderSwan: "WonderSwan"
        }
    }
}

public enum GameArtworkPreference: String, Codable, Hashable, Sendable {
    case automatic
    case procedural
}

public struct GameLibraryDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var games: [GameRecord]

    public init(schemaVersion: Int = 1, games: [GameRecord] = []) {
        self.schemaVersion = schemaVersion
        self.games = games
    }
}

public struct GameImporter: Sendable {
    public init() {}

    public func inspect(url: URL) throws -> GameRecord {
        let extensionName = url.pathExtension.lowercased()
        guard extensionName == "ws" || extensionName == "wsc" else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let metadata = try EngineSession.inspect(rom: data)
        return GameRecord(
            title: url.deletingPathExtension().lastPathComponent,
            fileURL: GameImportPlanner.normalizedURL(url),
            metadata: metadata
        )
    }
}

public struct GameLibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let root = SwanSongDataRootPolicy.defaultResolution(fileManager: fileManager).rootURL
        return Self(
            fileURL: root
                .appendingPathComponent("Library.json", isDirectory: false)
        )
    }

    public func load() throws -> GameLibraryDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return GameLibraryDocument()
        }
        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(GameLibraryDocument.self, from: data)
        guard document.schemaVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }

    public func save(_ document: GameLibraryDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public enum GameSaveStoreError: LocalizedError, Equatable, Sendable {
    case invalidSnapshotManifest
    case missingSnapshot(UUID)
    case unreadableLegacySave
    case unreadableSnapshot(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshotManifest:
            "The cartridge-save index is damaged. SwanSong left the save files unchanged."
        case let .missingSnapshot(generation):
            "Cartridge-save generation \(generation.uuidString) is missing. SwanSong left the remaining save files unchanged."
        case .unreadableLegacySave:
            "The legacy cartridge save could not be read. SwanSong left it unchanged."
        case let .unreadableSnapshot(generation):
            "Cartridge-save generation \(generation.uuidString) could not be read. SwanSong left the remaining save files unchanged."
        }
    }
}

public struct GameSaveLoadResult: Sendable {
    public let persistence: EnginePersistence
    public let recoveredPreviousGeneration: Bool

    public init(
        persistence: EnginePersistence,
        recoveredPreviousGeneration: Bool
    ) {
        self.persistence = persistence
        self.recoveredPreviousGeneration = recoveredPreviousGeneration
    }
}

public struct GameSaveStore: Sendable {
    private final class AccessCoordinator: @unchecked Sendable {
        private let lock = NSLock()

        func withLock<T>(_ operation: () throws -> T) rethrows -> T {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }
    }

    private struct SnapshotPointer: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let generation: UUID
        let previousGeneration: UUID?
    }

    private struct SnapshotRegionManifest: Codable {
        let kind: EnginePersistenceKind
        let byteCount: Int
        let sha256: String
    }

    private struct SnapshotManifest: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let generation: UUID
        let regions: [SnapshotRegionManifest]
    }

    private static let accessCoordinator = AccessCoordinator()

    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let root = SwanSongDataRootPolicy.defaultResolution(fileManager: fileManager).rootURL
        return Self(
            rootURL: root
                .appendingPathComponent("Saves", isDirectory: true)
        )
    }

    public func load(gameID: UUID) throws -> EnginePersistence {
        try loadWithStatus(gameID: gameID).persistence
    }

    public func loadWithStatus(gameID: UUID) throws -> GameSaveLoadResult {
        try Self.accessCoordinator.withLock {
            try loadUnlocked(gameID: gameID)
        }
    }

    private func loadUnlocked(gameID: UUID) throws -> GameSaveLoadResult {
        let directory = gameDirectory(for: gameID)
        guard let pointer = try readPointerIfPresent(in: directory) else {
            let legacy = try loadLegacyRegions(from: directory)
            if legacy.regions.isEmpty {
                let snapshots = directory.appendingPathComponent(".snapshots", isDirectory: true)
                if let children = try? FileManager.default.contentsOfDirectory(
                    at: snapshots,
                    includingPropertiesForKeys: nil
                ), !children.isEmpty {
                    throw GameSaveStoreError.invalidSnapshotManifest
                }
            }
            return GameSaveLoadResult(
                persistence: legacy,
                recoveredPreviousGeneration: false
            )
        }
        do {
            return GameSaveLoadResult(
                persistence: try loadSnapshot(pointer.generation, in: directory),
                recoveredPreviousGeneration: false
            )
        } catch let currentError as GameSaveStoreError {
            guard let previous = pointer.previousGeneration,
                  let recovered = try? loadSnapshot(previous, in: directory) else {
                throw currentError
            }
            // A complete previous generation is preferable to presenting a
            // partial save. Repairing the pointer is best-effort: even if the
            // index cannot be rewritten, this load remains safe and future
            // loads can attempt the same recovery again.
            try? publishPointer(
                SnapshotPointer(
                    schemaVersion: SnapshotPointer.currentSchemaVersion,
                    generation: previous,
                    previousGeneration: nil
                ),
                in: directory
            )
            return GameSaveLoadResult(
                persistence: recovered,
                recoveredPreviousGeneration: true
            )
        }
    }

    private func loadLegacyRegions(from directory: URL) throws -> EnginePersistence {
        var regions: [EnginePersistenceKind: Data] = [:]
        for kind in EnginePersistenceKind.allCases {
            let file = directory.appendingPathComponent(filename(for: kind))
            if FileManager.default.fileExists(atPath: file.path) {
                do {
                    regions[kind] = try Data(contentsOf: file)
                } catch {
                    throw GameSaveStoreError.unreadableLegacySave
                }
            }
        }
        return EnginePersistence(regions: regions)
    }

    public func save(_ persistence: EnginePersistence, gameID: UUID) throws {
        guard !persistence.regions.isEmpty else { return }
        try Self.accessCoordinator.withLock {
            var regions = try loadUnlocked(gameID: gameID).persistence.regions
            for (kind, data) in persistence.regions {
                regions[kind] = data
            }
            try commitUnlocked(regions, gameID: gameID)
        }
    }

    public func replaceCartridgeSave(
        _ persistence: EnginePersistence,
        gameID: UUID
    ) throws {
        let replaceable: [EnginePersistenceKind] = [
            .cartridgeRAM,
            .cartridgeEEPROM,
            .rtc,
        ]
        let unexpected = persistence.regions.keys.first { !replaceable.contains($0) }
        guard unexpected == nil else { throw CocoaError(.fileWriteInvalidFileName) }

        try Self.accessCoordinator.withLock {
            var regions = try loadUnlocked(gameID: gameID).persistence.regions
            for kind in replaceable {
                regions.removeValue(forKey: kind)
            }
            for (kind, data) in persistence.regions {
                regions[kind] = data
            }
            try commitUnlocked(regions, gameID: gameID)
        }
    }

    private func commitUnlocked(
        _ regions: [EnginePersistenceKind: Data],
        gameID: UUID
    ) throws {
        let fileManager = FileManager.default
        let directory = gameDirectory(for: gameID)
        let directoryExisted = fileManager.fileExists(atPath: directory.path)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshots = directory.appendingPathComponent(".snapshots", isDirectory: true)
        try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let previousPointer = try readPointerIfPresent(in: directory)

        let generation = UUID()
        let staging = snapshots.appendingPathComponent(
            ".staging-\(generation.uuidString)",
            isDirectory: true
        )
        let committed = snapshots.appendingPathComponent(
            generation.uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var snapshotWasMoved = false
        var pointerWasCommitted = false
        defer {
            if !snapshotWasMoved {
                try? fileManager.removeItem(at: staging)
            } else if !pointerWasCommitted {
                try? fileManager.removeItem(at: committed)
            }
            if !pointerWasCommitted, !directoryExisted {
                try? fileManager.removeItem(at: snapshots)
                try? fileManager.removeItem(at: directory)
            }
        }

        var completedWrites = 0
        var regionManifests: [SnapshotRegionManifest] = []
        for kind in EnginePersistenceKind.allCases {
            guard let data = regions[kind] else { continue }
            let file = staging.appendingPathComponent(filename(for: kind))
            try data.write(to: file, options: [.atomic])
            try synchronizeFile(file)
            regionManifests.append(
                SnapshotRegionManifest(
                    kind: kind,
                    byteCount: data.count,
                    sha256: sha256(data)
                )
            )
            completedWrites += 1
            #if DEBUG
            if let rawLimit = ProcessInfo.processInfo.environment[
                "SWAN_SONG_TEST_SAVE_FAILURE_AFTER_WRITES"
            ], let limit = Int(rawLimit), completedWrites >= limit {
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
        }

        let manifest = SnapshotManifest(
            schemaVersion: SnapshotManifest.currentSchemaVersion,
            generation: generation,
            regions: regionManifests
        )
        let manifestURL = staging.appendingPathComponent(".manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: [.atomic])
        try synchronizeFile(manifestURL)
        try synchronizeDirectory(staging)

        try fileManager.moveItem(at: staging, to: committed)
        snapshotWasMoved = true
        try synchronizeDirectory(snapshots)
        try synchronizeDirectory(directory)
        try synchronizeDirectory(rootURL)
        try synchronizeDirectory(rootURL.deletingLastPathComponent())

        #if DEBUG
        if ProcessInfo.processInfo.environment[
            "SWAN_SONG_TEST_SAVE_FAILURE_POINT"
        ] == "before-publish" {
            throw CocoaError(.fileWriteUnknown)
        }
        #endif

        let pointer = SnapshotPointer(
            schemaVersion: SnapshotPointer.currentSchemaVersion,
            generation: generation,
            previousGeneration: previousPointer?.generation
        )
        try publishPointer(pointer, in: directory)
        pointerWasCommitted = true

        // Once the pointer is durable, cleanup is deliberately best-effort.
        // Reporting failure after the commit would incorrectly tell the
        // player that its newest save was lost.
        let skipsCleanup: Bool = {
            #if DEBUG
            ProcessInfo.processInfo.environment[
                "SWAN_SONG_TEST_SAVE_FAILURE_POINT"
            ] == "cleanup"
            #else
            false
            #endif
        }()
        let retainedGenerations = Set([
            generation.uuidString,
            previousPointer?.generation.uuidString,
        ].compactMap { $0 })
        if !skipsCleanup, let children = try? fileManager.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: nil
        ) {
            for child in children where !retainedGenerations.contains(child.lastPathComponent) {
                try? fileManager.removeItem(at: child)
            }
        }
        for kind in EnginePersistenceKind.allCases {
            try? fileManager.removeItem(
                at: directory.appendingPathComponent(filename(for: kind))
            )
        }
    }

    private func readPointerIfPresent(in directory: URL) throws -> SnapshotPointer? {
        let pointerURL = directory.appendingPathComponent(".current-save.json")
        guard FileManager.default.fileExists(atPath: pointerURL.path) else { return nil }
        do {
            let pointer = try JSONDecoder().decode(
                SnapshotPointer.self,
                from: Data(contentsOf: pointerURL)
            )
            guard pointer.schemaVersion == SnapshotPointer.currentSchemaVersion else {
                throw GameSaveStoreError.invalidSnapshotManifest
            }
            return pointer
        } catch is GameSaveStoreError {
            throw GameSaveStoreError.invalidSnapshotManifest
        } catch {
            throw GameSaveStoreError.invalidSnapshotManifest
        }
    }

    private func loadSnapshot(
        _ generation: UUID,
        in directory: URL
    ) throws -> EnginePersistence {
        let snapshot = directory
            .appendingPathComponent(".snapshots", isDirectory: true)
            .appendingPathComponent(generation.uuidString, isDirectory: true)
        do {
            let values = try snapshot.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw GameSaveStoreError.missingSnapshot(generation)
            }
        } catch is GameSaveStoreError {
            throw GameSaveStoreError.missingSnapshot(generation)
        } catch {
            throw GameSaveStoreError.missingSnapshot(generation)
        }

        let manifest: SnapshotManifest
        do {
            manifest = try JSONDecoder().decode(
                SnapshotManifest.self,
                from: Data(contentsOf: snapshot.appendingPathComponent(".manifest.json"))
            )
        } catch {
            throw GameSaveStoreError.unreadableSnapshot(generation)
        }
        let kinds = Set(manifest.regions.map(\.kind))
        guard manifest.schemaVersion == SnapshotManifest.currentSchemaVersion,
              manifest.generation == generation,
              kinds.count == manifest.regions.count,
              manifest.regions.allSatisfy({
                  $0.byteCount >= 0
                      && $0.sha256.count == 64
                      && $0.sha256.allSatisfy(\.isHexDigit)
              }) else {
            throw GameSaveStoreError.unreadableSnapshot(generation)
        }

        var regions: [EnginePersistenceKind: Data] = [:]
        for region in manifest.regions {
            let file = snapshot.appendingPathComponent(filename(for: region.kind))
            let data: Data
            do {
                data = try Data(contentsOf: file)
            } catch {
                throw GameSaveStoreError.unreadableSnapshot(generation)
            }
            guard data.count == region.byteCount,
                  sha256(data) == region.sha256 else {
                throw GameSaveStoreError.unreadableSnapshot(generation)
            }
            regions[region.kind] = data
        }
        for kind in EnginePersistenceKind.allCases where !kinds.contains(kind) {
            if FileManager.default.fileExists(
                atPath: snapshot.appendingPathComponent(filename(for: kind)).path
            ) {
                throw GameSaveStoreError.unreadableSnapshot(generation)
            }
        }
        return EnginePersistence(regions: regions)
    }

    private func publishPointer(
        _ pointer: SnapshotPointer,
        in directory: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pointer)
        let staging = directory.appendingPathComponent(
            ".save-index-\(UUID().uuidString).tmp"
        )
        let destination = directory.appendingPathComponent(".current-save.json")
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging, options: [.atomic])
        try synchronizeFile(staging)
        let result = staging.path.withCString { source in
            destination.path.withCString { target in
                Darwin.rename(source, target)
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // rename() is the publication point. Durability synchronization and
        // cleanup after this line are best-effort so callers never receive a
        // false save-failure report after the new generation became visible.
        try? synchronizeFile(destination)
        try? synchronizeDirectory(directory)
    }

    private func synchronizeFile(_ file: URL) throws {
        let descriptor = file.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func gameDirectory(for gameID: UUID) -> URL {
        rootURL.appendingPathComponent(gameID.uuidString, isDirectory: true)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func filename(for kind: EnginePersistenceKind) -> String {
        switch kind {
        case .consoleEEPROM: "console.eeprom"
        case .cartridgeRAM: "cartridge.ram"
        case .cartridgeEEPROM: "cartridge.eeprom"
        case .cartridgeFlash: "cartridge.flash"
        case .rtc: "clock.rtc"
        }
    }
}

public enum GameStateHardwareModel: String, Codable, Equatable, Sendable {
    case wonderSwan
    case wonderSwanColor
    case pocketChallengeV2

    public init(isColor: Bool) {
        self = isColor ? .wonderSwanColor : .wonderSwan
    }

    public var isColor: Bool {
        self == .wonderSwanColor
    }

    public init(engineModel: EngineHardwareModel, isColor: Bool) {
        switch engineModel {
        case .pocketChallengeV2:
            self = .pocketChallengeV2
        case .wonderSwanColor, .swanCrystal:
            self = .wonderSwanColor
        case .automatic, .wonderSwan:
            self = isColor ? .wonderSwanColor : .wonderSwan
        }
    }
}

/// Exact identity of the emulated system that owns a save state. The footer
/// checksum remains for schema-1 discovery, but never substitutes for the ROM
/// digest when classifying a schema-2 state.
public struct GameStateSessionIdentity: Codable, Equatable, Sendable {
    public let romChecksum: UInt16
    public let romSHA256: String
    public let romByteCount: Int
    public let firmwareSHA256: String
    public let firmwareByteCount: Int
    public let hardwareModel: GameStateHardwareModel
    public let isColor: Bool
    public let backend: String
    public let engineBuildID: String?

    public init(
        romChecksum: UInt16,
        romSHA256: String,
        romByteCount: Int,
        firmwareSHA256: String,
        firmwareByteCount: Int,
        hardwareModel: GameStateHardwareModel,
        isColor: Bool,
        backend: String,
        engineBuildID: String?
    ) {
        self.romChecksum = romChecksum
        self.romSHA256 = romSHA256.lowercased()
        self.romByteCount = romByteCount
        self.firmwareSHA256 = firmwareSHA256.lowercased()
        self.firmwareByteCount = firmwareByteCount
        self.hardwareModel = hardwareModel
        self.isColor = isColor
        self.backend = backend
        self.engineBuildID = engineBuildID
    }

    public init(
        rom: Data,
        romChecksum: UInt16,
        firmware: Data,
        isColor: Bool,
        hardwareModel: EngineHardwareModel = .automatic,
        backend: String,
        engineBuildID: String?
    ) {
        self.init(
            romChecksum: romChecksum,
            romSHA256: Self.sha256(rom),
            romByteCount: rom.count,
            firmwareSHA256: Self.sha256(firmware),
            firmwareByteCount: firmware.count,
            hardwareModel: GameStateHardwareModel(
                engineModel: hardwareModel,
                isColor: isColor
            ),
            isColor: isColor,
            backend: backend,
            engineBuildID: engineBuildID
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum GameStateCompatibility: LocalizedError, Equatable, Sendable {
    case ready
    case legacyNeedsConfirmation(String)
    case wrongROM(String)
    case wrongFirmware(String)
    case wrongEngineBuild(String)
    case damaged(String)

    public var reason: String {
        switch self {
        case .ready:
            "This saved moment exactly matches the current game, startup implementation, hardware, and engine build."
        case let .legacyNeedsConfirmation(reason),
             let .wrongROM(reason),
             let .wrongFirmware(reason),
             let .wrongEngineBuild(reason),
             let .damaged(reason):
            reason
        }
    }

    public var isReady: Bool {
        self == .ready
    }

    public var errorDescription: String? {
        reason
    }
}

public struct GameStateManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generation: UUID
    public let createdAt: Date
    public let romChecksum: UInt16
    public let romSHA256: String?
    public let romByteCount: Int?
    public let firmwareSHA256: String?
    public let firmwareByteCount: Int?
    public let hardwareModel: GameStateHardwareModel?
    public let isColor: Bool?
    public let frameNumber: UInt64
    public let backend: String
    public let engineBuildID: String?
    public let stateByteCount: Int
    public let stateSHA256: String?
    public let previewByteCount: Int?
    public let previewSHA256: String?

    /// Creates a schema-1 manifest for compatibility tests and migration tools.
    /// New player saves must use the session-identity initializer below.
    public init(
        generation: UUID = UUID(),
        createdAt: Date = Date(),
        romChecksum: UInt16,
        frameNumber: UInt64,
        backend: String,
        stateByteCount: Int
    ) {
        schemaVersion = 1
        self.generation = generation
        self.createdAt = createdAt
        self.romChecksum = romChecksum
        romSHA256 = nil
        romByteCount = nil
        firmwareSHA256 = nil
        firmwareByteCount = nil
        hardwareModel = nil
        isColor = nil
        self.frameNumber = frameNumber
        self.backend = backend
        engineBuildID = nil
        self.stateByteCount = stateByteCount
        stateSHA256 = nil
        previewByteCount = nil
        previewSHA256 = nil
    }

    public init(
        generation: UUID = UUID(),
        createdAt: Date = Date(),
        sessionIdentity: GameStateSessionIdentity,
        frameNumber: UInt64,
        state: Data,
        previewPNG: Data?
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.generation = generation
        self.createdAt = createdAt
        romChecksum = sessionIdentity.romChecksum
        romSHA256 = sessionIdentity.romSHA256
        romByteCount = sessionIdentity.romByteCount
        firmwareSHA256 = sessionIdentity.firmwareSHA256
        firmwareByteCount = sessionIdentity.firmwareByteCount
        hardwareModel = sessionIdentity.hardwareModel
        isColor = sessionIdentity.isColor
        self.frameNumber = frameNumber
        backend = sessionIdentity.backend
        engineBuildID = sessionIdentity.engineBuildID
        stateByteCount = state.count
        stateSHA256 = Self.sha256(state)
        previewByteCount = previewPNG?.count
        previewSHA256 = previewPNG.map(Self.sha256)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct GameStateRecord: Sendable {
    public let manifest: GameStateManifest
    public let state: Data
    public let previewPNG: Data
    public let previewIssue: String?
    public let compatibility: GameStateCompatibility
}

public struct GameStateSummary: Identifiable, Sendable {
    public var id: UUID { manifest.generation }
    public let manifest: GameStateManifest
    public let isQuickState: Bool
    /// Empty when this card's preview is missing or damaged. Keeping the card
    /// preserves the rest of the timeline and lets existing UI show a fallback.
    public let previewPNG: Data
    public let previewIssue: String?
    public let compatibility: GameStateCompatibility
}

private struct GameStateTimelineDocument: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var entries: [GameStateManifest]
    var quickGeneration: UUID?

    init(entries: [GameStateManifest], quickGeneration: UUID?) {
        schemaVersion = Self.currentSchemaVersion
        self.entries = entries
        self.quickGeneration = quickGeneration
    }
}

public struct GameStateStore: Sendable {
    public let rootURL: URL
    public let maximumTimelineEntries: Int

    public init(rootURL: URL, maximumTimelineEntries: Int = 12) {
        self.rootURL = rootURL
        self.maximumTimelineEntries = max(1, maximumTimelineEntries)
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let root = SwanSongDataRootPolicy.defaultResolution(fileManager: fileManager).rootURL
        return Self(
            rootURL: root
                .appendingPathComponent("States", isDirectory: true)
        )
    }

    public func saveQuickState(
        gameID: UUID,
        romChecksum: UInt16,
        frameNumber: UInt64,
        backend: String,
        state: Data,
        previewPNG: Data
    ) throws -> GameStateManifest {
        try saveQuickState(
            gameID: gameID,
            manifest: GameStateManifest(
                romChecksum: romChecksum,
                frameNumber: frameNumber,
                backend: backend,
                stateByteCount: state.count
            ),
            state: state,
            previewPNG: previewPNG,
            writesLegacyQuickPointer: true
        )
    }

    public func saveQuickState(
        gameID: UUID,
        sessionIdentity: GameStateSessionIdentity,
        frameNumber: UInt64,
        state: Data,
        previewPNG: Data?
    ) throws -> GameStateManifest {
        try saveQuickState(
            gameID: gameID,
            manifest: GameStateManifest(
                sessionIdentity: sessionIdentity,
                frameNumber: frameNumber,
                state: state,
                previewPNG: previewPNG
            ),
            state: state,
            previewPNG: previewPNG,
            writesLegacyQuickPointer: false
        )
    }

    private func saveQuickState(
        gameID: UUID,
        manifest: GameStateManifest,
        state: Data,
        previewPNG: Data?,
        writesLegacyQuickPointer: Bool
    ) throws -> GameStateManifest {
        let directory = rootURL.appendingPathComponent(gameID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = manifest.generation.uuidString
        try state.write(to: directory.appendingPathComponent("\(base).state"), options: [.atomic])
        if let previewPNG {
            try previewPNG.write(
                to: directory.appendingPathComponent("\(base).png"),
                options: [.atomic]
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let timelineURL = directory.appendingPathComponent("Timeline.json")
        var entries: [GameStateManifest]
        if FileManager.default.fileExists(atPath: timelineURL.path) {
            let existingDocument = try loadTimelineDocument(in: directory)
            entries = existingDocument.entries
            if existingDocument.schemaVersion == 1,
               let legacyQuick = try loadLegacyQuickManifest(in: directory),
               !entries.contains(where: { $0.generation == legacyQuick.generation }) {
                // Recover the last fully written legacy quick state even when
                // an old multi-file publication stopped before its timeline.
                entries.insert(legacyQuick, at: 0)
            }
        } else if let legacyQuick = try loadLegacyQuickManifest(in: directory) {
            // A schema-1 install may have only QuickState.json. Preserve that
            // generation when the first schema-2 index is published.
            entries = [legacyQuick]
        } else {
            entries = []
        }
        entries.removeAll { $0.generation == manifest.generation }
        entries.insert(manifest, at: 0)
        if entries.count > maximumTimelineEntries {
            entries.removeLast(entries.count - maximumTimelineEntries)
        }
        if writesLegacyQuickPointer {
            try encoder.encode(manifest).write(
                to: directory.appendingPathComponent("QuickState.json"),
                options: [.atomic]
            )
        }
        // Timeline.json is the schema-2 publication point for both ordering
        // and the quick-state pointer. Any unindexed artifact is an orphan and
        // is never loadable; cleanup remains best-effort after publication.
        try encoder.encode(GameStateTimelineDocument(
            entries: entries,
            quickGeneration: manifest.generation
        )).write(
            to: timelineURL,
            options: [.atomic]
        )
        if let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            let retained = Set(entries.map { $0.generation.uuidString })
            for file in files where
                file.pathExtension == "state" || file.pathExtension == "png" {
                let generation = file.deletingPathExtension().lastPathComponent
                guard !retained.contains(generation) else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
        return manifest
    }

    public func loadQuickState(gameID: UUID, romChecksum: UInt16) throws -> GameStateRecord? {
        let record = try loadQuickState(
            gameID: gameID,
            expectedSessionIdentity: nil,
            legacyROMChecksum: romChecksum
        )
        if let record, case .wrongROM = record.compatibility {
            throw CocoaError(.fileReadCorruptFile)
        }
        return record
    }

    public func loadQuickState(
        gameID: UUID,
        sessionIdentity: GameStateSessionIdentity
    ) throws -> GameStateRecord? {
        try loadQuickState(
            gameID: gameID,
            expectedSessionIdentity: sessionIdentity,
            legacyROMChecksum: sessionIdentity.romChecksum
        )
    }

    private func loadQuickState(
        gameID: UUID,
        expectedSessionIdentity: GameStateSessionIdentity?,
        legacyROMChecksum: UInt16
    ) throws -> GameStateRecord? {
        let directory = rootURL.appendingPathComponent(gameID.uuidString, isDirectory: true)
        guard let manifest = try quickManifest(in: directory) else { return nil }
        return try loadRecord(
            manifest: manifest,
            in: directory,
            expectedSessionIdentity: expectedSessionIdentity,
            legacyROMChecksum: legacyROMChecksum
        )
    }

    public func listStates(gameID: UUID, romChecksum: UInt16) throws -> [GameStateSummary] {
        try listStates(
            gameID: gameID,
            expectedSessionIdentity: nil,
            legacyROMChecksum: romChecksum
        )
    }

    public func listStates(
        gameID: UUID,
        sessionIdentity: GameStateSessionIdentity
    ) throws -> [GameStateSummary] {
        try listStates(
            gameID: gameID,
            expectedSessionIdentity: sessionIdentity,
            legacyROMChecksum: sessionIdentity.romChecksum
        )
    }

    private func listStates(
        gameID: UUID,
        expectedSessionIdentity: GameStateSessionIdentity?,
        legacyROMChecksum: UInt16
    ) throws -> [GameStateSummary] {
        let directory = rootURL.appendingPathComponent(gameID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let entries: [GameStateManifest]
        let quickGeneration: UUID?
        let timelineURL = directory.appendingPathComponent("Timeline.json")
        if FileManager.default.fileExists(atPath: timelineURL.path) {
            let document = try loadTimelineDocument(in: directory)
            entries = document.entries
            if let indexedQuick = document.quickGeneration {
                quickGeneration = indexedQuick
            } else if document.schemaVersion == 1 {
                quickGeneration = try loadLegacyQuickManifest(in: directory)?.generation
            } else {
                quickGeneration = nil
            }
        } else if FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("QuickState.json").path
        ) {
            entries = [try JSONDecoder().decode(
                GameStateManifest.self,
                from: Data(contentsOf: directory.appendingPathComponent("QuickState.json"))
            )]
            quickGeneration = entries.first?.generation
        } else {
            entries = []
            quickGeneration = nil
        }
        return entries.map { manifest in
            let base = manifest.generation.uuidString
            let state: Data?
            var stateIssue: String?
            do {
                state = try Data(contentsOf: directory.appendingPathComponent("\(base).state"))
            } catch {
                state = nil
                stateIssue = "The saved-state data is missing or unreadable."
            }
            let compatibility = compatibility(
                of: manifest,
                expectedSessionIdentity: expectedSessionIdentity,
                legacyROMChecksum: legacyROMChecksum,
                state: state,
                stateIssue: stateIssue
            )
            let preview = validatedPreview(manifest: manifest, in: directory)
            return GameStateSummary(
                manifest: manifest,
                isQuickState: manifest.generation == quickGeneration,
                previewPNG: preview.data,
                previewIssue: preview.issue,
                compatibility: compatibility
            )
        }
    }

    public func loadState(
        gameID: UUID,
        generation: UUID,
        romChecksum: UInt16
    ) throws -> GameStateRecord {
        let record = try loadState(
            gameID: gameID,
            generation: generation,
            expectedSessionIdentity: nil,
            legacyROMChecksum: romChecksum
        )
        if case .wrongROM = record.compatibility {
            throw CocoaError(.fileReadCorruptFile)
        }
        return record
    }

    public func loadState(
        gameID: UUID,
        generation: UUID,
        sessionIdentity: GameStateSessionIdentity
    ) throws -> GameStateRecord {
        try loadState(
            gameID: gameID,
            generation: generation,
            expectedSessionIdentity: sessionIdentity,
            legacyROMChecksum: sessionIdentity.romChecksum
        )
    }

    private func loadState(
        gameID: UUID,
        generation: UUID,
        expectedSessionIdentity: GameStateSessionIdentity?,
        legacyROMChecksum: UInt16
    ) throws -> GameStateRecord {
        let directory = rootURL.appendingPathComponent(gameID.uuidString, isDirectory: true)
        let timelineURL = directory.appendingPathComponent("Timeline.json")
        let entries = FileManager.default.fileExists(atPath: timelineURL.path)
            ? try loadTimelineDocument(in: directory).entries
            : []
        var manifest = entries.first { $0.generation == generation }
        if manifest == nil {
            manifest = try loadLegacyQuickManifest(in: directory)
        }
        guard let manifest, manifest.generation == generation else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try loadRecord(
            manifest: manifest,
            in: directory,
            expectedSessionIdentity: expectedSessionIdentity,
            legacyROMChecksum: legacyROMChecksum
        )
    }

    public func deleteState(gameID: UUID, generation: UUID) throws {
        let directory = rootURL.appendingPathComponent(gameID.uuidString, isDirectory: true)
        let timelineURL = directory.appendingPathComponent("Timeline.json")
        var document: GameStateTimelineDocument
        if FileManager.default.fileExists(atPath: timelineURL.path) {
            document = try loadTimelineDocument(in: directory)
        } else if let quick = try loadLegacyQuickManifest(in: directory) {
            document = GameStateTimelineDocument(
                entries: [quick],
                quickGeneration: quick.generation
            )
        } else {
            document = GameStateTimelineDocument(entries: [], quickGeneration: nil)
        }
        document.entries.removeAll { $0.generation == generation }
        if document.quickGeneration == generation
            || !document.entries.contains(where: { $0.generation == document.quickGeneration }) {
            document.quickGeneration = document.entries.first?.generation
        }
        document.schemaVersion = GameStateTimelineDocument.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(
            to: directory.appendingPathComponent("Timeline.json"),
            options: [.atomic]
        )
        let quickURL = directory.appendingPathComponent("QuickState.json")
        if let quick = try? JSONDecoder().decode(
            GameStateManifest.self,
            from: Data(contentsOf: quickURL)
        ), quick.generation == generation {
            if let replacement = document.entries.first,
               replacement.schemaVersion == 1 {
                try encoder.encode(replacement).write(to: quickURL, options: [.atomic])
            } else {
                try? FileManager.default.removeItem(at: quickURL)
            }
        }
        let base = generation.uuidString
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(base).state"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(base).png"))
    }

    private func loadTimelineDocument(in directory: URL) throws -> GameStateTimelineDocument {
        let document = try JSONDecoder().decode(
            GameStateTimelineDocument.self,
            from: Data(contentsOf: directory.appendingPathComponent("Timeline.json"))
        )
        guard document.schemaVersion == 1
                || document.schemaVersion == GameStateTimelineDocument.currentSchemaVersion,
              Set(document.entries.map(\.generation)).count == document.entries.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if document.schemaVersion == GameStateTimelineDocument.currentSchemaVersion,
           let quickGeneration = document.quickGeneration,
           !document.entries.contains(where: { $0.generation == quickGeneration }) {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }

    private func quickManifest(in directory: URL) throws -> GameStateManifest? {
        let timelineURL = directory.appendingPathComponent("Timeline.json")
        if FileManager.default.fileExists(atPath: timelineURL.path) {
            let document = try loadTimelineDocument(in: directory)
            if document.schemaVersion == GameStateTimelineDocument.currentSchemaVersion {
                guard let quickGeneration = document.quickGeneration else { return nil }
                return document.entries.first { $0.generation == quickGeneration }
            }
        }
        return try loadLegacyQuickManifest(in: directory)
    }

    private func loadLegacyQuickManifest(
        in directory: URL
    ) throws -> GameStateManifest? {
        let manifestURL = directory.appendingPathComponent("QuickState.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        return try JSONDecoder().decode(
            GameStateManifest.self,
            from: Data(contentsOf: manifestURL)
        )
    }

    private func loadRecord(
        manifest: GameStateManifest,
        in directory: URL,
        expectedSessionIdentity: GameStateSessionIdentity?,
        legacyROMChecksum: UInt16
    ) throws -> GameStateRecord {
        let base = manifest.generation.uuidString
        let state = try Data(contentsOf: directory.appendingPathComponent("\(base).state"))
        let compatibility = compatibility(
            of: manifest,
            expectedSessionIdentity: expectedSessionIdentity,
            legacyROMChecksum: legacyROMChecksum,
            state: state,
            stateIssue: nil
        )
        let preview = validatedPreview(manifest: manifest, in: directory)
        return GameStateRecord(
            manifest: manifest,
            state: state,
            previewPNG: preview.data,
            previewIssue: preview.issue,
            compatibility: compatibility
        )
    }

    private func compatibility(
        of manifest: GameStateManifest,
        expectedSessionIdentity: GameStateSessionIdentity?,
        legacyROMChecksum: UInt16,
        state: Data?,
        stateIssue: String?
    ) -> GameStateCompatibility {
        if let stateIssue {
            return .damaged(stateIssue)
        }
        guard let state else {
            return .damaged("The saved-state data is missing or unreadable.")
        }
        guard manifest.stateByteCount >= 0, state.count == manifest.stateByteCount else {
            return .damaged("The saved-state size no longer matches its manifest.")
        }

        if manifest.schemaVersion == 1 {
            guard manifest.romChecksum == legacyROMChecksum else {
                return .wrongROM("This legacy state belongs to a different game checksum.")
            }
            return .legacyNeedsConfirmation(
                "This legacy state predates exact ROM, startup-implementation, and engine-build identity. Confirm compatibility before loading it."
            )
        }

        guard manifest.schemaVersion == GameStateManifest.currentSchemaVersion else {
            return .damaged("This saved moment uses an unsupported manifest version.")
        }
        guard
            let romSHA256 = validSHA256(manifest.romSHA256),
            let romByteCount = manifest.romByteCount,
            romByteCount > 0,
            let firmwareSHA256 = validSHA256(manifest.firmwareSHA256),
            let firmwareByteCount = manifest.firmwareByteCount,
            firmwareByteCount >= 0,
            let hardwareModel = manifest.hardwareModel,
            let isColor = manifest.isColor,
            hardwareModel.isColor == isColor,
            !manifest.backend.isEmpty,
            let stateSHA256 = validSHA256(manifest.stateSHA256)
        else {
            return .damaged("The schema-2 manifest is incomplete or internally inconsistent.")
        }
        guard state.count == manifest.stateByteCount,
              Self.sha256(state) == stateSHA256 else {
            return .damaged("The saved-state bytes no longer match their recorded digest.")
        }
        guard let expectedSessionIdentity else {
            return .legacyNeedsConfirmation(
                "The saved moment has exact identity data, but the current session does not. Restart the game before loading it."
            )
        }
        guard isValid(expectedSessionIdentity) else {
            return .damaged("The current player session does not have a valid exact identity.")
        }
        guard manifest.romChecksum == expectedSessionIdentity.romChecksum,
              romByteCount == expectedSessionIdentity.romByteCount,
              romSHA256 == expectedSessionIdentity.romSHA256,
              hardwareModel == expectedSessionIdentity.hardwareModel,
              isColor == expectedSessionIdentity.isColor else {
            return .wrongROM(
                "This saved moment was created from different game bytes or a different WonderSwan hardware model."
            )
        }
        guard firmwareByteCount == expectedSessionIdentity.firmwareByteCount,
              firmwareSHA256 == expectedSessionIdentity.firmwareSHA256 else {
            return .wrongFirmware(
                "This saved moment was created with a different version of SwanSong Open IPL."
            )
        }
        guard manifest.backend == expectedSessionIdentity.backend else {
            return .wrongEngineBuild(
                "This saved moment was created by a different emulator backend."
            )
        }
        guard let savedEngineBuildID = manifest.engineBuildID,
              !savedEngineBuildID.isEmpty else {
            return .wrongEngineBuild(
                "This saved moment does not record an exact emulator engine build."
            )
        }
        guard let currentEngineBuildID = expectedSessionIdentity.engineBuildID,
              !currentEngineBuildID.isEmpty else {
            return .wrongEngineBuild(
                "The current emulator engine build could not be identified exactly."
            )
        }
        guard savedEngineBuildID == currentEngineBuildID else {
            return .wrongEngineBuild(
                "This saved moment was created by a different emulator engine build."
            )
        }
        return .ready
    }

    private func validatedPreview(
        manifest: GameStateManifest,
        in directory: URL
    ) -> (data: Data, issue: String?) {
        let previewURL = directory.appendingPathComponent(
            "\(manifest.generation.uuidString).png"
        )
        let previewPNG: Data
        do {
            previewPNG = try Data(contentsOf: previewURL)
        } catch {
            if manifest.schemaVersion == GameStateManifest.currentSchemaVersion,
               manifest.previewByteCount == nil,
               manifest.previewSHA256 == nil {
                return (
                    Data(),
                    "This saved moment was created without a preview. SwanSong requires a verified preview to load it safely."
                )
            }
            return (Data(), "The saved-moment preview is missing or unreadable.")
        }
        if manifest.schemaVersion == 1 {
            return (previewPNG, nil)
        }
        guard let expectedCount = manifest.previewByteCount,
              expectedCount >= 0,
              let expectedSHA256 = validSHA256(manifest.previewSHA256) else {
            return (
                Data(),
                "The saved-moment preview identity is incomplete. The emulator state is still independent."
            )
        }
        guard previewPNG.count == expectedCount,
              Self.sha256(previewPNG) == expectedSHA256 else {
            return (
                Data(),
                "The saved-moment preview is damaged. The emulator state is still independent."
            )
        }
        do {
            _ = try EngineFramePNGCodec.decode(
                previewPNG,
                frameNumber: manifest.frameNumber
            )
        } catch {
            return (
                Data(),
                "The saved-moment preview is not a valid WonderSwan frame. SwanSong will not load this state."
            )
        }
        return (previewPNG, nil)
    }

    private func isValid(_ identity: GameStateSessionIdentity) -> Bool {
        identity.romByteCount > 0
            && validSHA256(identity.romSHA256) != nil
            && identity.firmwareByteCount >= 0
            && validSHA256(identity.firmwareSHA256) != nil
            && identity.hardwareModel.isColor == identity.isColor
            && !identity.backend.isEmpty
    }

    private func validSHA256(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let normalized = digest.lowercased()
        guard normalized.count == 64,
              normalized.allSatisfy(\.isHexDigit) else { return nil }
        return normalized
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
