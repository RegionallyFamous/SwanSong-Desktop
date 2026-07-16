import CryptoKit
import Darwin
import Foundation

public struct PocketCoreReleaseMetadata: Equatable, Sendable {
    public static let coreID = "RegionallyFamous.SwanSong"
    public static let repositoryURL = "https://github.com/RegionallyFamous/swansong-core"
    public static let manifestMagic = "SWAN_SONG_STABLE_RELEASE_V1"

    public let version: String
    public let releaseDate: String
    public let sourceCommit: String
    public let packageFilename: String
    public let packageByteCount: Int
    public let packageSHA256: String

    public init(
        version: String,
        releaseDate: String,
        sourceCommit: String,
        packageFilename: String,
        packageByteCount: Int,
        packageSHA256: String
    ) {
        self.version = version
        self.releaseDate = releaseDate
        self.sourceCommit = sourceCommit
        self.packageFilename = packageFilename
        self.packageByteCount = packageByteCount
        self.packageSHA256 = packageSHA256
    }
}

public enum PocketCoreInstallerError: LocalizedError, Equatable, Sendable {
    case invalidRelease(String)
    case invalidPackage(String)
    case invalidDestination(String)
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRelease(detail):
            "The SwanSong Core release could not be verified. \(detail)"
        case let .invalidPackage(detail):
            "The SwanSong Core package is not safe to install. \(detail)"
        case let .invalidDestination(detail):
            "That location cannot be prepared as a Pocket SD card. \(detail)"
        case let .installationFailed(detail):
            "SwanSong could not finish preparing the Pocket SD card. \(detail)"
        }
    }
}

public enum PocketVolumeInspection {
    private static let supportedFileSystemTypes: Set<String> = ["exfat", "msdos"]

    public static func supportsPocketCardFileSystem(_ fileSystemType: String) -> Bool {
        supportedFileSystemTypes.contains(fileSystemType.lowercased())
    }

    public static func fileSystemType(at url: URL) throws -> String {
        let information = try fileSystemInformation(at: url)
        var mutableInformation = information
        return withUnsafePointer(to: &mutableInformation.f_fstypename) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(MFSNAMELEN)
            ) {
                String(cString: $0).lowercased()
            }
        }
    }

    public static func availableByteCount(at url: URL) throws -> Int64 {
        let information = try fileSystemInformation(at: url)
        let blocks = UInt64(information.f_bavail)
        let blockSize = UInt64(information.f_bsize)
        let (bytes, overflowed) = blocks.multipliedReportingOverflow(by: blockSize)
        if overflowed || bytes > UInt64(Int64.max) {
            return Int64.max
        }
        return Int64(bytes)
    }

    public static func mountIdentity(at url: URL) throws -> String {
        let information = try fileSystemInformation(at: url)
        let first = UInt32(bitPattern: information.f_fsid.val.0)
        let second = UInt32(bitPattern: information.f_fsid.val.1)
        return "fsid:\(first):\(second)"
    }

    private static func fileSystemInformation(at url: URL) throws -> statfs {
        var information = statfs()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return statfs(path, &information)
        }
        guard result == 0 else {
            throw PocketCoreInstallerError.invalidDestination(
                "The selected volume's filesystem could not be inspected."
            )
        }
        return information
    }
}

public enum PocketCoreReleaseVerifier {
    private static let maximumManifestBytes = 2 * 1_024 * 1_024
    private static let maximumChecksumsBytes = 64 * 1_024
    private static let maximumPackageBytes = 32 * 1_024 * 1_024

    public static func verify(
        manifestData: Data,
        checksumsData: Data,
        githubTag: String
    ) throws -> PocketCoreReleaseMetadata {
        guard !manifestData.isEmpty, manifestData.count <= maximumManifestBytes else {
            throw PocketCoreInstallerError.invalidRelease(
                "release-manifest.json is empty or too large."
            )
        }
        guard !checksumsData.isEmpty, checksumsData.count <= maximumChecksumsBytes else {
            throw PocketCoreInstallerError.invalidRelease(
                "SHA256SUMS is empty or too large."
            )
        }

        let root = try jsonObject(manifestData, description: "release-manifest.json")
        guard root.count == 1,
              let manifest = root["release_manifest"] as? [String: Any] else {
            throw PocketCoreInstallerError.invalidRelease(
                "release-manifest.json has the wrong top-level schema."
            )
        }
        guard manifest["magic"] as? String == PocketCoreReleaseMetadata.manifestMagic,
              manifest["core_id"] as? String == PocketCoreReleaseMetadata.coreID,
              manifest["repository_url"] as? String == PocketCoreReleaseMetadata.repositoryURL else {
            throw PocketCoreInstallerError.invalidRelease(
                "the manifest does not identify the official Regionally Famous SwanSong Core."
            )
        }

        let version = try requiredText(manifest["version"], name: "version", maximum: 64)
        let releaseDate = try requiredText(
            manifest["date_release"],
            name: "release date",
            maximum: 10
        )
        guard releaseDate.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil else {
            throw PocketCoreInstallerError.invalidRelease(
                "the release date is malformed."
            )
        }
        let normalizedTag = githubTag.hasPrefix("v")
            ? String(githubTag.dropFirst())
            : githubTag
        guard normalizedTag == version else {
            throw PocketCoreInstallerError.invalidRelease(
                "the GitHub tag does not match manifest version \(version)."
            )
        }
        let sourceCommit = try requiredText(
            manifest["source_commit"],
            name: "source commit",
            maximum: 40
        )
        guard sourceCommit.wholeMatch(of: /[0-9a-f]{40}/) != nil else {
            throw PocketCoreInstallerError.invalidRelease(
                "the source commit is malformed."
            )
        }

        guard let policy = manifest["release_policy"] as? [String: Any],
              policy["magic"] as? String == "SWAN_SONG_RELEASE_POLICY_V2",
              policy["core_id"] as? String == PocketCoreReleaseMetadata.coreID,
              policy["repository_url"] as? String == PocketCoreReleaseMetadata.repositoryURL,
              policy["identity_authorized"] as? Bool == true,
              policy["distribution_and_licensing_authorized"] as? Bool == true else {
            throw PocketCoreInstallerError.invalidRelease(
                "the embedded release policy does not authorize this distribution."
            )
        }

        let requiredVerification = [
            "both_quartus_audits_pass",
            "distinct_signed_quartus_runs",
            "rbf_and_build_id_reproduced",
            "hardware_qa_accepted",
            "known_title_compatibility_accepted",
            "release_evidence_v2_validated",
            "release_package_validated",
            "release_stage_applied_and_reverified",
            "corresponding_source_archived",
        ]
        guard let verification = manifest["verification"] as? [String: Any],
              Set(verification.keys) == Set(requiredVerification),
              requiredVerification.allSatisfy({ verification[$0] as? Bool == true }) else {
            throw PocketCoreInstallerError.invalidRelease(
                "the manifest does not record every required release verification."
            )
        }

        guard let artifacts = manifest["artifacts"] as? [String: Any] else {
            throw PocketCoreInstallerError.invalidRelease(
                "the manifest has no release artifact inventory."
            )
        }
        let packageCandidates = artifacts.compactMap { name, value -> (String, [String: Any])? in
            guard name.hasSuffix(".zip"), let identity = value as? [String: Any] else {
                return nil
            }
            return (name, identity)
        }
        guard packageCandidates.count == 1,
              let candidate = packageCandidates.first else {
            throw PocketCoreInstallerError.invalidRelease(
                "the artifact inventory must contain exactly one installable ZIP."
            )
        }
        let expectedFilename = "\(PocketCoreReleaseMetadata.coreID)_\(version)_\(releaseDate).zip"
        guard candidate.0 == expectedFilename,
              candidate.1["filename"] as? String == expectedFilename else {
            throw PocketCoreInstallerError.invalidRelease(
                "the package filename does not match the verified release identity."
            )
        }
        guard let byteCount = candidate.1["size"] as? Int,
              byteCount > 0,
              byteCount <= maximumPackageBytes else {
            throw PocketCoreInstallerError.invalidRelease(
                "the package size is missing or outside the accepted limit."
            )
        }
        let packageDigest = try sha256(
            candidate.1["sha256"],
            description: "package SHA-256"
        )

        let checksums = try parseChecksums(checksumsData)
        guard checksums[expectedFilename] == packageDigest else {
            throw PocketCoreInstallerError.invalidRelease(
                "SHA256SUMS does not agree with the manifest package checksum."
            )
        }
        let manifestDigest = digest(manifestData)
        guard checksums["release-manifest.json"] == manifestDigest else {
            throw PocketCoreInstallerError.invalidRelease(
                "SHA256SUMS does not match release-manifest.json."
            )
        }

        return PocketCoreReleaseMetadata(
            version: version,
            releaseDate: releaseDate,
            sourceCommit: sourceCommit,
            packageFilename: expectedFilename,
            packageByteCount: byteCount,
            packageSHA256: packageDigest
        )
    }

    public static func verifyPackage(
        at url: URL,
        release: PocketCoreReleaseMetadata
    ) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw PocketCoreInstallerError.invalidPackage(
                "the downloaded ZIP could not be inspected."
            )
        }
        guard values.isRegularFile == true,
              values.fileSize == release.packageByteCount else {
            throw PocketCoreInstallerError.invalidPackage(
                "the downloaded ZIP size does not match the release manifest."
            )
        }
        guard digest(try Data(contentsOf: url, options: [.mappedIfSafe]))
            == release.packageSHA256 else {
            throw PocketCoreInstallerError.invalidPackage(
                "the downloaded ZIP checksum does not match the published release."
            )
        }
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func jsonObject(
        _ data: Data,
        description: String
    ) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw PocketCoreInstallerError.invalidRelease(
                    "\(description) is not a JSON object."
                )
            }
            return object
        } catch let error as PocketCoreInstallerError {
            throw error
        } catch {
            throw PocketCoreInstallerError.invalidRelease(
                "\(description) is not valid JSON."
            )
        }
    }

    private static func requiredText(
        _ value: Any?,
        name: String,
        maximum: Int
    ) throws -> String {
        guard let value = value as? String,
              !value.isEmpty,
              value.count <= maximum,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw PocketCoreInstallerError.invalidRelease(
                "the manifest \(name) is missing or malformed."
            )
        }
        return value
    }

    private static func sha256(_ value: Any?, description: String) throws -> String {
        guard let value = value as? String,
              value.wholeMatch(of: /[0-9a-f]{64}/) != nil else {
            throw PocketCoreInstallerError.invalidRelease(
                "the \(description) is malformed."
            )
        }
        return value
    }

    private static func parseChecksums(_ data: Data) throws -> [String: String] {
        guard let text = String(data: data, encoding: .ascii) else {
            throw PocketCoreInstallerError.invalidRelease(
                "SHA256SUMS is not ASCII text."
            )
        }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard !line.isEmpty else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: false)
            guard fields.count == 3,
                  fields[1].isEmpty,
                  fields[0].wholeMatch(of: /[0-9a-f]{64}/) != nil else {
                throw PocketCoreInstallerError.invalidRelease(
                    "SHA256SUMS contains a malformed line."
                )
            }
            let filename = String(fields[2])
            guard isLeafFilename(filename), result[filename] == nil else {
                throw PocketCoreInstallerError.invalidRelease(
                    "SHA256SUMS contains an unsafe or duplicate filename."
                )
            }
            result[filename] = String(fields[0])
        }
        guard !result.isEmpty else {
            throw PocketCoreInstallerError.invalidRelease("SHA256SUMS is empty.")
        }
        return result
    }

    private static func isLeafFilename(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
    }
}

public struct PocketCoreManagedFile: Equatable, Sendable {
    public let relativePath: String
    public let data: Data
}

public struct PocketCorePackage: Equatable, Sendable {
    private static let maximumEntries = 128
    private static let maximumFileBytes = 8 * 1_024 * 1_024
    private static let maximumExpandedBytes = 16 * 1_024 * 1_024
    private static let coreDirectory = "Cores/RegionallyFamous.SwanSong"

    public let release: PocketCoreReleaseMetadata
    public let files: [PocketCoreManagedFile]
    public let directories: [String]

    public init(
        extractedDirectoryURL: URL,
        release: PocketCoreReleaseMetadata,
        fileManager: FileManager = .default
    ) throws {
        let rootValues = try? extractedDirectoryURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues?.isDirectory == true,
              rootValues?.isSymbolicLink != true else {
            throw PocketCoreInstallerError.invalidPackage(
                "the extracted package root is not an ordinary directory."
            )
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: extractedDirectoryURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw PocketCoreInstallerError.invalidPackage(
                "the extracted package could not be enumerated."
            )
        }

        var observedFiles: [PocketCoreManagedFile] = []
        var observedDirectories: [String] = []
        var foldedPaths: Set<String> = []
        var entryCount = 0
        var expandedBytes = 0
        for case let url as URL in enumerator {
            entryCount += 1
            guard entryCount <= Self.maximumEntries else {
                throw PocketCoreInstallerError.invalidPackage(
                    "the package contains more than \(Self.maximumEntries) entries."
                )
            }
            let relative = try Self.relativePath(for: url, root: extractedDirectoryURL)
            let folded = relative.lowercased()
            guard foldedPaths.insert(folded).inserted else {
                throw PocketCoreInstallerError.invalidPackage(
                    "the package contains duplicate or case-colliding paths."
                )
            }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else {
                throw PocketCoreInstallerError.invalidPackage(
                    "the package contains a symbolic link at \(relative)."
                )
            }
            try Self.validateScope(relative, isDirectory: values.isDirectory == true)
            if values.isDirectory == true {
                observedDirectories.append(relative)
                continue
            }
            guard values.isRegularFile == true,
                  let size = values.fileSize,
                  size >= 0,
                  size <= Self.maximumFileBytes else {
                throw PocketCoreInstallerError.invalidPackage(
                    "\(relative) is not an ordinary file within the accepted size limit."
                )
            }
            expandedBytes += size
            guard expandedBytes <= Self.maximumExpandedBytes else {
                throw PocketCoreInstallerError.invalidPackage(
                    "the package expands beyond \(Self.maximumExpandedBytes) bytes."
                )
            }
            observedFiles.append(
                PocketCoreManagedFile(
                    relativePath: relative,
                    data: try Data(contentsOf: url, options: [.mappedIfSafe])
                )
            )
        }
        if let enumerationError {
            throw PocketCoreInstallerError.invalidPackage(
                "the extracted package could not be read completely: \(enumerationError.localizedDescription)"
            )
        }

        let fileMap = Dictionary(
            uniqueKeysWithValues: observedFiles.map { ($0.relativePath, $0.data) }
        )
        let requiredDirectories: Set<String> = [
            "Assets",
            "Assets/wonderswan",
            "Assets/wonderswan/common",
            "Cores",
            Self.coreDirectory,
            "Platforms",
            "Platforms/_images",
        ]
        guard requiredDirectories.isSubset(of: observedDirectories) else {
            throw PocketCoreInstallerError.invalidPackage(
                "one or more required Pocket package folders are missing."
            )
        }
        try Self.validateRequiredPayload(fileMap, release: release)
        self.release = release
        files = observedFiles.sorted { $0.relativePath < $1.relativePath }
        directories = observedDirectories.sorted {
            let leftDepth = $0.split(separator: "/").count
            let rightDepth = $1.split(separator: "/").count
            return leftDepth == rightDepth ? $0 < $1 : leftDepth < rightDepth
        }
    }

    private static func relativePath(for url: URL, root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            throw PocketCoreInstallerError.invalidPackage(
                "an extracted entry escaped the package directory."
            )
        }
        let relative = String(path.dropFirst(rootPath.count + 1))
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty,
              relative.utf8.count <= 1_024,
              !relative.contains("\\"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !parts.contains(where: { $0.utf8.count > 255 }),
              !relative.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw PocketCoreInstallerError.invalidPackage(
                "the package contains an unsafe path."
            )
        }
        return relative
    }

    private static func validateScope(_ relative: String, isDirectory: Bool) throws {
        if relative == "Assets"
            || relative == "Assets/wonderswan"
            || relative == "Assets/wonderswan/common"
            || relative == "Cores"
            || relative == coreDirectory
            || relative == "Platforms"
            || relative == "Platforms/_images" {
            guard isDirectory else {
                throw PocketCoreInstallerError.invalidPackage(
                    "\(relative) must be a directory."
                )
            }
            return
        }
        if relative == "Assets/wonderswan/common/.gitkeep" {
            guard !isDirectory else {
                throw PocketCoreInstallerError.invalidPackage(
                    "the package contains an unexpected asset directory."
                )
            }
            return
        }
        if relative.hasPrefix(coreDirectory + "/") {
            return
        }
        if relative == "Platforms/wonderswan.json"
            || relative == "Platforms/_images/wonderswan.bin" {
            guard !isDirectory else {
                throw PocketCoreInstallerError.invalidPackage(
                    "\(relative) must be a file."
                )
            }
            return
        }
        throw PocketCoreInstallerError.invalidPackage(
            "the package tries to manage unsupported path \(relative)."
        )
    }

    private static func validateRequiredPayload(
        _ files: [String: Data],
        release: PocketCoreReleaseMetadata
    ) throws {
        let requiredCoreFiles = [
            "audio.json",
            "core.json",
            "data.json",
            "input.json",
            "interact.json",
            "variants.json",
            "video.json",
        ].map { "\(coreDirectory)/\($0)" }
        let required = Set(requiredCoreFiles + [
            "Platforms/wonderswan.json",
            "Platforms/_images/wonderswan.bin",
        ])
        guard required.isSubset(of: files.keys) else {
            throw PocketCoreInstallerError.invalidPackage(
                "one or more required Pocket core or platform files are missing."
            )
        }
        guard let coreData = files["\(coreDirectory)/core.json"],
              let root = try? JSONSerialization.jsonObject(with: coreData) as? [String: Any],
              let core = root["core"] as? [String: Any],
              core["magic"] as? String == "APF_VER_1",
              let metadata = core["metadata"] as? [String: Any],
              metadata["author"] as? String == "RegionallyFamous",
              metadata["shortname"] as? String == "SwanSong",
              metadata["url"] as? String == PocketCoreReleaseMetadata.repositoryURL,
              metadata["version"] as? String == release.version,
              metadata["date_release"] as? String == release.releaseDate,
              let framework = core["framework"] as? [String: Any],
              framework["target_product"] as? String == "Analogue Pocket",
              let chip32 = framework["chip32_vm"] as? String,
              isLeafFilename(chip32),
              let cores = core["cores"] as? [[String: Any]],
              cores.count == 1,
              let bitstream = cores.first?["filename"] as? String,
              isLeafFilename(bitstream),
              files["\(coreDirectory)/\(chip32)"]?.isEmpty == false,
              files["\(coreDirectory)/\(bitstream)"]?.isEmpty == false else {
            throw PocketCoreInstallerError.invalidPackage(
                "core.json or its runtime payload does not match the verified release."
            )
        }
    }

    private static func isLeafFilename(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }
}

public struct PocketCoreInstallPlan: Equatable, Sendable {
    public let destinationURL: URL
    public let release: PocketCoreReleaseMetadata
    public let newFiles: [String]
    public let replacedFiles: [String]
    public let unchangedFiles: [String]

    public var changedFileCount: Int { newFiles.count + replacedFiles.count }
}

public struct PocketCoreInstallResult: Equatable, Sendable {
    public let destinationURL: URL
    public let version: String
    public let installedFileCount: Int
    public let unchangedFileCount: Int
}

public struct PocketCoreCardPreparer: Sendable {
    private static let minimumFreeSpaceReserve: Int64 = 1_024 * 1_024

    private let availableCapacity: @Sendable (URL) throws -> Int64
    private let beforePostWriteVerification: (@Sendable (URL) throws -> Void)?

    public init() {
        availableCapacity = { try PocketVolumeInspection.availableByteCount(at: $0) }
        beforePostWriteVerification = nil
    }

    init(
        availableCapacity: @escaping @Sendable (URL) throws -> Int64,
        beforePostWriteVerification: (@Sendable (URL) throws -> Void)? = nil
    ) {
        self.availableCapacity = availableCapacity
        self.beforePostWriteVerification = beforePostWriteVerification
    }

    public func plan(
        package: PocketCorePackage,
        destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> PocketCoreInstallPlan {
        try validateDestinationRoot(destinationURL)
        var newFiles: [String] = []
        var replacedFiles: [String] = []
        var unchangedFiles: [String] = []
        for managed in package.files {
            let destination = destinationURL.appendingPathComponent(managed.relativePath)
            try validateExistingComponents(
                root: destinationURL,
                relativePath: managed.relativePath,
                finalMustBeFile: true,
                fileManager: fileManager
            )
            if fileManager.fileExists(atPath: destination.path) {
                let existing = try boundedFileData(destination)
                if existing == managed.data {
                    unchangedFiles.append(managed.relativePath)
                } else {
                    replacedFiles.append(managed.relativePath)
                }
            } else {
                newFiles.append(managed.relativePath)
            }
        }
        return PocketCoreInstallPlan(
            destinationURL: destinationURL,
            release: package.release,
            newFiles: newFiles.sorted(),
            replacedFiles: replacedFiles.sorted(),
            unchangedFiles: unchangedFiles.sorted()
        )
    }

    public func apply(
        package: PocketCorePackage,
        destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> PocketCoreInstallResult {
        let plan = try plan(
            package: package,
            destinationURL: destinationURL,
            fileManager: fileManager
        )
        if plan.changedFileCount == 0 {
            return PocketCoreInstallResult(
                destinationURL: destinationURL,
                version: package.release.version,
                installedFileCount: 0,
                unchangedFileCount: plan.unchangedFiles.count
            )
        }

        let changed = Set(plan.newFiles + plan.replacedFiles)
        let changedByteCount = package.files
            .filter { changed.contains($0.relativePath) }
            .reduce(Int64(0)) { total, file in
                total + Int64(file.data.count)
            }
        let requiredByteCount = changedByteCount + Self.minimumFreeSpaceReserve
        let availableByteCount = try availableCapacity(destinationURL)
        guard availableByteCount >= requiredByteCount else {
            throw PocketCoreInstallerError.invalidDestination(
                "At least \(ByteCountFormatter.string(fromByteCount: requiredByteCount, countStyle: .file)) free is required to install and safely roll back this Core; the volume reports \(ByteCountFormatter.string(fromByteCount: availableByteCount, countStyle: .file)) free."
            )
        }

        let transaction = UUID().uuidString.lowercased()
        let backupRoot = destinationURL.appendingPathComponent(
            ".swansong-core-install-\(transaction)",
            isDirectory: true
        )
        var createdDirectories: [URL] = []
        var published: [(destination: URL, backup: URL?)] = []
        var temporaryFiles: [URL] = []
        do {
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: false)
            for directory in package.directories {
                let destination = destinationURL.appendingPathComponent(directory, isDirectory: true)
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
                    createdDirectories.append(destination)
                }
            }

            for managed in package.files where changed.contains(managed.relativePath) {
                let destination = destinationURL.appendingPathComponent(managed.relativePath)
                let temporary = destination
                    .deletingLastPathComponent()
                    .appendingPathComponent(".\(destination.lastPathComponent).\(transaction).tmp")
                do {
                    try managed.data.write(to: temporary, options: [.withoutOverwriting])
                    temporaryFiles.append(temporary)
                } catch {
                    try? fileManager.removeItem(at: temporary)
                    throw error
                }

                var backup: URL?
                if fileManager.fileExists(atPath: destination.path) {
                    let backupURL = backupRoot.appendingPathComponent(managed.relativePath)
                    try fileManager.createDirectory(
                        at: backupURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: destination, to: backupURL)
                    backup = backupURL
                }
                published.append((destination, backup))
                do {
                    try fileManager.moveItem(at: temporary, to: destination)
                    _ = temporaryFiles.popLast()
                } catch {
                    try? fileManager.removeItem(at: temporary)
                    throw error
                }
            }
            try beforePostWriteVerification?(destinationURL)
            for managed in package.files {
                try validateExistingComponents(
                    root: destinationURL,
                    relativePath: managed.relativePath,
                    finalMustBeFile: true,
                    fileManager: fileManager
                )
                let destination = destinationURL.appendingPathComponent(
                    managed.relativePath
                )
                guard try boundedFileData(destination) == managed.data else {
                    throw PocketCoreTransactionFailure(
                        detail: "Post-write verification failed for \(managed.relativePath)."
                    )
                }
            }
            try fileManager.removeItem(at: backupRoot)
        } catch {
            var rollbackIssues: [String] = []
            for temporary in temporaryFiles {
                try? fileManager.removeItem(at: temporary)
            }
            for item in published.reversed() {
                if fileManager.fileExists(atPath: item.destination.path) {
                    do {
                        try fileManager.removeItem(at: item.destination)
                    } catch {
                        rollbackIssues.append(
                            "could not remove \(item.destination.path)"
                        )
                    }
                }
                if let backup = item.backup {
                    do {
                        try fileManager.createDirectory(
                            at: item.destination.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try fileManager.moveItem(at: backup, to: item.destination)
                    } catch {
                        rollbackIssues.append(
                            "could not restore \(item.destination.path)"
                        )
                    }
                }
            }
            if rollbackIssues.isEmpty {
                try? fileManager.removeItem(at: backupRoot)
            }
            for directory in createdDirectories.reversed() {
                try? fileManager.removeItem(at: directory)
            }
            let rollbackDetail = rollbackIssues.isEmpty
                ? "The previous managed files were restored."
                : "Rollback needs attention (\(rollbackIssues.joined(separator: "; "))). Keep the recovery folder at \(backupRoot.path)."
            throw PocketCoreInstallerError.installationFailed(
                "\(error.localizedDescription) \(rollbackDetail)"
            )
        }

        return PocketCoreInstallResult(
            destinationURL: destinationURL,
            version: package.release.version,
            installedFileCount: plan.changedFileCount,
            unchangedFileCount: plan.unchangedFiles.count
        )
    }

    private func validateDestinationRoot(_ url: URL) throws {
        let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isWritableKey]
        )
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true,
              values?.isWritable == true else {
            throw PocketCoreInstallerError.invalidDestination(
                "Choose a writable mounted volume or folder, not a file or symbolic link."
            )
        }
    }

    private func validateExistingComponents(
        root: URL,
        relativePath: String,
        finalMustBeFile: Bool,
        fileManager: FileManager
    ) throws {
        let parts = relativePath.split(separator: "/").map(String.init)
        var current = root
        for (index, part) in parts.enumerated() {
            current.appendPathComponent(part)
            var metadata = stat()
            if lstat(current.path, &metadata) != 0 {
                if errno == ENOENT { continue }
                throw PocketCoreInstallerError.invalidDestination(
                    "\(current.path) could not be inspected safely."
                )
            }
            let kind = metadata.st_mode & S_IFMT
            guard kind != S_IFLNK else {
                throw PocketCoreInstallerError.invalidDestination(
                    "\(current.path) is a symbolic link."
                )
            }
            let isLast = index == parts.count - 1
            if isLast, finalMustBeFile {
                guard kind == S_IFREG else {
                    throw PocketCoreInstallerError.invalidDestination(
                        "\(current.path) is not an ordinary file."
                    )
                }
            } else if kind != S_IFDIR {
                throw PocketCoreInstallerError.invalidDestination(
                    "\(current.path) blocks a required Pocket folder."
                )
            }
        }
    }

    private func boundedFileData(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size <= 32 * 1_024 * 1_024 else {
            throw PocketCoreInstallerError.invalidDestination(
                "\(url.path) is not an ordinary managed file within the accepted size limit."
            )
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

private struct PocketCoreTransactionFailure: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}
