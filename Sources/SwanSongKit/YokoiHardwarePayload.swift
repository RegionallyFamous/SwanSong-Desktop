import Compression
import CryptoKit
import Foundation

public struct YokoiHardwarePayload: Equatable, Sendable {
    public let version: String
    public let installerROM: Data
    public let installerFileName: String
    public let installerSHA256: String
    public let cartService: Data
    public let cartServiceSHA256: String
    public let sourceURL: URL
    public let sourceRevision: String

    public init(
        version: String,
        installerROM: Data,
        installerFileName: String,
        installerSHA256: String,
        cartService: Data,
        cartServiceSHA256: String,
        sourceURL: URL,
        sourceRevision: String
    ) {
        self.version = version
        self.installerROM = installerROM
        self.installerFileName = installerFileName
        self.installerSHA256 = installerSHA256
        self.cartService = cartService
        self.cartServiceSHA256 = cartServiceSHA256
        self.sourceURL = sourceURL
        self.sourceRevision = sourceRevision
    }
}

public enum YokoiHardwarePayloadLoader {
    private struct Manifest: Decodable {
        struct Artifact: Decodable {
            let encodedFile: String
            let outputFile: String
            let compression: String
            let byteCount: Int
            let sha256: String
        }

        let schema: String
        let version: String
        let source: String
        let sourceRevision: String
        let installer: Artifact
        let cartService: Artifact
    }

    public static func bundledRoot(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent("YokoiHardware", isDirectory: true)
    }

    public static func loadBundled(bundle: Bundle = .main) throws -> YokoiHardwarePayload {
        guard let root = bundledRoot(bundle: bundle) else {
            throw YokoiHardwareError.invalidFirmware(
                "SwanSong could not locate its Yokoi hardware-support payload."
            )
        }
        return try load(at: root)
    }

    public static func load(at root: URL) throws -> YokoiHardwarePayload {
        let candidateRoot = root.standardizedFileURL
        let candidateValues = try candidateRoot.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard candidateValues.isDirectory == true,
              candidateValues.isSymbolicLink != true else {
            throw YokoiHardwareError.invalidFirmware(
                "The Yokoi hardware-support location is not a regular directory."
            )
        }
        let resolvedRoot = candidateRoot.resolvingSymlinksInPath()
        let manifestURL = resolvedRoot.appendingPathComponent("manifest.json")
        let manifestData = try readRegularFile(manifestURL, maximum: 64 * 1_024)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schema == "swan-song-yokoi-hardware-v1",
              !manifest.version.isEmpty,
              let sourceURL = URL(string: manifest.source),
              sourceURL.scheme == "https",
              manifest.sourceRevision.count == 40,
              manifest.sourceRevision == manifest.sourceRevision.lowercased(),
              manifest.sourceRevision.allSatisfy(\.isHexDigit),
              manifest.source == "https://github.com/RegionallyFamous/swansong-core/tree/\(manifest.sourceRevision)/firmware" else {
            throw YokoiHardwareError.invalidFirmware(
                "The Yokoi hardware-support manifest has an unsupported identity."
            )
        }

        let installer = try decode(manifest.installer, under: resolvedRoot, maximum: 256 * 1_024)
        let service = try decode(manifest.cartService, under: resolvedRoot, maximum: 64 * 1_024)
        guard installer.prefix(2) != Data([0x62, 0x46]),
              installer.count >= 16,
              installer[installer.count - 16] == 0xEA,
              service.prefix(2) == Data([0x62, 0x46]) else {
            throw YokoiHardwareError.invalidFirmware(
                "The Yokoi installer or cartridge-service payload has the wrong format."
            )
        }
        return YokoiHardwarePayload(
            version: manifest.version,
            installerROM: installer,
            installerFileName: manifest.installer.outputFile,
            installerSHA256: manifest.installer.sha256,
            cartService: service,
            cartServiceSHA256: manifest.cartService.sha256,
            sourceURL: sourceURL,
            sourceRevision: manifest.sourceRevision
        )
    }

    private static func decode(
        _ artifact: Manifest.Artifact,
        under root: URL,
        maximum: Int
    ) throws -> Data {
        guard artifact.compression == "raw-deflate+base64",
              artifact.byteCount > 0,
              artifact.byteCount <= maximum,
              safeName(artifact.encodedFile),
              safeName(artifact.outputFile),
              artifact.sha256.count == 64,
              artifact.sha256 == artifact.sha256.lowercased(),
              artifact.sha256.allSatisfy(\.isHexDigit) else {
            throw YokoiHardwareError.invalidFirmware(
                "A Yokoi hardware artifact has an unsafe manifest entry."
            )
        }
        let encoded = try readRegularFile(
            root.appendingPathComponent(artifact.encodedFile),
            maximum: maximum * 2
        )
        guard let compressed = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]),
              compressed.count <= maximum else {
            throw YokoiHardwareError.invalidFirmware(
                "A Yokoi hardware artifact is not valid bounded Base64 data."
            )
        }
        let data = try inflateRawDeflate(compressed, maximum: maximum)
        guard data.count == artifact.byteCount,
              sha256(data) == artifact.sha256 else {
            throw YokoiHardwareError.invalidFirmware(
                "A Yokoi hardware artifact did not match its size and SHA-256."
            )
        }
        return data
    }

    private static func readRegularFile(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size <= maximum else {
            throw YokoiHardwareError.invalidFirmware(
                "The Yokoi support payload contains a missing, linked, or oversized file."
            )
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func inflateRawDeflate(_ compressed: Data, maximum: Int) throws -> Data {
        var output = Data(count: maximum + 1)
        let decoded = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded > 0, decoded <= maximum else {
            throw YokoiHardwareError.invalidFirmware(
                "A Yokoi hardware artifact could not be decompressed within its size limit."
            )
        }
        output.removeSubrange(decoded..<output.count)
        return output
    }

    private static func safeName(_ value: String) -> Bool {
        !value.isEmpty && value == URL(fileURLWithPath: value).lastPathComponent
            && !value.contains("/") && !value.contains("\\")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum YokoiInstallerMediaState: Equatable, Sendable {
    case ready
    case alreadyPresent
}

public struct YokoiInstallerMediaPlan: Equatable, Sendable {
    public let selectedFolder: URL
    public let destination: URL
    public let volumeName: String
    public let volumeIsRemovable: Bool?
    public let state: YokoiInstallerMediaState
    public let installerSHA256: String
    public let byteCount: Int

    public init(
        selectedFolder: URL,
        destination: URL,
        volumeName: String,
        volumeIsRemovable: Bool?,
        state: YokoiInstallerMediaState,
        installerSHA256: String,
        byteCount: Int
    ) {
        self.selectedFolder = selectedFolder
        self.destination = destination
        self.volumeName = volumeName
        self.volumeIsRemovable = volumeIsRemovable
        self.state = state
        self.installerSHA256 = installerSHA256
        self.byteCount = byteCount
    }
}

public struct YokoiInstallerMediaResult: Equatable, Sendable {
    public let destination: URL
    public let byteCount: Int
    public let sha256: String
    public let wasAlreadyPresent: Bool
}

public enum YokoiInstallerMedia {
    public static func plan(
        payload: YokoiHardwarePayload,
        selectedFolder: URL,
        fileManager: FileManager = .default
    ) throws -> YokoiInstallerMediaPlan {
        let folder = selectedFolder.standardizedFileURL.resolvingSymlinksInPath()
        let values = try folder.resourceValues(forKeys: [
            .isDirectoryKey, .volumeIsReadOnlyKey, .volumeIsRemovableKey,
            .volumeNameKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard values.isDirectory == true else {
            throw YokoiHardwareError.verificationFailed(
                "Choose a folder on the flash cartridge's SD card."
            )
        }
        guard values.volumeIsReadOnly != true else {
            throw YokoiHardwareError.verificationFailed(
                "The selected SD card or folder is read-only."
            )
        }
        if let capacity = values.volumeAvailableCapacityForImportantUsage,
           capacity < Int64(payload.installerROM.count + 1_048_576) {
            throw YokoiHardwareError.verificationFailed(
                "The selected SD card does not have enough free space."
            )
        }

        var destination = folder.appendingPathComponent(payload.installerFileName)
        var state: YokoiInstallerMediaState = .ready
        if fileManager.fileExists(atPath: destination.path) {
            let existing = try regularExistingFile(at: destination)
            if existing.count == payload.installerROM.count,
               sha256(existing) == payload.installerSHA256 {
                state = .alreadyPresent
            } else {
                let stem = destination.deletingPathExtension().lastPathComponent
                let extensionName = destination.pathExtension
                var found = false
                for suffix in 2...999 {
                    let candidate = folder.appendingPathComponent(
                        "\(stem) \(suffix).\(extensionName)"
                    )
                    if !fileManager.fileExists(atPath: candidate.path) {
                        destination = candidate
                        found = true
                        break
                    }
                }
                guard found else {
                    throw YokoiHardwareError.verificationFailed(
                        "The selected folder contains too many installer copies."
                    )
                }
            }
        }
        return YokoiInstallerMediaPlan(
            selectedFolder: folder,
            destination: destination,
            volumeName: values.volumeName ?? folder.lastPathComponent,
            volumeIsRemovable: values.volumeIsRemovable,
            state: state,
            installerSHA256: payload.installerSHA256,
            byteCount: payload.installerROM.count
        )
    }

    public static func install(
        payload: YokoiHardwarePayload,
        plan: YokoiInstallerMediaPlan,
        fileManager: FileManager = .default
    ) throws -> YokoiInstallerMediaResult {
        let selectedFolder = plan.selectedFolder.standardizedFileURL.resolvingSymlinksInPath()
        let destinationParent = plan.destination.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        let folderValues = try selectedFolder.resourceValues(forKeys: [
            .isDirectoryKey, .volumeIsReadOnlyKey,
        ])
        guard folderValues.isDirectory == true,
              folderValues.volumeIsReadOnly != true,
              destinationParent == selectedFolder,
              plan.byteCount == payload.installerROM.count,
              plan.installerSHA256 == payload.installerSHA256,
              sha256(payload.installerROM) == payload.installerSHA256 else {
            throw YokoiHardwareError.verificationFailed(
                "The installer write plan no longer matches the selected folder or payload."
            )
        }
        if plan.state == .alreadyPresent {
            let existing = try regularExistingFile(at: plan.destination)
            guard existing.count == plan.byteCount,
                  sha256(existing) == plan.installerSHA256 else {
                throw YokoiHardwareError.verificationFailed(
                    "The existing installer changed after SwanSong checked it."
                )
            }
            return YokoiInstallerMediaResult(
                destination: plan.destination,
                byteCount: plan.byteCount,
                sha256: plan.installerSHA256,
                wasAlreadyPresent: true
            )
        }
        guard !fileManager.fileExists(atPath: plan.destination.path) else {
            throw YokoiHardwareError.destinationExists(plan.destination)
        }
        let temporary = plan.selectedFolder.appendingPathComponent(
            ".yokoi-installer-\(UUID().uuidString).partial"
        )
        do {
            try payload.installerROM.write(to: temporary, options: [.atomic])
            let readback = try Data(contentsOf: temporary, options: [.mappedIfSafe])
            guard readback.count == plan.byteCount,
                  sha256(readback) == plan.installerSHA256 else {
                throw YokoiHardwareError.verificationFailed(
                    "The installer did not verify after being written to the SD card."
                )
            }
            guard !fileManager.fileExists(atPath: plan.destination.path) else {
                throw YokoiHardwareError.destinationExists(plan.destination)
            }
            try fileManager.moveItem(at: temporary, to: plan.destination)
            return YokoiInstallerMediaResult(
                destination: plan.destination,
                byteCount: plan.byteCount,
                sha256: plan.installerSHA256,
                wasAlreadyPresent: false
            )
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func regularExistingFile(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw YokoiHardwareError.verificationFailed(
                "SwanSong will not read or replace a linked or non-file installer path."
            )
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }
}
