import Darwin
import Foundation

public enum WonderSwanFirmwareKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case monochrome
    case color
    case pocketChallengeV2

    public var id: Self { self }

    public var title: String {
        switch self {
        case .monochrome: "WonderSwan"
        case .color: "WonderSwan Color"
        case .pocketChallengeV2: "Pocket Challenge V2"
        }
    }

    public var expectedByteCount: Int {
        switch self {
        case .monochrome: 4 * 1_024
        case .color: 8 * 1_024
        case .pocketChallengeV2: 4 * 1_024
        }
    }

    fileprivate var fileName: String {
        switch self {
        case .monochrome: "WonderSwan.boot.rom"
        case .color: "WonderSwanColor.boot.rom"
        case .pocketChallengeV2: "PocketChallengeV2.boot.rom"
        }
    }
}

public enum WonderSwanFirmwareError: LocalizedError, Equatable, Sendable {
    case unsupportedSize(Int)
    case emptyImage
    case missingResetVector
    case sizeMismatch(expected: Int, actual: Int)
    case missingImage(WonderSwanFirmwareKind)
    case unsafeStorage

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSize(actual):
            "That file is \(actual) bytes. WonderSwan startup files must be exactly 4 KiB or 8 KiB."
        case .emptyImage:
            "That does not appear to be a compatible WonderSwan startup file."
        case .missingResetVector:
            "That does not appear to be a compatible WonderSwan startup file."
        case let .sizeMismatch(expected, actual):
            "The installed startup file is \(actual) bytes; \(expected) bytes were expected."
        case let .missingImage(kind):
            "The installed \(kind.title) startup file is missing."
        case .unsafeStorage:
            "The startup-file location is not a private, regular folder."
        }
    }
}

public struct WonderSwanFirmwareStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let root = SwanSongDataRootPolicy.defaultResolution(fileManager: fileManager).rootURL
        return Self(
            rootURL: root
                .appendingPathComponent("Firmware", isDirectory: true)
        )
    }

    public func install(
        _ data: Data,
        as requestedKind: WonderSwanFirmwareKind? = nil
    ) throws -> WonderSwanFirmwareKind {
        let kind = try requestedKind ?? Self.kind(for: data)
        try Self.validate(data, for: kind)
        try prepareStorage()
        let destination = fileURL(for: kind)
        _ = try secureItemIfPresent(
            at: destination,
            expectedType: .typeRegular
        )

        let fileManager = FileManager.default
        let temporary = rootURL.appendingPathComponent(
            ".firmware-install-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        guard fileManager.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw WonderSwanFirmwareError.unsafeStorage
        }

        var writer: FileHandle? = try FileHandle(forWritingTo: temporary)
        var committed = false
        defer {
            try? writer?.close()
            if !committed {
                try? fileManager.removeItem(at: temporary)
            }
        }

        guard let activeWriter = writer else {
            throw WonderSwanFirmwareError.unsafeStorage
        }
        try activeWriter.write(contentsOf: data)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temporary.path
        )
        guard try secureItemIfPresent(
            at: temporary,
            expectedType: .typeRegular,
            requiredPermissions: 0o600
        ) else {
            throw WonderSwanFirmwareError.unsafeStorage
        }
        try activeWriter.synchronize()
        try activeWriter.close()
        writer = nil

        // Revalidate both the private directory and the destination immediately
        // before the rename. The rename is the commit point: every operation
        // that can reject the new image has already completed, so the old image
        // remains intact on any earlier failure.
        try validateExistingStorage()
        _ = try secureItemIfPresent(
            at: destination,
            expectedType: .typeRegular
        )
        try Self.atomicRename(from: temporary, to: destination)
        committed = true
        return kind
    }

    public func load(_ kind: WonderSwanFirmwareKind) throws -> Data? {
        guard try storageExists() else { return nil }
        let url = fileURL(for: kind)
        guard try secureItemIfPresent(
            at: url,
            expectedType: .typeRegular,
            requiredPermissions: 0o600,
            repairPermissions: true
        ) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count == kind.expectedByteCount else {
            throw WonderSwanFirmwareError.sizeMismatch(
                expected: kind.expectedByteCount,
                actual: data.count
            )
        }
        try Self.validateContent(data)
        return data
    }

    public func isInstalled(_ kind: WonderSwanFirmwareKind) -> Bool {
        (try? load(kind)) != nil
    }

    public func remove(_ kind: WonderSwanFirmwareKind) throws {
        guard try storageExists() else { return }
        let url = fileURL(for: kind)
        guard try secureItemIfPresent(
            at: url,
            expectedType: .typeRegular
        ) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Creates or repairs the private firmware directory without installing an
    /// image. UI surfaces can use this before revealing the storage location.
    @discardableResult
    public func prepareStorage() throws -> URL {
        let fileManager = FileManager.default
        let parent = rootURL.deletingLastPathComponent()
        if try attributesIfPresent(at: parent) == nil {
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        }
        guard try secureItemIfPresent(
            at: parent,
            expectedType: .typeDirectory
        ) else {
            throw WonderSwanFirmwareError.unsafeStorage
        }

        if try attributesIfPresent(at: rootURL) == nil {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard try secureItemIfPresent(
            at: rootURL,
            expectedType: .typeDirectory,
            requiredPermissions: 0o700,
            repairPermissions: true
        ) else {
            throw WonderSwanFirmwareError.unsafeStorage
        }
        return rootURL
    }

    public func fileURL(for kind: WonderSwanFirmwareKind) -> URL {
        rootURL.appendingPathComponent(kind.fileName, isDirectory: false)
    }

    public static func kind(for data: Data) throws -> WonderSwanFirmwareKind {
        let kind: WonderSwanFirmwareKind
        switch data.count {
        case WonderSwanFirmwareKind.monochrome.expectedByteCount:
            kind = .monochrome
        case WonderSwanFirmwareKind.color.expectedByteCount:
            kind = .color
        default:
            throw WonderSwanFirmwareError.unsupportedSize(data.count)
        }
        try validateContent(data)
        return kind
    }

    public static func validate(
        _ data: Data,
        for kind: WonderSwanFirmwareKind
    ) throws {
        guard data.count == kind.expectedByteCount else {
            throw WonderSwanFirmwareError.sizeMismatch(
                expected: kind.expectedByteCount,
                actual: data.count
            )
        }
        try validateContent(data)
    }

    private static func validateContent(_ data: Data) throws {
        guard let first = data.first,
              data.contains(where: { $0 != first }) else {
            throw WonderSwanFirmwareError.emptyImage
        }
        guard data.count >= 16 else {
            throw WonderSwanFirmwareError.missingResetVector
        }

        let vector = data.count - 16
        guard data[vector] == 0xea else {
            throw WonderSwanFirmwareError.missingResetVector
        }
        let offset = UInt32(data[vector + 1])
            | (UInt32(data[vector + 2]) << 8)
        let segment = UInt32(data[vector + 3])
            | (UInt32(data[vector + 4]) << 8)
        let target = ((segment << 4) + offset) & 0x000f_ffff
        let mappedStart = UInt32(0x10_0000 - data.count)
        guard target >= mappedStart, target < 0x10_0000 else {
            throw WonderSwanFirmwareError.missingResetVector
        }
    }

    private func storageExists() throws -> Bool {
        guard try attributesIfPresent(at: rootURL) != nil else { return false }
        try validateExistingStorage()
        return true
    }

    private func validateExistingStorage() throws {
        let parent = rootURL.deletingLastPathComponent()
        guard try secureItemIfPresent(
            at: parent,
            expectedType: .typeDirectory
        ) else {
            throw WonderSwanFirmwareError.unsafeStorage
        }
        guard try secureItemIfPresent(
            at: rootURL,
            expectedType: .typeDirectory,
            requiredPermissions: 0o700,
            repairPermissions: true
        ) else {
            throw WonderSwanFirmwareError.unsafeStorage
        }
    }

    private func attributesIfPresent(
        at url: URL
    ) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as CocoaError
            where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    @discardableResult
    private func secureItemIfPresent(
        at url: URL,
        expectedType: FileAttributeType,
        requiredPermissions: Int? = nil,
        repairPermissions: Bool = false
    ) throws -> Bool {
        let fileManager = FileManager.default
        guard var attributes = try attributesIfPresent(at: url) else { return false }
        guard attributes[.type] as? FileAttributeType == expectedType,
              let owner = attributes[.ownerAccountID] as? NSNumber,
              owner.uint32Value == getuid() else {
            throw WonderSwanFirmwareError.unsafeStorage
        }

        if let requiredPermissions {
            let current = (attributes[.posixPermissions] as? NSNumber)?.intValue
            if current != requiredPermissions, repairPermissions {
                try fileManager.setAttributes(
                    [.posixPermissions: requiredPermissions],
                    ofItemAtPath: url.path
                )
                guard let repaired = try attributesIfPresent(at: url) else {
                    throw WonderSwanFirmwareError.unsafeStorage
                }
                attributes = repaired
            }
            guard (attributes[.posixPermissions] as? NSNumber)?.intValue
                    == requiredPermissions else {
                throw WonderSwanFirmwareError.unsafeStorage
            }
        }
        return true
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
