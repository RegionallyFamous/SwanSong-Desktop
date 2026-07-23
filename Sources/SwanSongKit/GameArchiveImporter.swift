import Foundation

public enum LibraryGameImportError: LocalizedError, Equatable, Sendable {
    case unsafeSource
    case sourceTooLarge
    case archiveTooLarge
    case archiveOutputTooLarge
    case archiveTimedOut
    case archiveToolFailed(String)
    case unsupportedArchive
    case encryptedArchive
    case noGameInArchive
    case ambiguousArchive
    case unsafeMember
    case invalidGame

    public var errorDescription: String? {
        switch self {
        case .unsafeSource:
            "Choose a regular local game file. Links, folders, and special files are not imported."
        case .sourceTooLarge:
            "That game is outside the supported 64 KB to 16 MB ROM range."
        case .archiveTooLarge:
            "That game archive is too large to inspect safely."
        case .archiveOutputTooLarge:
            "That game archive expands beyond SwanSong’s 16 MB ROM limit."
        case .archiveTimedOut:
            "SwanSong stopped inspecting that archive because it did not respond. Extract it in Finder and choose the game directly."
        case let .archiveToolFailed(detail):
            detail.isEmpty
                ? "The game archive could not be opened."
                : "The game archive could not be opened: \(detail)"
        case .unsupportedArchive:
            "That ZIP uses an unsupported format or compression method."
        case .encryptedArchive:
            "Password-protected game archives are not supported."
        case .noGameInArchive:
            "This ZIP does not contain a .ws, .wsc, .pc2, or .pcv2 game."
        case .ambiguousArchive:
            "This ZIP contains more than one WonderSwan game. Extract it and choose the game you want."
        case .unsafeMember:
            "The game inside this ZIP has an unsafe filename or file type."
        case .invalidGame:
            "This is not a structurally valid WonderSwan ROM."
        }
    }
}

public struct LibraryGameImportImage: Sendable {
    public let data: Data
    public let suggestedTitle: String
    public let sourceFileName: String
    public let metadata: ROMMetadata
    public let sha256: String
    public let hardwareModel: EngineHardwareModel

    public init(
        data: Data,
        suggestedTitle: String,
        sourceFileName: String,
        metadata: ROMMetadata,
        sha256: String,
        hardwareModel: EngineHardwareModel = .automatic
    ) {
        self.data = data
        self.suggestedTitle = suggestedTitle
        self.sourceFileName = sourceFileName
        self.metadata = metadata
        self.sha256 = sha256
        self.hardwareModel = hardwareModel == .automatic
            ? (metadata.isColor ? .wonderSwanColor : .wonderSwan)
            : hardwareModel
    }
}

/// Library imports intentionally use a stronger policy than the shared engine
/// inspector. The engine accepts checksum-broken hacks, but also has to map
/// power-of-two images before it knows whether their cartridge footer is sane.
/// This policy keeps compatible bad-checksum/homebrew images while rejecting
/// arbitrary power-of-two data renamed to `.ws`.
public enum GameROMValidationPolicy {
    public static let minimumByteCount = 64 * 1_024
    public static let maximumByteCount = 16 * 1_024 * 1_024

    public static func validateLibraryImage(_ data: Data) throws -> ROMMetadata {
        guard data.count >= minimumByteCount,
              data.count <= maximumByteCount,
              data.count.isMultiple(of: 64 * 1_024),
              data.count >= 16 else {
            throw LibraryGameImportError.invalidGame
        }
        let footer = data.suffix(16)
        let bytes = Array(footer)
        let supportedSaveTypes: Set<UInt8> = [
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x10, 0x20, 0x50,
        ]
        guard bytes[0] == 0xea,
              bytes[5] & 0x0f == 0,
              bytes[7] <= 1,
              supportedSaveTypes.contains(bytes[11]),
              bytes[12] & 0x04 != 0,
              bytes[13] <= 1 else {
            throw LibraryGameImportError.invalidGame
        }
        do {
            return try EngineSession.inspect(rom: data)
        } catch {
            throw LibraryGameImportError.invalidGame
        }
    }

    static func sizeDeclarationIsValid(_ metadata: ROMMetadata) -> Bool {
        let declaredSizes: [UInt8: UInt64] = [
            0x00: 128 * 1_024,
            0x01: 256 * 1_024,
            0x02: 512 * 1_024,
            0x03: 1 * 1_024 * 1_024,
            0x04: 2 * 1_024 * 1_024,
            0x05: 3 * 1_024 * 1_024,
            0x06: 4 * 1_024 * 1_024,
            0x07: 6 * 1_024 * 1_024,
            0x08: 8 * 1_024 * 1_024,
            0x09: 16 * 1_024 * 1_024,
        ]
        guard let declared = declaredSizes[metadata.romSizeCode] else { return false }
        if metadata.fileSize == 64 * 1_024 {
            return declared == 128 * 1_024
        }
        if metadata.fileSize.nonzeroBitCount == 1 {
            return declared == metadata.fileSize
        }
        return declared == metadata.fileSize || declared == metadata.mappedSize
    }
}

public enum LibraryGameImageImporter {
    private static let maximumArchiveBytes = 64 * 1_024 * 1_024

    public static func image(from url: URL) throws -> LibraryGameImportImage {
        let extensionName = url.pathExtension.lowercased()
        guard ["ws", "wsc", "pc2", "pcv2", "zip"].contains(extensionName) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw LibraryGameImportError.unsafeSource
        }
        guard let byteCount = values.fileSize, byteCount > 0 else {
            throw LibraryGameImportError.unsafeSource
        }
        if extensionName == "zip" {
            guard byteCount <= maximumArchiveBytes else {
                throw LibraryGameImportError.archiveTooLarge
            }
            return try WonderSwanGameArchiveImporter.image(from: url)
        }
        guard byteCount >= GameROMValidationPolicy.minimumByteCount,
              byteCount <= GameROMValidationPolicy.maximumByteCount else {
            throw LibraryGameImportError.sourceTooLarge
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == byteCount else { throw LibraryGameImportError.unsafeSource }
        let metadata = try GameROMValidationPolicy.validateLibraryImage(data)
        return LibraryGameImportImage(
            data: data,
            suggestedTitle: url.deletingPathExtension().lastPathComponent,
            sourceFileName: url.lastPathComponent,
            metadata: metadata,
            sha256: ManagedGameStore.sha256(data),
            hardwareModel: try Self.hardwareModel(
                forExtension: extensionName,
                metadata: metadata
            )
        )
    }

    static func hardwareModel(
        forExtension extensionName: String,
        metadata: ROMMetadata
    ) throws -> EngineHardwareModel {
        switch extensionName.lowercased() {
        case "pc2", "pcv2":
            // PCV2 shares the monochrome footer shape, but a Color cartridge
            // renamed to a PCV2 extension must not cross the hardware boundary.
            guard !metadata.isColor else {
                throw LibraryGameImportError.invalidGame
            }
            return .pocketChallengeV2
        default: return metadata.isColor ? .wonderSwanColor : .wonderSwan
        }
    }
}

public enum WonderSwanGameArchiveImporter {
    private struct CentralDirectoryEntry {
        let name: String
        let flags: UInt16
        let compressionMethod: UInt16
        let compressedByteCount: UInt32
        let uncompressedByteCount: UInt32
        let externalAttributes: UInt32
        let creatorPlatform: UInt8
    }

    private static let maximumArchiveBytes = 64 * 1_024 * 1_024
    private static let maximumListingBytes = 512 * 1_024
    private static let maximumEntryCount = 16_384
    private static let maximumCandidates = 32
    private static let commandTimeout: DispatchTimeInterval = .seconds(10)

    public static func image(from url: URL) throws -> LibraryGameImportImage {
        let archive = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !archive.isEmpty, archive.count <= maximumArchiveBytes else {
            throw LibraryGameImportError.archiveTooLarge
        }
        let entries = try centralDirectoryEntries(in: archive)
        let candidates = entries.filter {
            let extensionName = URL(fileURLWithPath: $0.name).pathExtension.lowercased()
            return ["ws", "wsc", "pc2", "pcv2"].contains(extensionName)
        }
        guard candidates.count <= maximumCandidates else {
            throw LibraryGameImportError.ambiguousArchive
        }
        guard Set(candidates.map(\.name)).count == candidates.count else {
            throw LibraryGameImportError.ambiguousArchive
        }
        guard let candidate = candidates.first else {
            throw LibraryGameImportError.noGameInArchive
        }
        guard candidates.count == 1 else {
            throw LibraryGameImportError.ambiguousArchive
        }
        try validate(candidate)

        let data = try runUnzip(
            ["-p", url.path, escapedUnzipPattern(candidate.name)],
            maximumOutputBytes: GameROMValidationPolicy.maximumByteCount
        )
        guard data.count == Int(candidate.uncompressedByteCount) else {
            throw LibraryGameImportError.invalidGame
        }
        let metadata = try GameROMValidationPolicy.validateLibraryImage(data)
        let memberName = candidate.name.split(separator: "/", omittingEmptySubsequences: false).last
            .map(String.init) ?? candidate.name
        let memberExtension = URL(fileURLWithPath: memberName).pathExtension.lowercased()
        return LibraryGameImportImage(
            data: data,
            suggestedTitle: URL(fileURLWithPath: memberName).deletingPathExtension().lastPathComponent,
            sourceFileName: url.lastPathComponent,
            metadata: metadata,
            sha256: ManagedGameStore.sha256(data),
            hardwareModel: try LibraryGameImageImporter.hardwareModel(
                forExtension: memberExtension,
                metadata: metadata
            )
        )
    }

    private static func validate(_ entry: CentralDirectoryEntry) throws {
        guard safeMemberName(entry.name) else {
            throw LibraryGameImportError.unsafeMember
        }
        guard entry.flags & 0x0001 == 0 else {
            throw LibraryGameImportError.encryptedArchive
        }
        guard entry.compressionMethod == 0 || entry.compressionMethod == 8 else {
            throw LibraryGameImportError.unsupportedArchive
        }
        let mode = UInt16(entry.externalAttributes >> 16)
        let unixType = mode & 0xf000
        if entry.creatorPlatform == 3, unixType != 0, unixType != 0x8000 {
            throw LibraryGameImportError.unsafeMember
        }
        let isDOSDirectory = entry.externalAttributes & 0x10 != 0
        guard !isDOSDirectory, !entry.name.hasSuffix("/") else {
            throw LibraryGameImportError.unsafeMember
        }
        guard entry.uncompressedByteCount >= UInt32(GameROMValidationPolicy.minimumByteCount),
              entry.uncompressedByteCount <= UInt32(GameROMValidationPolicy.maximumByteCount),
              entry.compressedByteCount <= UInt32(maximumArchiveBytes) else {
            throw LibraryGameImportError.archiveOutputTooLarge
        }
    }

    private static func safeMemberName(_ name: String) -> Bool {
        guard !name.isEmpty,
              !name.hasPrefix("/"),
              !name.hasPrefix("\\"),
              !name.contains("\\"),
              !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            return false
        }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private static func centralDirectoryEntries(in archive: Data) throws -> [CentralDirectoryEntry] {
        // EOCD is at least 22 bytes and may be followed by a 65,535-byte comment.
        guard archive.count >= 22 else { throw LibraryGameImportError.unsupportedArchive }
        let searchStart = max(0, archive.count - (65_535 + 22))
        var eocdOffset: Int?
        var cursor = archive.count - 22
        while cursor >= searchStart {
            if archive.uint32LE(at: cursor) == 0x0605_4b50 {
                eocdOffset = cursor
                break
            }
            cursor -= 1
        }
        guard let eocdOffset,
              let diskNumber = archive.uint16LE(at: eocdOffset + 4),
              let directoryDisk = archive.uint16LE(at: eocdOffset + 6),
              let entriesOnDisk = archive.uint16LE(at: eocdOffset + 8),
              let entryCount = archive.uint16LE(at: eocdOffset + 10),
              let directorySize = archive.uint32LE(at: eocdOffset + 12),
              let directoryOffset = archive.uint32LE(at: eocdOffset + 16),
              let commentLength = archive.uint16LE(at: eocdOffset + 20),
              diskNumber == 0,
              directoryDisk == 0,
              entriesOnDisk == entryCount,
              entryCount != .max,
              directorySize != .max,
              directoryOffset != .max,
              Int(entryCount) <= maximumEntryCount,
              Int(directorySize) <= maximumListingBytes,
              eocdOffset + 22 + Int(commentLength) == archive.count,
              Int(directoryOffset) + Int(directorySize) <= eocdOffset else {
            throw LibraryGameImportError.unsupportedArchive
        }

        var entries: [CentralDirectoryEntry] = []
        entries.reserveCapacity(Int(entryCount))
        cursor = Int(directoryOffset)
        let directoryEnd = cursor + Int(directorySize)
        while entries.count < Int(entryCount) {
            guard cursor + 46 <= directoryEnd,
                  archive.uint32LE(at: cursor) == 0x0201_4b50,
                  let madeBy = archive.uint16LE(at: cursor + 4),
                  let flags = archive.uint16LE(at: cursor + 8),
                  let compression = archive.uint16LE(at: cursor + 10),
                  let compressed = archive.uint32LE(at: cursor + 20),
                  let uncompressed = archive.uint32LE(at: cursor + 24),
                  let nameLength = archive.uint16LE(at: cursor + 28),
                  let extraLength = archive.uint16LE(at: cursor + 30),
                  let entryCommentLength = archive.uint16LE(at: cursor + 32),
                  let externalAttributes = archive.uint32LE(at: cursor + 38) else {
                throw LibraryGameImportError.unsupportedArchive
            }
            guard compressed != .max, uncompressed != .max else {
                throw LibraryGameImportError.unsupportedArchive
            }
            let nameStart = cursor + 46
            let nameEnd = nameStart + Int(nameLength)
            let next = nameEnd + Int(extraLength) + Int(entryCommentLength)
            guard nameLength > 0, nameEnd <= directoryEnd, next <= directoryEnd else {
                throw LibraryGameImportError.unsupportedArchive
            }
            let nameData = archive.subdata(in: nameStart..<nameEnd)
            let name: String
            if flags & 0x0800 != 0 {
                guard let utf8Name = String(data: nameData, encoding: .utf8) else {
                    throw LibraryGameImportError.unsafeMember
                }
                name = utf8Name
            } else {
                name = String(data: nameData, encoding: .isoLatin1)
                    ?? String(decoding: nameData, as: UTF8.self)
            }
            entries.append(
                CentralDirectoryEntry(
                    name: name,
                    flags: flags,
                    compressionMethod: compression,
                    compressedByteCount: compressed,
                    uncompressedByteCount: uncompressed,
                    externalAttributes: externalAttributes,
                    creatorPlatform: UInt8(truncatingIfNeeded: madeBy >> 8)
                )
            )
            cursor = next
        }
        guard cursor == directoryEnd else { throw LibraryGameImportError.unsupportedArchive }
        return entries
    }

    private static func escapedUnzipPattern(_ name: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(name.count)
        for character in name {
            if "\\*?[]".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    private static func runUnzip(
        _ arguments: [String],
        maximumOutputBytes: Int
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + commandTimeout,
            execute: watchdog
        )
        defer { watchdog.cancel() }

        var data = Data()
        while data.count <= maximumOutputBytes {
            let remaining = maximumOutputBytes + 1 - data.count
            let chunk = output.fileHandleForReading.readData(
                ofLength: min(32 * 1_024, remaining)
            )
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        if data.count > maximumOutputBytes {
            process.terminate()
            process.waitUntilExit()
            throw LibraryGameImportError.archiveOutputTooLarge
        }

        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal {
            throw LibraryGameImportError.archiveTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw LibraryGameImportError.archiveToolFailed(
                "unzip exited with status \(process.terminationStatus)."
            )
        }
        return data
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let low = UInt16(bytes[offset])
            let high = UInt16(bytes[offset + 1]) << 8
            return low | high
        }
    }

    func uint32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let byte0 = UInt32(bytes[offset])
            let byte1 = UInt32(bytes[offset + 1]) << 8
            let byte2 = UInt32(bytes[offset + 2]) << 16
            let byte3 = UInt32(bytes[offset + 3]) << 24
            return byte0 | byte1 | byte2 | byte3
        }
    }
}
