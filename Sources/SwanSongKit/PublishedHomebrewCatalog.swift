import Foundation

/// Decoder for the signed, rights-attested catalog published by
/// RegionallyFamous/swansong-catalog. The wire format deliberately contains
/// more provenance than the app's presentation model; all of it is validated
/// before an entry can become installable.
public enum PublishedHomebrewCatalogDecoder {
    public static let schema = "swansong-homebrew-catalog-v1"
    public static let catalogID = "regionally-famous.swansong-catalog"
    public static let repositoryURL = URL(
        string: "https://github.com/RegionallyFamous/swansong-catalog"
    )!
    public static let sourceURL = URL(
        string: "https://raw.githubusercontent.com/RegionallyFamous/swansong-catalog/main/dist/catalog-v1.json"
    )!

    private static let publicationEpoch = Date(timeIntervalSince1970: 1_767_225_600)

    public static func decode(_ data: Data, sourceURL: URL) throws -> HomebrewCatalog {
        guard sourceURL == self.sourceURL else {
            throw HomebrewCatalogError.invalidCatalogSourceURL(sourceURL)
        }
        guard !data.isEmpty, data.count <= HomebrewCatalogValidator.maximumCatalogByteCount else {
            throw HomebrewCatalogError.catalogTooLarge
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HomebrewCatalogError.invalidJSONSchema("document")
        }
        try validateShape(object)

        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw HomebrewCatalogError.invalidJSONSchema("document")
        }
        guard document.schema == schema else {
            throw HomebrewCatalogError.unsupportedSchemaVersion(document.catalogVersion)
        }
        guard document.catalogVersion >= 1 else {
            throw HomebrewCatalogError.invalidRevision(document.catalogVersion)
        }
        guard !document.entries.isEmpty,
              document.entries.count <= HomebrewCatalogValidator.maximumEntryCount else {
            throw HomebrewCatalogError.tooManyEntries
        }

        let publishers = try validatedPublishers(document.publishers)
        try validateSourceFiles(document.sourceFiles)
        var ids = Set<String>()
        var digests = Set<String>()
        let releaseDate = publicationEpoch.addingTimeInterval(
            TimeInterval(document.catalogVersion)
        )
        let entries = try document.entries.map { entry -> HomebrewCatalogEntry in
            guard ids.insert(entry.id).inserted else {
                throw HomebrewCatalogError.duplicateEntryID(entry.id)
            }
            guard digests.insert(entry.rom.sha256).inserted else {
                throw HomebrewCatalogError.duplicateAssetSHA256(entry.rom.sha256)
            }
            guard let publisher = publishers[entry.publisher] else {
                throw HomebrewCatalogError.invalidEntryText("publisher")
            }
            return try mappedEntry(entry, publisher: publisher, releaseDate: releaseDate)
        }

        return HomebrewCatalog(
            catalogID: catalogID,
            revision: document.catalogVersion,
            generatedAt: releaseDate,
            repositoryURL: repositoryURL,
            entries: entries
        )
    }

    public static func validateForInstallation(
        entry: HomebrewCatalogEntry,
        release: HomebrewCatalogRelease
    ) throws {
        guard entry.releases.contains(release) else {
            throw HomebrewCatalogError.releaseDoesNotBelongToEntry
        }
        guard let screenshotURL = entry.screenshotURL,
              isIdentifier(entry.id),
              validText(entry.title, maximum: 160),
              validText(entry.developer, maximum: 160),
              validText(entry.summary, maximum: 512),
              validText(entry.description, maximum: 8 * 1_024),
              entry.licenseName == "MIT",
              isFirstPartySource(entry.sourceURL),
              isImmutableEvidence(entry.provenanceURL, sourceURL: entry.sourceURL),
              isImmutableLicense(entry.licenseURL, source: entry.sourceURL),
              isImmutableScreenshot(screenshotURL, sourceURL: entry.sourceURL),
              validVersion(release.version),
              isIdentifier(release.saveCompatibilityID),
              release.releasedAt != nil,
              release.asset.byteCount >= GameROMValidationPolicy.minimumByteCount,
              release.asset.byteCount <= 8 * 1_024 * 1_024,
              release.asset.byteCount.isMultiple(of: 64 * 1_024),
              isLowercaseSHA256(release.asset.sha256),
              release.asset.fileExtension == "wsc",
              release.asset.hardwareModel == .wonderSwanColor,
              release.asset.url.pathExtension == "wsc",
              let tag = immutableReleaseTag(release.asset.url),
              tag == "v\(release.version)",
              releaseAssetMatchesSource(release.asset.url, source: entry.sourceURL),
              release.releaseURL == releaseURL(for: release.asset.url, tag: tag) else {
            throw HomebrewCatalogError.invalidJSONSchema("installable entry")
        }
    }

    private static func mappedEntry(
        _ entry: WireEntry,
        publisher: WirePublisher,
        releaseDate: Date
    ) throws -> HomebrewCatalogEntry {
        guard isIdentifier(entry.id),
              validText(entry.title, maximum: 160),
              validText(entry.summary, maximum: 512),
              validText(publisher.name, maximum: 160),
              entry.players == 1,
              ["horizontal", "vertical", "dynamic"].contains(entry.orientation),
              entry.format == "wsc",
              entry.hardware == ["wonderswan-color"],
              entry.content.ageRating == "Everyone",
              !entry.content.network,
              !entry.content.purchases,
              entry.rights.authorizedForRedistribution,
              entry.rights.originalWork,
              entry.rights.publisherSuppliedScreenshot,
              !entry.controls.isEmpty,
              entry.controls.count <= 32,
              entry.controls.allSatisfy({ validText($0, maximum: 256) }),
              isFirstPartySource(entry.source.url),
              entry.source.license == "MIT",
              immutableReference(entry.source.revision),
              isImmutableEvidence(entry.evidence, source: entry.source),
              isImmutableScreenshot(entry.screenshot, source: entry.source),
              entry.rom.bytes >= GameROMValidationPolicy.minimumByteCount,
              entry.rom.bytes <= 8 * 1_024 * 1_024,
              entry.rom.bytes.isMultiple(of: 64 * 1_024),
              isLowercaseSHA256(entry.rom.sha256),
              let tag = immutableReleaseTag(entry.rom.url),
              tag == "v\(entry.version)",
              releaseAssetMatchesSource(entry.rom.url, source: entry.source.url) else {
            throw HomebrewCatalogError.invalidJSONSchema("entries.\(entry.id)")
        }

        let sourceURL = entry.source.url
        let licenseURL = sourceURL.appendingPathComponent(
            "blob/\(entry.source.revision)/LICENSE"
        )
        let release = HomebrewCatalogRelease(
            version: entry.version,
            saveCompatibilityID: "\(entry.id)-save-v1",
            releasedAt: releaseDate,
            releaseURL: releaseURL(for: entry.rom.url, tag: tag),
            asset: HomebrewCatalogAsset(
                url: entry.rom.url,
                byteCount: entry.rom.bytes,
                sha256: entry.rom.sha256,
                fileExtension: "wsc",
                hardwareModel: .wonderSwanColor
            )
        )
        let mapped = HomebrewCatalogEntry(
            id: entry.id,
            title: entry.title,
            developer: publisher.name,
            summary: entry.summary,
            description: entry.summary,
            sourceURL: sourceURL,
            provenanceURL: entry.evidence,
            licenseName: entry.source.license,
            licenseURL: licenseURL,
            screenshotURL: entry.screenshot,
            releases: [release]
        )
        try validateForInstallation(entry: mapped, release: release)
        return mapped
    }

    private static func validatedPublishers(
        _ publishers: [WirePublisher]
    ) throws -> [String: WirePublisher] {
        guard !publishers.isEmpty, publishers.count <= 64 else {
            throw HomebrewCatalogError.invalidJSONSchema("publishers")
        }
        var result: [String: WirePublisher] = [:]
        for publisher in publishers {
            guard result[publisher.id] == nil,
                  isIdentifier(publisher.id),
                  validText(publisher.name, maximum: 160),
                  publisher.attestsDistributionRights,
                  publisher.controlsRelease,
                  publisher.url.scheme == "https",
                  publisher.url.host?.lowercased() == "github.com",
                  publisher.url.path == "/RegionallyFamous",
                  publisher.url.query == nil,
                  publisher.url.fragment == nil else {
                throw HomebrewCatalogError.invalidJSONSchema("publishers")
            }
            result[publisher.id] = publisher
        }
        return result
    }

    private static func validateSourceFiles(_ files: [WireSourceFile]) throws {
        guard !files.isEmpty, files.count <= 128 else {
            throw HomebrewCatalogError.invalidJSONSchema("sourceFiles")
        }
        var paths = Set<String>()
        for file in files {
            guard paths.insert(file.path).inserted,
                  file.path == URL(fileURLWithPath: file.path).lastPathComponent,
                  file.path.hasSuffix(".json"),
                  isLowercaseSHA256(file.sha256) else {
                throw HomebrewCatalogError.invalidJSONSchema("sourceFiles")
            }
        }
    }

    private static func releaseURL(for assetURL: URL, tag: String) -> URL {
        let components = assetURL.path.split(separator: "/").map(String.init)
        return URL(
            string: "https://github.com/\(components[0])/\(components[1])/releases/tag/\(tag)"
        )!
    }

    private static func immutableReleaseTag(_ url: URL) -> String? {
        guard safeHTTPS(url, host: "github.com"),
              url.query == nil,
              url.fragment == nil else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        guard path.count == 6,
              path[0] == "RegionallyFamous",
              path[2] == "releases",
              path[3] == "download",
              immutableReference(path[4]),
              !path[5].isEmpty else { return nil }
        return path[4]
    }

    private static func isFirstPartySource(_ url: URL) -> Bool {
        guard safeHTTPS(url, host: "github.com"),
              url.query == nil,
              url.fragment == nil else { return false }
        let path = url.path.split(separator: "/").map(String.init)
        return path.count == 2 && path[0] == "RegionallyFamous" && !path[1].isEmpty
    }

    private static func isImmutableEvidence(_ url: URL) -> Bool {
        guard safeHTTPS(url, host: "github.com"),
              url.query == nil,
              url.fragment == nil else { return false }
        let path = url.path.split(separator: "/").map(String.init)
        return path.count >= 5
            && path[0] == "RegionallyFamous"
            && path[2] == "blob"
            && immutableReference(path[3])
    }

    private static func isImmutableEvidence(_ url: URL, source: WireSource) -> Bool {
        guard isImmutableEvidence(url) else { return false }
        let evidencePath = url.path.split(separator: "/").map(String.init)
        let sourcePath = source.url.path.split(separator: "/").map(String.init)
        return evidencePath.count >= 5
            && sourcePath.count == 2
            && evidencePath[0] == sourcePath[0]
            && evidencePath[1] == sourcePath[1]
            && evidencePath[3] == source.revision
    }

    private static func isImmutableEvidence(_ url: URL, sourceURL: URL) -> Bool {
        guard isImmutableEvidence(url) else { return false }
        let evidencePath = url.path.split(separator: "/").map(String.init)
        let sourcePath = sourceURL.path.split(separator: "/").map(String.init)
        return evidencePath.count >= 5
            && sourcePath.count == 2
            && evidencePath[0] == sourcePath[0]
            && evidencePath[1] == sourcePath[1]
    }

    private static func releaseAssetMatchesSource(_ asset: URL, source: URL) -> Bool {
        let assetPath = asset.path.split(separator: "/").map(String.init)
        let sourcePath = source.path.split(separator: "/").map(String.init)
        return assetPath.count == 6
            && sourcePath.count == 2
            && assetPath[0] == sourcePath[0]
            && assetPath[1] == sourcePath[1]
    }

    private static func isImmutableLicense(_ url: URL, source: URL) -> Bool {
        guard safeHTTPS(url, host: "github.com"), url.lastPathComponent == "LICENSE" else {
            return false
        }
        let sourcePath = source.path.split(separator: "/").map(String.init)
        let path = url.path.split(separator: "/").map(String.init)
        return sourcePath.count == 2
            && path.count == 5
            && path[0] == sourcePath[0]
            && path[1] == sourcePath[1]
            && path[2] == "blob"
            && immutableReference(path[3])
    }

    private static func isImmutableScreenshot(_ url: URL, source: WireSource) -> Bool {
        guard safeHTTPS(url, host: "raw.githubusercontent.com"),
              url.query == nil,
              url.fragment == nil else { return false }
        let sourcePath = source.url.path.split(separator: "/").map(String.init)
        let path = url.path.split(separator: "/").map(String.init)
        return sourcePath.count == 2
            && path.count >= 4
            && path[0] == sourcePath[0]
            && path[1] == sourcePath[1]
            && path[2] == source.revision
            && ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }

    private static func isImmutableScreenshot(_ url: URL, sourceURL: URL) -> Bool {
        guard safeHTTPS(url, host: "raw.githubusercontent.com"),
              url.query == nil,
              url.fragment == nil else { return false }
        let sourcePath = sourceURL.path.split(separator: "/").map(String.init)
        let path = url.path.split(separator: "/").map(String.init)
        return sourcePath.count == 2
            && path.count >= 4
            && path[0] == sourcePath[0]
            && path[1] == sourcePath[1]
            && immutableReference(path[2])
            && ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }

    private static func safeHTTPS(_ url: URL, host: String) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == host
            && url.user == nil
            && url.password == nil
            && url.port == nil
            && !url.path.contains("//")
            && !url.path.split(separator: "/").contains("..")
    }

    private static func immutableReference(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 80
            && !["latest", "main", "master", "head"].contains(value.lowercased())
            && value.unicodeScalars.allSatisfy {
                ($0.value >= 0x30 && $0.value <= 0x39)
                    || ($0.value >= 0x41 && $0.value <= 0x5a)
                    || ($0.value >= 0x61 && $0.value <= 0x7a)
                    || [0x2d, 0x2e, 0x5f].contains($0.value)
            }
    }

    private static func validVersion(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 64
            && value.first?.isNumber == true
            && immutableReference(value)
    }

    private static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 128
            && value.first?.isLetter == true
            && (value.last?.isLetter == true || value.last?.isNumber == true)
            && !value.contains("..")
            && value.unicodeScalars.allSatisfy {
                ($0.value >= 0x61 && $0.value <= 0x7a)
                    || ($0.value >= 0x30 && $0.value <= 0x39)
                    || $0.value == 0x2d
            }
    }

    private static func validText(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= maximum
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            ($0.value >= 0x30 && $0.value <= 0x39)
                || ($0.value >= 0x61 && $0.value <= 0x66)
        }
    }

    private static func validateShape(_ object: Any) throws {
        let root = try dictionary(object, "document")
        try exactKeys(root, ["schema", "catalogVersion", "entries", "publishers", "sourceFiles"], "document")
        for (index, object) in try array(root["entries"], "entries").enumerated() {
            let entry = try dictionary(object, "entries[\(index)]")
            try exactKeys(entry, [
                "content", "controls", "evidence", "format", "hardware", "id",
                "orientation", "players", "publisher", "rights", "rom", "screenshot",
                "source", "summary", "title", "version",
            ], "entries[\(index)]")
            try exactKeys(try dictionary(entry["content"], "content"), ["ageRating", "network", "purchases"], "content")
            try exactKeys(try dictionary(entry["rights"], "rights"), ["authorizedForRedistribution", "originalWork", "publisherSuppliedScreenshot"], "rights")
            try exactKeys(try dictionary(entry["rom"], "rom"), ["bytes", "sha256", "url"], "rom")
            try exactKeys(try dictionary(entry["source"], "source"), ["license", "revision", "url"], "source")
        }
        for object in try array(root["publishers"], "publishers") {
            try exactKeys(try dictionary(object, "publisher"), ["attestsDistributionRights", "controlsRelease", "id", "name", "url"], "publisher")
        }
        for object in try array(root["sourceFiles"], "sourceFiles") {
            try exactKeys(try dictionary(object, "sourceFile"), ["path", "sha256"], "sourceFile")
        }
    }

    private static func dictionary(_ value: Any?, _ location: String) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw HomebrewCatalogError.invalidJSONSchema(location)
        }
        return value
    }

    private static func array(_ value: Any?, _ location: String) throws -> [Any] {
        guard let value = value as? [Any] else {
            throw HomebrewCatalogError.invalidJSONSchema(location)
        }
        return value
    }

    private static func exactKeys(
        _ value: [String: Any],
        _ expected: Set<String>,
        _ location: String
    ) throws {
        guard Set(value.keys) == expected else {
            throw HomebrewCatalogError.invalidJSONSchema(location)
        }
    }

    private struct Document: Decodable {
        let schema: String
        let catalogVersion: Int
        let entries: [WireEntry]
        let publishers: [WirePublisher]
        let sourceFiles: [WireSourceFile]
    }

    private struct WireEntry: Decodable {
        let content: WireContent
        let controls: [String]
        let evidence: URL
        let format: String
        let hardware: [String]
        let id: String
        let orientation: String
        let players: Int
        let publisher: String
        let rights: WireRights
        let rom: WireROM
        let screenshot: URL
        let source: WireSource
        let summary: String
        let title: String
        let version: String
    }

    private struct WireContent: Decodable {
        let ageRating: String
        let network: Bool
        let purchases: Bool
    }

    private struct WireRights: Decodable {
        let authorizedForRedistribution: Bool
        let originalWork: Bool
        let publisherSuppliedScreenshot: Bool
    }

    private struct WireROM: Decodable {
        let bytes: Int
        let sha256: String
        let url: URL
    }

    private struct WireSource: Decodable {
        let license: String
        let revision: String
        let url: URL
    }

    private struct WirePublisher: Decodable {
        let attestsDistributionRights: Bool
        let controlsRelease: Bool
        let id: String
        let name: String
        let url: URL
    }

    private struct WireSourceFile: Decodable {
        let path: String
        let sha256: String
    }
}
