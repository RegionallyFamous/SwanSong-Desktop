import Foundation

public enum TranslationPatchError: LocalizedError, Equatable, Sendable {
    case unsafeManifest
    case manifestTooLarge
    case invalidManifest
    case ineligibleRelease
    case unsupportedPlatform(String)
    case unsupportedPatchFormat(String)
    case unsafePatchPath
    case patchTooLarge
    case patchByteCountMismatch(expected: Int, actual: Int)
    case patchSHA256Mismatch
    case originalByteCountMismatch(expected: Int, actual: Int)
    case originalSHA256Mismatch
    case malformedIPS
    case outputByteCountMismatch(expected: Int, actual: Int)
    case outputSHA256Mismatch
    case invalidOutput
    case invalidOutputChecksum
    case changedPersistenceContract
    case conflictingLibraryIdentity

    public var errorDescription: String? {
        switch self {
        case .unsafeManifest:
            "Choose a regular local release.json file. Links, folders, and special files are not accepted."
        case .manifestTooLarge:
            "That release manifest is too large to inspect safely."
        case .invalidManifest:
            "That file is not a supported SwanSong translation release manifest."
        case .ineligibleRelease:
            "This translation package is not marked source-free and release-certified."
        case let .unsupportedPlatform(platform):
            "This translation targets \(platform), which this installer does not support."
        case let .unsupportedPatchFormat(format):
            "This translation uses \(format). This version of SwanSong installs IPS patches."
        case .unsafePatchPath:
            "The release manifest points outside its own package or to an unsafe patch file."
        case .patchTooLarge:
            "That patch is too large to inspect safely."
        case let .patchByteCountMismatch(expected, actual):
            "The patch size does not match the release manifest (expected \(expected) bytes, found \(actual))."
        case .patchSHA256Mismatch:
            "The patch does not match the release manifest. Download or copy a clean release package."
        case let .originalByteCountMismatch(expected, actual):
            "That is the wrong game or revision (expected \(expected) bytes, found \(actual))."
        case .originalSHA256Mismatch:
            "That is not the exact original game revision required by this translation."
        case .malformedIPS:
            "The IPS patch is damaged or uses an unsupported record layout."
        case let .outputByteCountMismatch(expected, actual):
            "The finished game has the wrong size (expected \(expected) bytes, produced \(actual))."
        case .outputSHA256Mismatch:
            "The finished game does not match the certified release hash."
        case .invalidOutput:
            "The finished file is not a structurally valid WonderSwan game."
        case .invalidOutputChecksum:
            "The finished game has an invalid WonderSwan cartridge checksum."
        case .changedPersistenceContract:
            "The translation unexpectedly changes the cartridge save or real-time-clock hardware contract."
        case .conflictingLibraryIdentity:
            "A different library entry already claims this translated release."
        }
    }
}

public struct TranslationPatchReleaseManifest: Hashable, Sendable {
    public let schema: String
    public let title: String
    public let platform: String
    public let revision: String?
    public let translationVersion: String
    public let inputByteCount: Int
    public let inputSHA256: String
    public let patchPath: String
    public let patchByteCount: Int
    public let patchSHA256: String
    public let outputByteCount: Int
    public let outputSHA256: String
    public let certificateSHA256: String?

    public var hardwareModel: EngineHardwareModel {
        platform == "WonderSwan Color" ? .wonderSwanColor : .wonderSwan
    }

    public var libraryTitle: String {
        "\(title) — English"
    }
}

public struct TranslationPatchPackage: Sendable {
    public static let maximumManifestByteCount = 1 * 1_024 * 1_024
    public static let maximumPatchByteCount = 64 * 1_024 * 1_024

    public let manifest: TranslationPatchReleaseManifest
    public let manifestURL: URL
    public let manifestSHA256: String
    public let patchURL: URL
    public let patchData: Data

    public init(manifestURL: URL) throws {
        let manifestURL = manifestURL.standardizedFileURL
        let manifestValues = try manifestURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard manifestValues.isRegularFile == true,
              manifestValues.isSymbolicLink != true,
              let manifestByteCount = manifestValues.fileSize,
              manifestByteCount > 0 else {
            throw TranslationPatchError.unsafeManifest
        }
        guard manifestByteCount <= Self.maximumManifestByteCount else {
            throw TranslationPatchError.manifestTooLarge
        }

        let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        guard manifestData.count == manifestByteCount else {
            throw TranslationPatchError.unsafeManifest
        }
        let raw: RawManifest
        do {
            raw = try JSONDecoder().decode(RawManifest.self, from: manifestData)
        } catch {
            throw TranslationPatchError.invalidManifest
        }
        let manifest = try raw.validated()

        let manifestDirectory = manifestURL.deletingLastPathComponent()
        let packageRoot = manifestDirectory.lastPathComponent == "release"
            ? manifestDirectory.deletingLastPathComponent()
            : manifestDirectory
        let patchURL = packageRoot
            .appendingPathComponent(manifest.patchPath, isDirectory: false)
            .standardizedFileURL
        let resolvedRoot = packageRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedPatch = patchURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path
            : resolvedRoot.path + "/"
        guard resolvedPatch.path.hasPrefix(rootPrefix) else {
            throw TranslationPatchError.unsafePatchPath
        }

        let patchValues = try patchURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard patchValues.isRegularFile == true,
              patchValues.isSymbolicLink != true,
              let patchByteCount = patchValues.fileSize,
              patchByteCount > 0 else {
            throw TranslationPatchError.unsafePatchPath
        }
        guard patchByteCount <= Self.maximumPatchByteCount else {
            throw TranslationPatchError.patchTooLarge
        }
        guard patchByteCount == manifest.patchByteCount else {
            throw TranslationPatchError.patchByteCountMismatch(
                expected: manifest.patchByteCount,
                actual: patchByteCount
            )
        }
        let patchData = try Data(contentsOf: patchURL, options: [.mappedIfSafe])
        guard patchData.count == patchByteCount else {
            throw TranslationPatchError.unsafePatchPath
        }
        guard ManagedGameStore.sha256(patchData) == manifest.patchSHA256 else {
            throw TranslationPatchError.patchSHA256Mismatch
        }

        self.manifest = manifest
        self.manifestURL = manifestURL
        self.manifestSHA256 = ManagedGameStore.sha256(manifestData)
        self.patchURL = patchURL
        self.patchData = patchData
    }
}

public struct TranslationPatchOrigin: Codable, Hashable, Sendable {
    public let title: String
    public let revision: String?
    public let translationVersion: String
    public let manifestSHA256: String
    public let inputSHA256: String
    public let patchSHA256: String
    public let outputSHA256: String

    public init(
        title: String,
        revision: String?,
        translationVersion: String,
        manifestSHA256: String,
        inputSHA256: String,
        patchSHA256: String,
        outputSHA256: String
    ) {
        self.title = title
        self.revision = revision
        self.translationVersion = translationVersion
        self.manifestSHA256 = manifestSHA256
        self.inputSHA256 = inputSHA256
        self.patchSHA256 = patchSHA256
        self.outputSHA256 = outputSHA256
    }
}

public enum TranslationPatchInstallAction: Equatable, Sendable {
    case installed
    case adopted
    case unchanged
    case repaired
}

public struct TranslationPatchInstallResult: Sendable {
    public let games: [GameRecord]
    public let gameID: GameRecord.ID
    public let createdReference: ManagedGameReference?
    public let action: TranslationPatchInstallAction

    public init(
        games: [GameRecord],
        gameID: GameRecord.ID,
        createdReference: ManagedGameReference?,
        action: TranslationPatchInstallAction
    ) {
        self.games = games
        self.gameID = gameID
        self.createdReference = createdReference
        self.action = action
    }
}

public struct TranslationPatchInstaller: Sendable {
    public let package: TranslationPatchPackage

    public init(package: TranslationPatchPackage) {
        self.package = package
    }

    public func install(
        originalImage: LibraryGameImportImage,
        into existingGames: [GameRecord],
        managedStore: ManagedGameStore
    ) throws -> TranslationPatchInstallResult {
        let manifest = package.manifest
        guard originalImage.data.count == manifest.inputByteCount else {
            throw TranslationPatchError.originalByteCountMismatch(
                expected: manifest.inputByteCount,
                actual: originalImage.data.count
            )
        }
        guard originalImage.sha256 == manifest.inputSHA256 else {
            throw TranslationPatchError.originalSHA256Mismatch
        }
        guard manifest.hardwareModel == originalImage.hardwareModel else {
            throw TranslationPatchError.unsupportedPlatform(manifest.platform)
        }

        let outputData = try IPSPatch.apply(
            package.patchData,
            to: originalImage.data,
            expectedOutputByteCount: manifest.outputByteCount
        )
        guard outputData.count == manifest.outputByteCount else {
            throw TranslationPatchError.outputByteCountMismatch(
                expected: manifest.outputByteCount,
                actual: outputData.count
            )
        }
        guard ManagedGameStore.sha256(outputData) == manifest.outputSHA256 else {
            throw TranslationPatchError.outputSHA256Mismatch
        }

        let metadata: ROMMetadata
        do {
            metadata = try GameROMValidationPolicy.validateLibraryImage(outputData)
        } catch {
            throw TranslationPatchError.invalidOutput
        }
        guard metadata.checksumIsValid else {
            throw TranslationPatchError.invalidOutputChecksum
        }
        guard GameROMValidationPolicy.sizeDeclarationIsValid(metadata),
              (manifest.hardwareModel == .wonderSwanColor) == metadata.isColor else {
            throw TranslationPatchError.invalidOutput
        }
        guard originalImage.metadata.isColor == metadata.isColor,
              originalImage.metadata.saveType == metadata.saveType,
              originalImage.metadata.hasRTC == metadata.hasRTC else {
            throw TranslationPatchError.changedPersistenceContract
        }

        let origin = TranslationPatchOrigin(
            title: manifest.title,
            revision: manifest.revision,
            translationVersion: manifest.translationVersion,
            manifestSHA256: package.manifestSHA256,
            inputSHA256: manifest.inputSHA256,
            patchSHA256: manifest.patchSHA256,
            outputSHA256: manifest.outputSHA256
        )
        let fileExtension = metadata.isColor ? "wsc" : "ws"
        let sourceFileName = "\(manifest.title) English v\(manifest.translationVersion).\(fileExtension)"
        let image = LibraryGameImportImage(
            data: outputData,
            suggestedTitle: manifest.libraryTitle,
            sourceFileName: sourceFileName,
            metadata: metadata,
            sha256: manifest.outputSHA256,
            hardwareModel: manifest.hardwareModel
        )
        let originIndices = existingGames.indices.filter {
            existingGames[$0].translationPatchOrigin == origin
        }
        guard originIndices.count <= 1 else {
            throw TranslationPatchError.conflictingLibraryIdentity
        }
        if let originIndex = originIndices.first {
            guard let reference = existingGames[originIndex].managedROM,
                  reference.sha256 == manifest.outputSHA256 else {
                throw TranslationPatchError.conflictingLibraryIdentity
            }
            switch managedStore.health(of: reference) {
            case .healthy:
                return TranslationPatchInstallResult(
                    games: existingGames,
                    gameID: existingGames[originIndex].id,
                    createdReference: nil,
                    action: .unchanged
                )
            case .missing, .changed:
                _ = try managedStore.repair(image, matching: reference)
                return TranslationPatchInstallResult(
                    games: existingGames,
                    gameID: existingGames[originIndex].id,
                    createdReference: nil,
                    action: .repaired
                )
            case .invalidReference:
                throw TranslationPatchError.conflictingLibraryIdentity
            }
        }

        let digestIndices = existingGames.indices.filter {
            existingGames[$0].managedROM?.sha256 == manifest.outputSHA256
        }
        guard digestIndices.count <= 1 else {
            throw TranslationPatchError.conflictingLibraryIdentity
        }

        let targetIndex: Int?
        let action: TranslationPatchInstallAction
        if let digestIndex = digestIndices.first {
            guard existingGames[digestIndex].translationPatchOrigin == nil,
                  existingGames[digestIndex].homebrewCatalogOrigin == nil else {
                throw TranslationPatchError.conflictingLibraryIdentity
            }
            targetIndex = digestIndex
            action = .adopted
        } else {
            targetIndex = nil
            action = .installed
        }

        let installed = try managedStore.install(image)

        var games = existingGames
        let gameID: GameRecord.ID
        if let targetIndex {
            gameID = games[targetIndex].id
            games[targetIndex].fileURL = installed.fileURL
            games[targetIndex].metadata = metadata
            games[targetIndex].managedROM = installed.reference
            games[targetIndex].sourceFileName = sourceFileName
            games[targetIndex].translationPatchOrigin = origin
            games[targetIndex].preferredHardwareModel = manifest.hardwareModel
        } else {
            let game = GameRecord(
                title: manifest.libraryTitle,
                fileURL: installed.fileURL,
                metadata: metadata,
                managedROM: installed.reference,
                sourceFileName: sourceFileName,
                translationPatchOrigin: origin,
                preferredHardwareModel: manifest.hardwareModel
            )
            games.append(game)
            gameID = game.id
        }

        return TranslationPatchInstallResult(
            games: games,
            gameID: gameID,
            createdReference: installed.created ? installed.reference : nil,
            action: action
        )
    }

}

public enum IPSPatch {
    public static func apply(
        _ patch: Data,
        to original: Data,
        expectedOutputByteCount: Int
    ) throws -> Data {
        guard expectedOutputByteCount >= GameROMValidationPolicy.minimumByteCount,
              expectedOutputByteCount <= GameROMValidationPolicy.maximumByteCount else {
            throw TranslationPatchError.malformedIPS
        }
        let bytes = [UInt8](patch)
        guard bytes.count >= 8,
              Array(bytes[0..<5]) == Array("PATCH".utf8) else {
            throw TranslationPatchError.malformedIPS
        }

        var output = [UInt8](original)
        var index = 5
        var recordCount = 0
        var foundEOF = false
        while index + 3 <= bytes.count {
            if bytes[index] == 0x45,
               bytes[index + 1] == 0x4f,
               bytes[index + 2] == 0x46 {
                index += 3
                foundEOF = true
                break
            }
            recordCount += 1
            guard recordCount <= 1_000_000 else {
                throw TranslationPatchError.malformedIPS
            }
            let offset = Int(bytes[index]) << 16
                | Int(bytes[index + 1]) << 8
                | Int(bytes[index + 2])
            index += 3
            guard index + 2 <= bytes.count else {
                throw TranslationPatchError.malformedIPS
            }
            let literalByteCount = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2

            if literalByteCount == 0 {
                guard index + 3 <= bytes.count else {
                    throw TranslationPatchError.malformedIPS
                }
                let runByteCount = Int(bytes[index]) << 8 | Int(bytes[index + 1])
                let value = bytes[index + 2]
                index += 3
                guard runByteCount > 0 else {
                    throw TranslationPatchError.malformedIPS
                }
                try write(
                    repeatElement(value, count: runByteCount),
                    at: offset,
                    into: &output,
                    maximumByteCount: expectedOutputByteCount
                )
            } else {
                guard index + literalByteCount <= bytes.count else {
                    throw TranslationPatchError.malformedIPS
                }
                try write(
                    bytes[index..<(index + literalByteCount)],
                    at: offset,
                    into: &output,
                    maximumByteCount: expectedOutputByteCount
                )
                index += literalByteCount
            }
        }
        guard foundEOF else {
            throw TranslationPatchError.malformedIPS
        }

        if index == bytes.count {
            // The common IPS form leaves the source size unchanged.
        } else if index + 3 == bytes.count {
            let declaredOutputByteCount = Int(bytes[index]) << 16
                | Int(bytes[index + 1]) << 8
                | Int(bytes[index + 2])
            guard declaredOutputByteCount == expectedOutputByteCount else {
                throw TranslationPatchError.malformedIPS
            }
            if output.count < declaredOutputByteCount {
                output.append(
                    contentsOf: repeatElement(
                        0,
                        count: declaredOutputByteCount - output.count
                    )
                )
            } else if output.count > declaredOutputByteCount {
                output.removeSubrange(declaredOutputByteCount..<output.count)
            }
        } else {
            throw TranslationPatchError.malformedIPS
        }
        guard output.count == expectedOutputByteCount else {
            throw TranslationPatchError.outputByteCountMismatch(
                expected: expectedOutputByteCount,
                actual: output.count
            )
        }
        return Data(output)
    }

    private static func write<S: Sequence>(
        _ values: S,
        at offset: Int,
        into output: inout [UInt8],
        maximumByteCount: Int
    ) throws where S.Element == UInt8 {
        let values = Array(values)
        guard offset >= 0,
              values.count <= maximumByteCount,
              offset <= maximumByteCount - values.count else {
            throw TranslationPatchError.malformedIPS
        }
        let end = offset + values.count
        if output.count < end {
            output.append(contentsOf: repeatElement(0, count: end - output.count))
        }
        output.replaceSubrange(offset..<end, with: values)
    }
}

private struct RawManifest: Decodable {
    struct FileIdentity: Decodable {
        let byteCount: Int
        let sha256: String
    }

    struct PatchIdentity: Decodable {
        let format: String
        let path: String
        let byteCount: Int
        let sha256: String
    }

    struct OutputIdentity: Decodable {
        let byteCount: Int
        let sha256: String
        let checksumValid: Bool
    }

    struct CertificateIdentity: Decodable {
        let sha256: String
    }

    enum Version: Decodable {
        case string(String)
        case integer(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .integer(try container.decode(Int.self))
            }
        }

        var stringValue: String {
            switch self {
            case let .string(value): value
            case let .integer(value): String(value)
            }
        }
    }

    let schema: String
    let status: String
    let sourceFree: Bool
    let releaseEligible: Bool
    let title: String
    let platform: String
    let revision: String?
    let translationVersion: Version
    let input: FileIdentity
    let patch: PatchIdentity
    let output: OutputIdentity
    let certificate: CertificateIdentity?

    func validated() throws -> TranslationPatchReleaseManifest {
        guard schema.hasSuffix("-distributable-release-v1"),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200,
              translationVersion.stringValue.count <= 40,
              !translationVersion.stringValue.isEmpty,
              input.byteCount >= GameROMValidationPolicy.minimumByteCount,
              input.byteCount <= GameROMValidationPolicy.maximumByteCount,
              output.byteCount >= GameROMValidationPolicy.minimumByteCount,
              output.byteCount <= GameROMValidationPolicy.maximumByteCount,
              patch.byteCount >= 8,
              patch.byteCount <= TranslationPatchPackage.maximumPatchByteCount,
              validSHA256(input.sha256),
              validSHA256(patch.sha256),
              validSHA256(output.sha256),
              certificate.map({ validSHA256($0.sha256) }) ?? true else {
            throw TranslationPatchError.invalidManifest
        }
        guard status == "release-certified",
              sourceFree,
              releaseEligible,
              output.checksumValid else {
            throw TranslationPatchError.ineligibleRelease
        }
        guard platform == "WonderSwan" || platform == "WonderSwan Color" else {
            throw TranslationPatchError.unsupportedPlatform(platform)
        }
        guard patch.format.uppercased() == "IPS" else {
            throw TranslationPatchError.unsupportedPatchFormat(patch.format)
        }
        guard Self.safeRelativePath(patch.path) else {
            throw TranslationPatchError.unsafePatchPath
        }

        return TranslationPatchReleaseManifest(
            schema: schema,
            title: title,
            platform: platform,
            revision: revision,
            translationVersion: translationVersion.stringValue,
            inputByteCount: input.byteCount,
            inputSHA256: input.sha256.lowercased(),
            patchPath: patch.path,
            patchByteCount: patch.byteCount,
            patchSHA256: patch.sha256.lowercased(),
            outputByteCount: output.byteCount,
            outputSHA256: output.sha256.lowercased(),
            certificateSHA256: certificate?.sha256.lowercased()
        )
    }

    private func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            guard let ascii = $0.asciiValue else { return false }
            return (48...57).contains(ascii)
                || (65...70).contains(ascii)
                || (97...102).contains(ascii)
        }
    }

    private static func safeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\"),
              !path.contains("\0") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}
