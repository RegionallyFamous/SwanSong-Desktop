import Foundation

public struct HomebrewCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let catalogID: String
    public let revision: Int
    public let generatedAt: Date
    public let repositoryURL: URL
    public let entries: [HomebrewCatalogEntry]

    public init(
        schemaVersion: Int = 1,
        catalogID: String,
        revision: Int,
        generatedAt: Date,
        repositoryURL: URL,
        entries: [HomebrewCatalogEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.catalogID = catalogID
        self.revision = revision
        self.generatedAt = generatedAt
        self.repositoryURL = repositoryURL
        self.entries = entries
    }
}

public struct HomebrewCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let developer: String
    public let summary: String
    public let description: String
    public let sourceURL: URL
    public let provenanceURL: URL
    public let licenseName: String
    public let licenseURL: URL
    public let screenshotURL: URL?
    public let releases: [HomebrewCatalogRelease]

    public init(
        id: String,
        title: String,
        developer: String,
        summary: String,
        description: String,
        sourceURL: URL,
        provenanceURL: URL,
        licenseName: String,
        licenseURL: URL,
        screenshotURL: URL? = nil,
        releases: [HomebrewCatalogRelease]
    ) {
        self.id = id
        self.title = title
        self.developer = developer
        self.summary = summary
        self.description = description
        self.sourceURL = sourceURL
        self.provenanceURL = provenanceURL
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.screenshotURL = screenshotURL
        self.releases = releases
    }
}

public struct HomebrewCatalogRelease: Codable, Equatable, Sendable {
    public let version: String
    public let saveCompatibilityID: String
    public let releasedAt: Date?
    public let releaseURL: URL
    public let asset: HomebrewCatalogAsset

    public init(
        version: String,
        saveCompatibilityID: String,
        releasedAt: Date? = nil,
        releaseURL: URL,
        asset: HomebrewCatalogAsset
    ) {
        self.version = version
        self.saveCompatibilityID = saveCompatibilityID
        self.releasedAt = releasedAt
        self.releaseURL = releaseURL
        self.asset = asset
    }
}

public struct HomebrewCatalogAsset: Codable, Equatable, Sendable {
    public let url: URL
    public let byteCount: Int
    public let sha256: String
    public let fileExtension: String
    public let hardwareModel: EngineHardwareModel

    public init(
        url: URL,
        byteCount: Int,
        sha256: String,
        fileExtension: String,
        hardwareModel: EngineHardwareModel
    ) {
        self.url = url
        self.byteCount = byteCount
        self.sha256 = sha256
        self.fileExtension = fileExtension
        self.hardwareModel = hardwareModel
    }
}

/// Stable supply-chain identity retained by the library independently of the
/// catalog cache. A release can replace its managed ROM without changing the
/// game's UUID or user-owned library metadata.
public struct HomebrewCatalogOrigin: Codable, Equatable, Hashable, Sendable {
    public let catalogID: String
    public let entryID: String
    public let version: String
    /// Publication time of the installed catalog release. Older library
    /// documents omit this field; `nil` keeps those documents readable while
    /// newly installed releases retain enough ordering state to reject a
    /// later catalog rollback.
    public let releasedAt: Date?
    public let saveCompatibilityID: String
    public let assetSHA256: String

    public init(
        catalogID: String,
        entryID: String,
        version: String,
        releasedAt: Date? = nil,
        saveCompatibilityID: String,
        assetSHA256: String
    ) {
        self.catalogID = catalogID
        self.entryID = entryID
        self.version = version
        self.releasedAt = releasedAt
        self.saveCompatibilityID = saveCompatibilityID
        self.assetSHA256 = assetSHA256
    }
}

public enum HomebrewCatalogError: LocalizedError, Equatable, Sendable {
    case catalogTooLarge
    case invalidJSONSchema(String)
    case unsupportedSchemaVersion(Int)
    case invalidCatalogID(String)
    case invalidRevision(Int)
    case invalidGeneratedAt
    case invalidRepositoryURL(URL)
    case invalidCatalogSourceURL(URL)
    case tooManyEntries
    case duplicateEntryID(String)
    case invalidEntryID(String)
    case invalidEntryText(String)
    case invalidSourceURL(URL)
    case invalidProvenanceURL(URL)
    case invalidLicenseURL(URL)
    case invalidScreenshotURL(URL)
    case missingReleases(String)
    case tooManyReleases(String)
    case duplicateReleaseVersion(String)
    case duplicateReleaseDate
    case invalidVersion(String)
    case invalidSaveCompatibilityID(String)
    case invalidReleasedAt
    case invalidReleaseURL(URL)
    case invalidAssetURL(URL)
    case releaseAssetTagMismatch
    case invalidAssetByteCount(Int)
    case invalidAssetSHA256(String)
    case duplicateAssetSHA256(String)
    case invalidAssetFileExtension(String)
    case invalidAssetHardwareModel(EngineHardwareModel)
    case assetFileExtensionMismatch
    case releaseDoesNotBelongToEntry
    case invalidExistingOrigin
    case conflictingLibraryIdentity
    case mutableReleaseVersion(String)
    case releaseDowngrade(installed: String, requested: String)
    case changedSaveCompatibility(existing: String, requested: String)
    case changedPersistenceContract
    case pocketChallengeUpdateRequiresMigration
    case assetByteCountMismatch(expected: Int, actual: Int)
    case assetSHA256Mismatch
    case invalidAssetContents

    public var errorDescription: String? {
        switch self {
        case .catalogTooLarge:
            "The homebrew catalog is larger than SwanSong accepts."
        case let .invalidJSONSchema(location):
            "The homebrew catalog has an invalid v1 schema at \(location)."
        case let .unsupportedSchemaVersion(version):
            "Homebrew catalog schema \(version) is not supported."
        case let .invalidCatalogID(id):
            "The homebrew catalog identity is invalid: \(id)."
        case let .invalidRevision(revision):
            "The homebrew catalog revision is invalid: \(revision)."
        case .invalidGeneratedAt:
            "The homebrew catalog generation date is invalid."
        case .invalidRepositoryURL:
            "The homebrew catalog repository is not the first-party SwanSong Story Forge repository."
        case .invalidCatalogSourceURL:
            "The homebrew catalog did not come from the first-party SwanSong Story Forge repository."
        case .tooManyEntries:
            "The homebrew catalog contains too many entries."
        case let .duplicateEntryID(id):
            "The homebrew catalog repeats entry \(id)."
        case let .invalidEntryID(id):
            "The homebrew catalog entry identity is invalid: \(id)."
        case let .invalidEntryText(field):
            "The homebrew catalog has invalid \(field) text."
        case .invalidSourceURL:
            "A homebrew source link is outside the first-party SwanSong Story Forge repository."
        case .invalidProvenanceURL:
            "A homebrew provenance link is outside the first-party SwanSong Story Forge repository."
        case .invalidLicenseURL:
            "A homebrew license link is outside the first-party SwanSong Story Forge repository."
        case .invalidScreenshotURL:
            "A homebrew screenshot link is not an immutable first-party image."
        case let .missingReleases(id):
            "Homebrew entry \(id) has no releases."
        case let .tooManyReleases(id):
            "Homebrew entry \(id) has too many releases."
        case let .duplicateReleaseVersion(version):
            "The homebrew catalog repeats release \(version)."
        case .duplicateReleaseDate:
            "Homebrew releases for one title must have distinct publication dates."
        case let .invalidVersion(version):
            "The homebrew release version is invalid: \(version)."
        case let .invalidSaveCompatibilityID(id):
            "The homebrew save-compatibility identity is invalid: \(id)."
        case .invalidReleasedAt:
            "The homebrew release date is invalid."
        case .invalidReleaseURL:
            "A homebrew release link is outside the first-party SwanSong Story Forge releases."
        case .invalidAssetURL:
            "A homebrew download is outside the first-party SwanSong Story Forge releases."
        case .releaseAssetTagMismatch:
            "The homebrew release and its download use different release tags."
        case let .invalidAssetByteCount(count):
            "The homebrew download has an invalid byte count: \(count)."
        case let .invalidAssetSHA256(digest):
            "The homebrew download has an invalid SHA-256 digest: \(digest)."
        case let .duplicateAssetSHA256(digest):
            "The homebrew catalog repeats download digest \(digest)."
        case let .invalidAssetFileExtension(fileExtension):
            "The homebrew download has an invalid file extension: \(fileExtension)."
        case let .invalidAssetHardwareModel(model):
            "The homebrew download has an invalid hardware model: \(model.rawValue)."
        case .assetFileExtensionMismatch:
            "The homebrew download filename, extension, and hardware model do not agree."
        case .releaseDoesNotBelongToEntry:
            "The selected homebrew release does not belong to that catalog entry."
        case .invalidExistingOrigin:
            "The existing homebrew library identity is invalid."
        case .conflictingLibraryIdentity:
            "More than one library game claims this homebrew identity."
        case let .mutableReleaseVersion(version):
            "Homebrew release \(version) changed bytes without changing its version."
        case let .releaseDowngrade(installed, requested):
            "SwanSong could not prove that homebrew release \(requested) is newer than installed release \(installed), so it refused to replace it."
        case let .changedSaveCompatibility(existing, requested):
            "This update changes save compatibility from \(existing) to \(requested), so it cannot replace the installed game in place."
        case .changedPersistenceContract:
            "This update changes the game hardware or cartridge-save contract, so it cannot replace the installed game in place."
        case .pocketChallengeUpdateRequiresMigration:
            "Pocket Challenge V2 updates cannot replace an installed game until program-flash saves can be migrated safely."
        case let .assetByteCountMismatch(expected, actual):
            "The downloaded homebrew uses \(actual) bytes instead of the published \(expected) bytes."
        case .assetSHA256Mismatch:
            "The downloaded homebrew does not match its published SHA-256 digest."
        case .invalidAssetContents:
            "The downloaded homebrew is not the declared WonderSwan game image."
        }
    }
}

public enum HomebrewCatalogValidator {
    public static let firstPartyCatalogID = "regionally-famous.swansong-story-forge"
    public static let firstPartyRepositoryURL = URL(
        string: "https://github.com/RegionallyFamous/swansong-story-forge"
    )!
    public static let maximumCatalogByteCount = 1 * 1_024 * 1_024
    public static let maximumEntryCount = 256
    public static let maximumReleasesPerEntry = 64

    private static let earliestDate = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
    private static let maximumFutureInterval: TimeInterval = 24 * 60 * 60

    /// Decodes the canonical v1 JSON representation and rejects unknown keys
    /// before validating all supply-chain values.
    public static func decode(
        _ data: Data,
        sourceURL: URL
    ) throws -> HomebrewCatalog {
        guard data.count <= maximumCatalogByteCount else {
            throw HomebrewCatalogError.catalogTooLarge
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HomebrewCatalogError.invalidJSONSchema("document")
        }
        try validateJSONShape(object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog: HomebrewCatalog
        do {
            catalog = try decoder.decode(HomebrewCatalog.self, from: data)
        } catch {
            throw HomebrewCatalogError.invalidJSONSchema("document")
        }
        try validate(catalog, sourceURL: sourceURL)
        return catalog
    }

    public static func validate(
        _ catalog: HomebrewCatalog,
        sourceURL: URL
    ) throws {
        guard catalog.schemaVersion == 1 else {
            throw HomebrewCatalogError.unsupportedSchemaVersion(catalog.schemaVersion)
        }
        guard catalog.catalogID == firstPartyCatalogID else {
            throw HomebrewCatalogError.invalidCatalogID(catalog.catalogID)
        }
        guard catalog.revision >= 1 else {
            throw HomebrewCatalogError.invalidRevision(catalog.revision)
        }
        guard catalog.generatedAt.timeIntervalSince1970.isFinite,
              catalog.generatedAt >= earliestDate,
              catalog.generatedAt <= Date().addingTimeInterval(maximumFutureInterval) else {
            throw HomebrewCatalogError.invalidGeneratedAt
        }
        guard catalog.repositoryURL.absoluteString == firstPartyRepositoryURL.absoluteString else {
            throw HomebrewCatalogError.invalidRepositoryURL(catalog.repositoryURL)
        }
        guard isCatalogSourceURL(sourceURL) else {
            throw HomebrewCatalogError.invalidCatalogSourceURL(sourceURL)
        }
        guard catalog.entries.count <= maximumEntryCount else {
            throw HomebrewCatalogError.tooManyEntries
        }

        var entryIDs = Set<String>()
        var assetDigests = Set<String>()
        for entry in catalog.entries {
            guard entryIDs.insert(entry.id).inserted else {
                throw HomebrewCatalogError.duplicateEntryID(entry.id)
            }
            try validateEntry(entry, generatedAt: catalog.generatedAt)
            for release in entry.releases {
                guard assetDigests.insert(release.asset.sha256).inserted else {
                    throw HomebrewCatalogError.duplicateAssetSHA256(release.asset.sha256)
                }
            }
        }
    }

    static func validateForInstallation(
        entry: HomebrewCatalogEntry,
        release: HomebrewCatalogRelease,
        catalogID: String = firstPartyCatalogID
    ) throws {
        if catalogID == PublishedHomebrewCatalogDecoder.catalogID {
            try PublishedHomebrewCatalogDecoder.validateForInstallation(
                entry: entry,
                release: release
            )
            return
        }
        try validateEntry(entry, generatedAt: Date())
        guard entry.releases.contains(release) else {
            throw HomebrewCatalogError.releaseDoesNotBelongToEntry
        }
    }

    static func originIsValid(_ origin: HomebrewCatalogOrigin) -> Bool {
        [firstPartyCatalogID, PublishedHomebrewCatalogDecoder.catalogID]
            .contains(origin.catalogID)
            && isIdentifier(origin.entryID, maximumUTF8Bytes: 128)
            && isVersion(origin.version)
            && (origin.releasedAt.map {
                $0.timeIntervalSince1970.isFinite && $0 >= earliestDate
            } ?? true)
            && isIdentifier(origin.saveCompatibilityID, maximumUTF8Bytes: 128)
            && isLowercaseSHA256(origin.assetSHA256)
    }

    private static func validateEntry(
        _ entry: HomebrewCatalogEntry,
        generatedAt: Date
    ) throws {
        guard isIdentifier(entry.id, maximumUTF8Bytes: 128) else {
            throw HomebrewCatalogError.invalidEntryID(entry.id)
        }
        try validateText(entry.title, field: "title", maximumUTF8Bytes: 160)
        try validateText(entry.developer, field: "developer", maximumUTF8Bytes: 160)
        try validateText(entry.summary, field: "summary", maximumUTF8Bytes: 512)
        try validateText(entry.description, field: "description", maximumUTF8Bytes: 8 * 1_024)
        try validateText(entry.licenseName, field: "license", maximumUTF8Bytes: 160)
        guard isGameRepositoryURL(entry.sourceURL, entryID: entry.id, kind: "tree") else {
            throw HomebrewCatalogError.invalidSourceURL(entry.sourceURL)
        }
        guard isGameRepositoryURL(entry.provenanceURL, entryID: entry.id, kind: "blob") else {
            throw HomebrewCatalogError.invalidProvenanceURL(entry.provenanceURL)
        }
        guard isRepositoryBlobURL(entry.licenseURL) else {
            throw HomebrewCatalogError.invalidLicenseURL(entry.licenseURL)
        }
        if let screenshotURL = entry.screenshotURL,
           !isScreenshotURL(screenshotURL, sourceURL: entry.sourceURL) {
            throw HomebrewCatalogError.invalidScreenshotURL(screenshotURL)
        }
        guard !entry.releases.isEmpty else {
            throw HomebrewCatalogError.missingReleases(entry.id)
        }
        guard entry.releases.count <= maximumReleasesPerEntry else {
            throw HomebrewCatalogError.tooManyReleases(entry.id)
        }

        var versions = Set<String>()
        var releaseDates = Set<Date>()
        for release in entry.releases {
            guard versions.insert(release.version).inserted else {
                throw HomebrewCatalogError.duplicateReleaseVersion(release.version)
            }
            try validateRelease(release, generatedAt: generatedAt)
            guard let releasedAt = release.releasedAt,
                  releaseDates.insert(releasedAt).inserted else {
                throw HomebrewCatalogError.duplicateReleaseDate
            }
        }
    }

    private static func validateRelease(
        _ release: HomebrewCatalogRelease,
        generatedAt: Date
    ) throws {
        guard isVersion(release.version) else {
            throw HomebrewCatalogError.invalidVersion(release.version)
        }
        guard isIdentifier(release.saveCompatibilityID, maximumUTF8Bytes: 128) else {
            throw HomebrewCatalogError.invalidSaveCompatibilityID(release.saveCompatibilityID)
        }
        guard let releasedAt = release.releasedAt,
              releasedAt.timeIntervalSince1970.isFinite,
              releasedAt >= earliestDate,
              releasedAt <= generatedAt.addingTimeInterval(maximumFutureInterval) else {
            throw HomebrewCatalogError.invalidReleasedAt
        }
        guard let releaseTag = releaseTag(from: release.releaseURL),
              isImmutableReleaseTag(releaseTag) else {
            throw HomebrewCatalogError.invalidReleaseURL(release.releaseURL)
        }
        let asset = release.asset
        guard let assetTag = assetReleaseTag(from: asset.url) else {
            throw HomebrewCatalogError.invalidAssetURL(asset.url)
        }
        guard releaseTag == assetTag else {
            throw HomebrewCatalogError.releaseAssetTagMismatch
        }
        try validateAsset(asset)
    }

    private static func validateAsset(_ asset: HomebrewCatalogAsset) throws {
        guard asset.byteCount >= GameROMValidationPolicy.minimumByteCount,
              asset.byteCount <= GameROMValidationPolicy.maximumByteCount,
              asset.byteCount.isMultiple(of: 64 * 1_024) else {
            throw HomebrewCatalogError.invalidAssetByteCount(asset.byteCount)
        }
        guard isLowercaseSHA256(asset.sha256) else {
            throw HomebrewCatalogError.invalidAssetSHA256(asset.sha256)
        }
        guard ["ws", "wsc", "pc2", "pcv2"].contains(asset.fileExtension) else {
            throw HomebrewCatalogError.invalidAssetFileExtension(asset.fileExtension)
        }
        guard asset.hardwareModel != .automatic else {
            throw HomebrewCatalogError.invalidAssetHardwareModel(asset.hardwareModel)
        }
        let expectedExtensions: Set<String>
        switch asset.hardwareModel {
        case .automatic:
            throw HomebrewCatalogError.invalidAssetHardwareModel(asset.hardwareModel)
        case .wonderSwan:
            expectedExtensions = ["ws"]
        case .wonderSwanColor, .swanCrystal:
            expectedExtensions = ["wsc"]
        case .pocketChallengeV2:
            expectedExtensions = ["pc2", "pcv2"]
        }
        guard expectedExtensions.contains(asset.fileExtension),
              asset.url.pathExtension == asset.fileExtension else {
            throw HomebrewCatalogError.assetFileExtensionMismatch
        }
    }

    private static func validateText(
        _ value: String,
        field: String,
        maximumUTF8Bytes: Int
    ) throws {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count <= maximumUTF8Bytes,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw HomebrewCatalogError.invalidEntryText(field)
        }
    }

    private static func isIdentifier(
        _ value: String,
        maximumUTF8Bytes: Int
    ) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= maximumUTF8Bytes,
              value.first?.isASCII == true,
              value.first?.isLetter == true,
              value.last?.isASCII == true,
              value.last?.isLetter == true || value.last?.isNumber == true,
              !value.contains("..") else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x61...0x7a, 0x30...0x39, 0x2d, 0x2e: true
            default: false
            }
        }
    }

    private static func isVersion(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 64,
              value.first?.isASCII == true,
              value.first?.isNumber == true,
              value.last?.isASCII == true,
              value.last?.isLetter == true || value.last?.isNumber == true,
              !value.contains("..") else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x61...0x7a, 0x30...0x39, 0x2b, 0x2d, 0x2e: true
            default: false
            }
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x61...0x66: true
            default: false
            }
        }
    }

    private static func isCatalogSourceURL(_ url: URL) -> Bool {
        guard let components = safeHTTPSComponents(url),
              let host = components.host?.lowercased(),
              host == "raw.githubusercontent.com",
              let path = pathSegments(components) else { return false }
        return path == [
            "RegionallyFamous",
            "swansong-story-forge",
            "main",
            "distribution",
            "catalog-v1.json",
        ]
    }

    private static func isGameRepositoryURL(
        _ url: URL,
        entryID: String,
        kind: String
    ) -> Bool {
        guard let components = safeHTTPSComponents(url),
              components.host?.lowercased() == "github.com",
              let path = pathSegments(components) else { return false }
        return path.count >= 6
            && path[0] == "RegionallyFamous"
            && path[1] == "swansong-story-forge"
            && path[2] == kind
            && isCommitSHA(path[3])
            && path[4] == "games"
            && path[5] == entryID
    }

    private static func isRepositoryBlobURL(_ url: URL) -> Bool {
        guard let components = safeHTTPSComponents(url),
              components.host?.lowercased() == "github.com",
              let path = pathSegments(components) else { return false }
        return path.count >= 5
            && path[0] == "RegionallyFamous"
            && path[1] == "swansong-story-forge"
            && path[2] == "blob"
            && isCommitSHA(path[3])
    }

    private static func isScreenshotURL(_ url: URL, sourceURL: URL) -> Bool {
        guard let components = safeHTTPSComponents(url),
              components.host?.lowercased() == "raw.githubusercontent.com",
              let path = pathSegments(components),
              let sourceComponents = safeHTTPSComponents(sourceURL),
              let sourcePath = pathSegments(sourceComponents) else { return false }
        return path.count >= 4
            && sourcePath.count >= 6
            && path[0] == sourcePath[0]
            && path[1] == sourcePath[1]
            && path[2] == sourcePath[3]
            && ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }

    private static func releaseTag(from url: URL) -> String? {
        guard let components = safeHTTPSComponents(url),
              components.host?.lowercased() == "github.com",
              let path = pathSegments(components),
              path.count == 5,
              path[0] == "RegionallyFamous",
              path[1] == "swansong-story-forge",
              path[2] == "releases",
              path[3] == "tag" else { return nil }
        return path[4]
    }

    private static func isImmutableReleaseTag(_ tag: String) -> Bool {
        !["latest", "main", "master", "head"].contains(tag.lowercased())
    }

    private static func assetReleaseTag(from url: URL) -> String? {
        guard let components = safeHTTPSComponents(url),
              components.host?.lowercased() == "github.com",
              let path = pathSegments(components),
              path.count == 6,
              path[0] == "RegionallyFamous",
              path[1] == "swansong-story-forge",
              path[2] == "releases",
              path[3] == "download" else { return nil }
        return path[4]
    }

    private static func safeHTTPSComponents(_ url: URL) -> URLComponents? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else { return nil }
        return components
    }

    private static func isCommitSHA(_ value: String) -> Bool {
        value.count == 40 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x61...0x66: true
            default: false
            }
        }
    }

    private static func pathSegments(_ components: URLComponents) -> [String]? {
        let encoded = components.percentEncodedPath
        guard !encoded.isEmpty,
              !encoded.contains("%"),
              !encoded.contains("//") else { return nil }
        let segments = encoded.split(separator: "/").map(String.init)
        guard segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return segments
    }

    private static func validateJSONShape(_ object: Any) throws {
        let catalog = try dictionary(object, location: "document")
        try requireKeys(
            catalog,
            required: ["schemaVersion", "catalogID", "revision", "generatedAt", "repositoryURL", "entries"],
            optional: [],
            location: "document"
        )
        guard let entries = catalog["entries"] as? [Any] else {
            throw HomebrewCatalogError.invalidJSONSchema("entries")
        }
        for (entryIndex, entryObject) in entries.enumerated() {
            let location = "entries[\(entryIndex)]"
            let entry = try dictionary(entryObject, location: location)
            try requireKeys(
                entry,
                required: ["id", "title", "developer", "summary", "description", "sourceURL", "provenanceURL", "licenseName", "licenseURL", "releases"],
                optional: ["screenshotURL"],
                location: location
            )
            guard let releases = entry["releases"] as? [Any] else {
                throw HomebrewCatalogError.invalidJSONSchema("\(location).releases")
            }
            for (releaseIndex, releaseObject) in releases.enumerated() {
                let releaseLocation = "\(location).releases[\(releaseIndex)]"
                let release = try dictionary(releaseObject, location: releaseLocation)
                try requireKeys(
                    release,
                    required: ["version", "saveCompatibilityID", "releasedAt", "releaseURL", "asset"],
                    optional: [],
                    location: releaseLocation
                )
                let asset = try dictionary(
                    release["asset"] as Any,
                    location: "\(releaseLocation).asset"
                )
                try requireKeys(
                    asset,
                    required: ["url", "byteCount", "sha256", "fileExtension", "hardwareModel"],
                    optional: [],
                    location: "\(releaseLocation).asset"
                )
            }
        }
    }

    private static func dictionary(
        _ object: Any,
        location: String
    ) throws -> [String: Any] {
        guard let dictionary = object as? [String: Any] else {
            throw HomebrewCatalogError.invalidJSONSchema(location)
        }
        return dictionary
    }

    private static func requireKeys(
        _ dictionary: [String: Any],
        required: Set<String>,
        optional: Set<String>,
        location: String
    ) throws {
        let keys = Set(dictionary.keys)
        guard required.isSubset(of: keys),
              keys.isSubset(of: required.union(optional)) else {
            throw HomebrewCatalogError.invalidJSONSchema(location)
        }
    }
}

public enum HomebrewCatalogInstallAction: String, Equatable, Sendable {
    case installed
    case adopted
    case updated
    case unchanged
}

public struct HomebrewCatalogInstallResult: Sendable {
    public let games: [GameRecord]
    public let gameID: GameRecord.ID
    public let createdReference: ManagedGameReference?
    public let action: HomebrewCatalogInstallAction

    public init(
        games: [GameRecord],
        gameID: GameRecord.ID,
        createdReference: ManagedGameReference?,
        action: HomebrewCatalogInstallAction
    ) {
        self.games = games
        self.gameID = gameID
        self.createdReference = createdReference
        self.action = action
    }
}

/// Applies already-downloaded catalog asset bytes to an immutable library
/// snapshot. The caller persists `result.games`, then removes
/// `createdReference` on persistence failure or prunes superseded managed
/// references after success.
public struct HomebrewCatalogInstaller: Sendable {
    private let assetData: Data

    public init(assetData: Data) {
        self.assetData = assetData
    }

    public func install(
        entry: HomebrewCatalogEntry,
        release: HomebrewCatalogRelease,
        catalogID: String = HomebrewCatalogValidator.firstPartyCatalogID,
        into existingGames: [GameRecord],
        managedStore: ManagedGameStore
    ) throws -> HomebrewCatalogInstallResult {
        try HomebrewCatalogValidator.validateForInstallation(
            entry: entry,
            release: release,
            catalogID: catalogID
        )
        let asset = release.asset
        guard assetData.count == asset.byteCount else {
            throw HomebrewCatalogError.assetByteCountMismatch(
                expected: asset.byteCount,
                actual: assetData.count
            )
        }
        guard ManagedGameStore.sha256(assetData) == asset.sha256 else {
            throw HomebrewCatalogError.assetSHA256Mismatch
        }

        let metadata: ROMMetadata
        do {
            metadata = try GameROMValidationPolicy.validateLibraryImage(assetData)
        } catch {
            throw HomebrewCatalogError.invalidAssetContents
        }
        guard metadata.checksumIsValid,
              Self.sizeDeclarationIsValid(metadata),
              Self.hardwareModel(asset.hardwareModel, accepts: metadata) else {
            throw HomebrewCatalogError.invalidAssetContents
        }

        let catalogIndices = existingGames.indices.filter { index in
            existingGames[index].homebrewCatalogOrigin?.catalogID
                == catalogID
                && existingGames[index].homebrewCatalogOrigin?.entryID == entry.id
        }
        guard catalogIndices.count <= 1 else {
            throw HomebrewCatalogError.conflictingLibraryIdentity
        }

        let digestIndices = existingGames.indices.filter { index in
            existingGames[index].managedROM?.sha256 == asset.sha256
        }
        let targetIndex: Int?
        let action: HomebrewCatalogInstallAction
        if let catalogIndex = catalogIndices.first {
            guard let origin = existingGames[catalogIndex].homebrewCatalogOrigin,
                  HomebrewCatalogValidator.originIsValid(origin) else {
                throw HomebrewCatalogError.invalidExistingOrigin
            }
            guard origin.saveCompatibilityID == release.saveCompatibilityID else {
                throw HomebrewCatalogError.changedSaveCompatibility(
                    existing: origin.saveCompatibilityID,
                    requested: release.saveCompatibilityID
                )
            }
            if origin.version == release.version,
               origin.assetSHA256 != asset.sha256 {
                throw HomebrewCatalogError.mutableReleaseVersion(release.version)
            }
            if origin.assetSHA256 != asset.sha256 {
                let installedReleasedAt = origin.releasedAt
                    ?? entry.releases.first(where: {
                        $0.version == origin.version
                            && $0.asset.sha256 == origin.assetSHA256
                    })?.releasedAt
                guard let installedReleasedAt,
                      !Self.releaseSortsBefore(
                       releasedAt: release.releasedAt,
                       version: release.version,
                       than: installedReleasedAt,
                       version: origin.version
                      ) else {
                    throw HomebrewCatalogError.releaseDowngrade(
                        installed: origin.version,
                        requested: release.version
                    )
                }
                if existingGames[catalogIndex].resolvedHardwareModel == .pocketChallengeV2
                    || asset.hardwareModel == .pocketChallengeV2 {
                    throw HomebrewCatalogError.pocketChallengeUpdateRequiresMigration
                }
                guard existingGames[catalogIndex].resolvedHardwareModel
                        == asset.hardwareModel,
                      existingGames[catalogIndex].metadata.saveType == metadata.saveType,
                      existingGames[catalogIndex].metadata.hasRTC == metadata.hasRTC else {
                    throw HomebrewCatalogError.changedPersistenceContract
                }
            }
            targetIndex = catalogIndex
            action = origin.version == release.version
                && origin.assetSHA256 == asset.sha256 ? .unchanged : .updated
        } else if let digestIndex = digestIndices.first {
            guard digestIndices.count == 1 else {
                throw HomebrewCatalogError.conflictingLibraryIdentity
            }
            guard existingGames[digestIndex].homebrewCatalogOrigin == nil else {
                throw HomebrewCatalogError.conflictingLibraryIdentity
            }
            targetIndex = digestIndex
            action = .adopted
        } else {
            targetIndex = nil
            action = .installed
        }

        let image = LibraryGameImportImage(
            data: assetData,
            suggestedTitle: entry.title,
            sourceFileName: asset.url.lastPathComponent,
            metadata: metadata,
            sha256: asset.sha256,
            hardwareModel: asset.hardwareModel
        )
        let installed = try managedStore.install(image)
        let origin = HomebrewCatalogOrigin(
            catalogID: catalogID,
            entryID: entry.id,
            version: release.version,
            releasedAt: release.releasedAt,
            saveCompatibilityID: release.saveCompatibilityID,
            assetSHA256: asset.sha256
        )

        var games = existingGames
        let gameID: GameRecord.ID
        if let targetIndex {
            gameID = games[targetIndex].id
            games[targetIndex].fileURL = installed.fileURL
            games[targetIndex].metadata = metadata
            games[targetIndex].managedROM = installed.reference
            games[targetIndex].sourceFileName = asset.url.lastPathComponent
            games[targetIndex].homebrewCatalogOrigin = origin
            games[targetIndex].preferredHardwareModel = asset.hardwareModel
        } else {
            let game = GameRecord(
                title: entry.title,
                fileURL: installed.fileURL,
                metadata: metadata,
                managedROM: installed.reference,
                sourceFileName: asset.url.lastPathComponent,
                homebrewCatalogOrigin: origin,
                preferredHardwareModel: asset.hardwareModel
            )
            games.append(game)
            gameID = game.id
        }

        return HomebrewCatalogInstallResult(
            games: games,
            gameID: gameID,
            createdReference: installed.created ? installed.reference : nil,
            action: action
        )
    }

    private static func hardwareModel(
        _ hardwareModel: EngineHardwareModel,
        accepts metadata: ROMMetadata
    ) -> Bool {
        switch hardwareModel {
        case .automatic:
            false
        case .wonderSwan, .pocketChallengeV2:
            !metadata.isColor
        case .wonderSwanColor, .swanCrystal:
            metadata.isColor
        }
    }

    private static func releaseSortsBefore(
        releasedAt candidateDate: Date?,
        version candidateVersion: String,
        than installedDate: Date,
        version installedVersion: String
    ) -> Bool {
        guard let candidateDate else { return true }
        if candidateDate != installedDate {
            return candidateDate < installedDate
        }
        return candidateVersion < installedVersion
    }

    private static func sizeDeclarationIsValid(_ metadata: ROMMetadata) -> Bool {
        GameROMValidationPolicy.sizeDeclarationIsValid(metadata)
    }
}
