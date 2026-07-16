import AppKit
import Foundation
import Observation
import SwanSongKit
import SwiftUI

enum PocketCoreSetupAccessibility {
    static let page = "pocket-core-setup"
    static let checkRelease = "pocket-core-check-release"
    static let chooseCard = "pocket-core-choose-card"
    static let prepareCard = "pocket-core-prepare-card"
    static let minimumInteractiveDimension: CGFloat = 28
}

struct AvailablePocketCoreRelease: Equatable, Sendable {
    let metadata: PocketCoreReleaseMetadata
    let releaseTag: String
    let packageDownloadURL: URL
    let releasePageURL: URL
}

enum PocketCoreReleaseServiceError: LocalizedError {
    case invalidResponse(String)
    case missingAsset(String)
    case downloadFailed(String)
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(detail):
            "The official SwanSong Core release could not be read. \(detail)"
        case let .missingAsset(detail):
            "The official release is incomplete. \(detail)"
        case let .downloadFailed(detail):
            "The SwanSong Core package could not be downloaded. \(detail)"
        case let .archiveFailed(detail):
            "The verified SwanSong Core package could not be opened. \(detail)"
        }
    }
}

private enum PocketCoreWireError: LocalizedError {
    case untrustedRedirect
    case unexpectedResponse
    case responseTooLarge
    case byteCountMismatch

    var errorDescription: String? {
        switch self {
        case .untrustedRedirect:
            "GitHub redirected the Core download outside its trusted asset hosts."
        case .unexpectedResponse:
            "GitHub did not return the requested Core release file."
        case .responseTooLarge:
            "The Core release download exceeded SwanSong’s safety limit."
        case .byteCountMismatch:
            "The Core release download size did not match GitHub’s asset record."
        }
    }
}

private struct PocketCoreWireResponse: Sendable {
    let data: Data
    let statusCode: Int
}

private struct PocketCoreDownloadPolicy: Sendable {
    let maximumByteCount: Int
    let expectedByteCount: Int?
    let acceptedStatusCodes: Set<Int>
}

private final class PocketCoreDownloadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func attach(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}

private final class PocketCoreDownloadDelegate: NSObject, URLSessionDataDelegate,
    @unchecked Sendable {
    private final class Transfer: @unchecked Sendable {
        let continuation: CheckedContinuation<PocketCoreWireResponse, Error>
        let policy: PocketCoreDownloadPolicy
        var data: Data
        var statusCode: Int?
        var advertisedByteCount: Int64?

        init(
            continuation: CheckedContinuation<PocketCoreWireResponse, Error>,
            policy: PocketCoreDownloadPolicy
        ) {
            self.continuation = continuation
            self.policy = policy
            self.data = Data()
            self.data.reserveCapacity(
                min(policy.expectedByteCount ?? 64 * 1_024, policy.maximumByteCount)
            )
        }
    }

    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private let trustsRedirect: @Sendable (URL) -> Bool

    init(trustsRedirect: @escaping @Sendable (URL) -> Bool) {
        self.trustsRedirect = trustsRedirect
    }

    func data(
        for request: URLRequest,
        using session: URLSession,
        policy: PocketCoreDownloadPolicy
    ) async throws -> PocketCoreWireResponse {
        let cancellation = PocketCoreDownloadCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                let transfer = Transfer(
                    continuation: continuation,
                    policy: policy
                )
                lock.lock()
                transfers[task.taskIdentifier] = transfer
                lock.unlock()
                cancellation.attach(task)
                task.resume()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, trustsRedirect(url) else {
            completionHandler(nil)
            if let transfer = removeTransfer(for: task.taskIdentifier) {
                transfer.continuation.resume(
                    throwing: PocketCoreWireError.untrustedRedirect
                )
            }
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        var failure: PocketCoreWireError?
        lock.lock()
        if let transfer = transfers[dataTask.taskIdentifier],
           let response = response as? HTTPURLResponse {
            if (300..<400).contains(response.statusCode) {
                failure = .untrustedRedirect
            } else if !transfer.policy.acceptedStatusCodes.contains(response.statusCode) {
                failure = .unexpectedResponse
            } else if response.expectedContentLength
                > Int64(transfer.policy.maximumByteCount) {
                failure = .responseTooLarge
            } else if let expectedByteCount = transfer.policy.expectedByteCount,
                      response.expectedContentLength >= 0,
                      response.expectedContentLength != Int64(expectedByteCount) {
                failure = .byteCountMismatch
            } else if let contentEncoding = response.value(
                forHTTPHeaderField: "Content-Encoding"
            ), contentEncoding.lowercased() != "identity" {
                failure = .unexpectedResponse
            } else {
                transfer.statusCode = response.statusCode
                if response.expectedContentLength >= 0 {
                    transfer.advertisedByteCount = response.expectedContentLength
                }
            }
        } else {
            failure = .unexpectedResponse
        }
        let failedTransfer = failure == nil
            ? nil
            : transfers.removeValue(forKey: dataTask.taskIdentifier)
        lock.unlock()

        guard let failure else {
            completionHandler(.allow)
            return
        }
        completionHandler(.cancel)
        failedTransfer?.continuation.resume(throwing: failure)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        var failedTransfer: Transfer?
        var failure: PocketCoreWireError?

        lock.lock()
        if let transfer = transfers[dataTask.taskIdentifier] {
            if let expectedByteCount = transfer.policy.expectedByteCount,
               data.count > expectedByteCount - transfer.data.count {
                failure = .byteCountMismatch
            } else if data.count
                > transfer.policy.maximumByteCount - transfer.data.count {
                failure = .responseTooLarge
            } else {
                transfer.data.append(data)
            }
            if failure != nil {
                failedTransfer = transfers.removeValue(
                    forKey: dataTask.taskIdentifier
                )
            }
        }
        lock.unlock()

        if let failure {
            failedTransfer?.continuation.resume(throwing: failure)
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let transfer = removeTransfer(for: task.taskIdentifier) else {
            return
        }
        if let error {
            let urlError = error as NSError
            if urlError.domain == NSURLErrorDomain,
               urlError.code == NSURLErrorCancelled {
                transfer.continuation.resume(throwing: CancellationError())
            } else {
                transfer.continuation.resume(throwing: error)
            }
            return
        }
        guard let statusCode = transfer.statusCode else {
            transfer.continuation.resume(
                throwing: PocketCoreWireError.unexpectedResponse
            )
            return
        }
        if let expectedByteCount = transfer.policy.expectedByteCount,
           transfer.data.count != expectedByteCount {
            transfer.continuation.resume(
                throwing: PocketCoreWireError.byteCountMismatch
            )
            return
        }
        if let advertisedByteCount = transfer.advertisedByteCount,
           transfer.data.count != Int(advertisedByteCount) {
            transfer.continuation.resume(
                throwing: PocketCoreWireError.byteCountMismatch
            )
            return
        }
        transfer.continuation.resume(
            returning: PocketCoreWireResponse(
                data: transfer.data,
                statusCode: statusCode
            )
        )
    }

    private func removeTransfer(for taskIdentifier: Int) -> Transfer? {
        lock.lock()
        let transfer = transfers.removeValue(forKey: taskIdentifier)
        lock.unlock()
        return transfer
    }
}

struct PocketCoreReleaseService: Sendable {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/RegionallyFamous/swansong-core/releases/latest"
    )!
    private static let maximumReleaseMetadataBytes = 2 * 1_024 * 1_024
    private static let maximumPackageBytes = 32 * 1_024 * 1_024
    private static let trustedRedirectHosts: Set<String> = [
        "api.github.com",
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let size: Int

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
            }
        }

        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let immutable: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case immutable
            case assets
        }
    }

    private let session: URLSession
    private let downloadDelegate: PocketCoreDownloadDelegate

    init(session: URLSession = .shared) {
        let configuration = session.configuration
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        let delegate = PocketCoreDownloadDelegate(
            trustsRedirect: Self.isTrustedRedirect
        )
        self.downloadDelegate = delegate
        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func latestRelease() async throws -> AvailablePocketCoreRelease? {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("SwanSong-Desktop", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let response = try await boundedData(
            for: request,
            maximumByteCount: Self.maximumReleaseMetadataBytes,
            expectedByteCount: nil,
            acceptedStatusCodes: [200, 404]
        )
        if response.statusCode == 404 {
            return nil
        }
        let data = response.data

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw PocketCoreReleaseServiceError.invalidResponse(
                "The release metadata is malformed."
            )
        }
        guard !release.draft, !release.prerelease else {
            return nil
        }
        guard release.immutable else {
            throw PocketCoreReleaseServiceError.invalidResponse(
                "The stable release is not protected as an immutable GitHub Release."
            )
        }
        try validateReleasePageURL(release.htmlURL, releaseTag: release.tagName)
        let manifestAsset = try exactlyOneAsset(named: "release-manifest.json", in: release)
        let checksumsAsset = try exactlyOneAsset(named: "SHA256SUMS", in: release)
        try validateDownloadURL(
            manifestAsset.browserDownloadURL,
            releaseTag: release.tagName,
            filename: manifestAsset.name
        )
        try validateDownloadURL(
            checksumsAsset.browserDownloadURL,
            releaseTag: release.tagName,
            filename: checksumsAsset.name
        )

        async let manifest = downloadSmallAsset(
            manifestAsset,
            maximumBytes: 2 * 1_024 * 1_024
        )
        async let checksums = downloadSmallAsset(
            checksumsAsset,
            maximumBytes: 64 * 1_024
        )
        let metadata = try await PocketCoreReleaseVerifier.verify(
            manifestData: manifest,
            checksumsData: checksums,
            githubTag: release.tagName
        )
        let packageAsset = try exactlyOneAsset(named: metadata.packageFilename, in: release)
        guard packageAsset.size == metadata.packageByteCount else {
            throw PocketCoreReleaseServiceError.missingAsset(
                "GitHub's package size does not match release-manifest.json."
            )
        }
        try validateDownloadURL(
            packageAsset.browserDownloadURL,
            releaseTag: release.tagName,
            filename: packageAsset.name
        )
        return AvailablePocketCoreRelease(
            metadata: metadata,
            releaseTag: release.tagName,
            packageDownloadURL: packageAsset.browserDownloadURL,
            releasePageURL: release.htmlURL
        )
    }

    func downloadPackage(
        _ release: AvailablePocketCoreRelease
    ) async throws -> PocketCorePackage {
        try validateDownloadURL(
            release.packageDownloadURL,
            releaseTag: release.releaseTag,
            filename: release.metadata.packageFilename
        )
        var request = URLRequest(url: release.packageDownloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("SwanSong-Desktop", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let packageData = try await boundedData(
            for: request,
            maximumByteCount: Self.maximumPackageBytes,
            expectedByteCount: release.metadata.packageByteCount,
            acceptedStatusCodes: [200]
        ).data

        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-Pocket-Core-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: workspace) }
            let archive = workspace.appendingPathComponent(release.metadata.packageFilename)
            try packageData.write(to: archive, options: .withoutOverwriting)
            try PocketCoreReleaseVerifier.verifyPackage(at: archive, release: release.metadata)
            let extracted = workspace.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
            try await Task.detached(priority: .userInitiated) {
                try PocketCoreArchiveExtractor.extract(archive: archive, to: extracted)
            }.value
            return try PocketCorePackage(
                extractedDirectoryURL: extracted,
                release: release.metadata
            )
        } catch let error as PocketCoreInstallerError {
            throw error
        } catch let error as PocketCoreReleaseServiceError {
            throw error
        } catch {
            throw PocketCoreReleaseServiceError.downloadFailed(error.localizedDescription)
        }
    }

    private func exactlyOneAsset(
        named name: String,
        in release: GitHubRelease
    ) throws -> GitHubRelease.Asset {
        let matches = release.assets.filter { $0.name == name }
        guard matches.count == 1, let match = matches.first else {
            throw PocketCoreReleaseServiceError.missingAsset(
                "Expected exactly one \(name) asset."
            )
        }
        return match
    }

    private func downloadSmallAsset(
        _ asset: GitHubRelease.Asset,
        maximumBytes: Int
    ) async throws -> Data {
        guard asset.size > 0, asset.size <= maximumBytes else {
            throw PocketCoreReleaseServiceError.missingAsset(
                "\(asset.name) is empty or too large."
            )
        }
        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("SwanSong-Desktop", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await boundedData(
            for: request,
            maximumByteCount: maximumBytes,
            expectedByteCount: asset.size,
            acceptedStatusCodes: [200]
        ).data
    }

    private func validateDownloadURL(
        _ url: URL,
        releaseTag: String,
        filename: String
    ) throws {
        guard let components = Self.safeHTTPSComponents(url),
              components.host?.lowercased() == "github.com",
              let segments = Self.strictPathSegments(components.percentEncodedPath),
              segments.count == 6,
              segments[0] == "RegionallyFamous",
              segments[1] == "swansong-core",
              segments[2] == "releases",
              segments[3] == "download",
              segments[4] == releaseTag,
              segments[5] == filename else {
            throw PocketCoreReleaseServiceError.invalidResponse(
                "A release asset points outside the official GitHub repository."
            )
        }
    }

    private func validateReleasePageURL(_ url: URL, releaseTag: String) throws {
        guard let components = Self.safeHTTPSComponents(url),
              components.host?.lowercased() == "github.com",
              let segments = Self.strictPathSegments(components.percentEncodedPath),
              segments.count == 5,
              segments[0] == "RegionallyFamous",
              segments[1] == "swansong-core",
              segments[2] == "releases",
              segments[3] == "tag",
              segments[4] == releaseTag else {
            throw PocketCoreReleaseServiceError.invalidResponse(
                "The release page points outside the official GitHub repository."
            )
        }
    }

    private func boundedData(
        for request: URLRequest,
        maximumByteCount: Int,
        expectedByteCount: Int?,
        acceptedStatusCodes: Set<Int>
    ) async throws -> PocketCoreWireResponse {
        try await downloadDelegate.data(
            for: request,
            using: session,
            policy: PocketCoreDownloadPolicy(
                maximumByteCount: maximumByteCount,
                expectedByteCount: expectedByteCount,
                acceptedStatusCodes: acceptedStatusCodes
            )
        )
    }

    private static func safeHTTPSComponents(_ url: URL) -> URLComponents? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "https",
        components.host != nil,
        components.user == nil,
        components.password == nil,
        components.port == nil,
        components.query == nil,
        components.fragment == nil else {
            return nil
        }
        return components
    }

    private static func strictPathSegments(_ encodedPath: String) -> [String]? {
        guard strictRedirectPath(encodedPath),
              !encodedPath.contains("%") else {
            return nil
        }
        return encodedPath.split(separator: "/").map(String.init)
    }

    private static func strictRedirectPath(_ encodedPath: String) -> Bool {
        guard !encodedPath.isEmpty,
              !encodedPath.contains("//") else {
            return false
        }
        let lowercasedPath = encodedPath.lowercased()
        guard !lowercasedPath.contains("%2f"),
              !lowercasedPath.contains("%5c"),
              !lowercasedPath.contains("%2e") else {
            return false
        }
        let segments = encodedPath.split(separator: "/")
        return !segments.isEmpty && segments.allSatisfy {
            $0 != "." && $0 != ".."
        }
    }

    private static func isTrustedRedirect(_ url: URL) -> Bool {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "https",
        components.user == nil,
        components.password == nil,
        components.port == nil,
        components.fragment == nil,
        let host = components.host?.lowercased(),
        trustedRedirectHosts.contains(host),
        strictRedirectPath(components.percentEncodedPath) else {
            return false
        }
        if components.query != nil {
            return host == "objects.githubusercontent.com"
                || host == "release-assets.githubusercontent.com"
        }
        return true
    }

    #if SWAN_SONG_AUTOMATION
    static func productionTrustsRedirectForTesting(_ url: URL) -> Bool {
        isTrustedRedirect(url)
    }
    #endif
}

enum PocketCoreArchiveExtractor {
    private static let maximumListingBytes = 256 * 1_024
    private static let maximumEntries = 128
    private static let maximumFileBytes = 8 * 1_024 * 1_024
    private static let maximumExpandedBytes = 16 * 1_024 * 1_024

    static func extract(archive: URL, to destination: URL) throws {
        let listing = try run(
            executable: "/usr/bin/unzip",
            arguments: ["-Z", "-1", archive.path],
            outputLimit: maximumListingBytes
        )
        let names = listing.split(separator: 0x0A, omittingEmptySubsequences: true)
        guard !names.isEmpty, names.count <= maximumEntries else {
            throw PocketCoreReleaseServiceError.archiveFailed(
                "The ZIP has no entries or exceeds the accepted entry limit."
            )
        }
        for rawName in names {
            guard let name = String(data: Data(rawName), encoding: .utf8) else {
                throw PocketCoreReleaseServiceError.archiveFailed(
                    "The ZIP contains a filename that is not UTF-8."
                )
            }
            try validateEntry(name)
        }
        let detailListing = try run(
            executable: "/usr/bin/zipinfo",
            arguments: ["-l", archive.path],
            outputLimit: maximumListingBytes
        )
        try validateEntryTypesAndSizes(detailListing, expectedCount: names.count)
        _ = try run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archive.path, destination.path],
            outputLimit: 64 * 1_024
        )
    }

    private static func validateEntryTypesAndSizes(
        _ listing: Data,
        expectedCount: Int
    ) throws {
        guard let text = String(data: listing, encoding: .utf8) else {
            throw PocketCoreReleaseServiceError.archiveFailed(
                "The ZIP details are not valid UTF-8."
            )
        }
        let records = text.split(separator: "\n").filter { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            return fields.count >= 10 && fields[2] == "unx"
        }
        guard records.count == expectedCount else {
            throw PocketCoreReleaseServiceError.archiveFailed(
                "The ZIP entry inventory is ambiguous."
            )
        }
        var total = 0
        for record in records {
            let fields = record.split(whereSeparator: { $0.isWhitespace })
            guard let type = fields[0].first,
                  type == "-" || type == "d",
                  let size = Int(fields[3]),
                  size >= 0,
                  (type == "d" ? size == 0 : size <= maximumFileBytes) else {
                throw PocketCoreReleaseServiceError.archiveFailed(
                    "The ZIP contains a link, special entry, or oversized file."
                )
            }
            total += size
            guard total <= maximumExpandedBytes else {
                throw PocketCoreReleaseServiceError.archiveFailed(
                    "The ZIP expands beyond the accepted size limit."
                )
            }
        }
    }

    private static func validateEntry(_ raw: String) throws {
        let name = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty,
              name.utf8.count <= 1_024,
              !name.hasPrefix("/"),
              !name.contains("\\"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !parts.contains(where: { $0.utf8.count > 255 }),
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }),
              let first = parts.first,
              ["Assets", "Cores", "Platforms"].contains(String(first)) else {
            throw PocketCoreReleaseServiceError.archiveFailed(
                "The ZIP contains an unsafe or unsupported path."
            )
        }
    }

    private static func run(
        executable: String,
        arguments: [String],
        outputLimit: Int
    ) throws -> Data {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-Archive-Output-\(UUID().uuidString)"
        )
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-Archive-Error-\(UUID().uuidString)"
        )
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? errors.close()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PocketCoreReleaseServiceError.archiveFailed(
                "A required macOS archive tool could not run."
            )
        }
        try output.synchronize()
        try errors.synchronize()
        let outputData = try boundedData(at: outputURL, maximum: outputLimit)
        let errorData = try boundedData(at: errorURL, maximum: 64 * 1_024)
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PocketCoreReleaseServiceError.archiveFailed(
                detail?.isEmpty == false ? detail! : "macOS rejected the ZIP."
            )
        }
        return outputData
    }

    private static func boundedData(at url: URL, maximum: Int) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximum else {
            throw PocketCoreReleaseServiceError.archiveFailed(
                "The archive tool produced too much output."
            )
        }
        return try Data(contentsOf: url)
    }
}

struct PocketCardSelection: Equatable, Sendable {
    let rootURL: URL
    let volumeName: String
    let mountIdentity: String
    let formatDescription: String
    let availableByteCount: Int64?
    let hasPocketLayout: Bool
    let installedCoreVersion: String?
}

enum PocketCardInspector {
    private static let pocketDirectories: Set<String> = [
        "Assets", "Cores", "Memories", "Platforms", "Presets", "Saves",
        "Settings", "System",
    ]
    private static let harmlessFreshVolumeEntries: Set<String> = [
        ".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd",
    ]

    static func inspect(_ selectedURL: URL) throws -> PocketCardSelection {
        let root = selectedURL.standardizedFileURL
        guard root.deletingLastPathComponent().path == "/Volumes" else {
            throw PocketCoreInstallerError.invalidDestination(
                "Choose the SD card itself under /Volumes, not a folder inside it."
            )
        }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isWritableKey,
            .volumeIsReadOnlyKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeNameKey,
            .volumeUUIDStringKey,
        ]
        let values = try root.resourceValues(forKeys: keys)
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              values.isWritable == true,
              values.volumeIsReadOnly != true else {
            throw PocketCoreInstallerError.invalidDestination(
                "The selected volume is not writable."
            )
        }
        let formatDescription = values.volumeLocalizedFormatDescription ?? "Unknown"
        let fileSystemType = try PocketVolumeInspection.fileSystemType(at: root)
        guard PocketVolumeInspection.supportsPocketCardFileSystem(fileSystemType) else {
            throw PocketCoreInstallerError.invalidDestination(
                "Analogue Pocket cards must use exFAT or FAT32; this volume reports \(formatDescription)."
            )
        }

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        guard !names.contains(where: { $0.hasPrefix(".swansong-core-install-") }) else {
            throw PocketCoreInstallerError.invalidDestination(
                "The card contains an unfinished SwanSong Core transaction. Restore its backup before trying again."
            )
        }
        let pocketMatches = Self.pocketDirectories.intersection(names)
        let hasPocketLayout = pocketMatches.count >= 2
        let meaningfulNames = Set(names).subtracting(Self.harmlessFreshVolumeEntries)
        guard hasPocketLayout || meaningfulNames.isEmpty else {
            throw PocketCoreInstallerError.invalidDestination(
                "This non-empty volume does not look like an Analogue Pocket card."
            )
        }
        for name in pocketMatches {
            let entry = root.appendingPathComponent(name, isDirectory: true)
            let entryValues = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard entryValues.isDirectory == true,
                  entryValues.isSymbolicLink != true else {
                throw PocketCoreInstallerError.invalidDestination(
                    "The Pocket folder \(name) is not an ordinary directory."
                )
            }
        }
        let mountIdentity: String
        if let volumeUUID = values.volumeUUIDString {
            mountIdentity = "uuid:\(volumeUUID)"
        } else {
            mountIdentity = try PocketVolumeInspection.mountIdentity(at: root)
        }
        return PocketCardSelection(
            rootURL: root,
            volumeName: values.volumeName ?? root.lastPathComponent,
            mountIdentity: mountIdentity,
            formatDescription: formatDescription,
            availableByteCount: try PocketVolumeInspection.availableByteCount(at: root),
            hasPocketLayout: hasPocketLayout,
            installedCoreVersion: installedVersion(on: root)
        )
    }

    private static func installedVersion(on root: URL) -> String? {
        let coreJSON = root.appendingPathComponent(
            "Cores/RegionallyFamous.SwanSong/core.json"
        )
        guard let values = try? coreJSON.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size <= 256 * 1_024,
              let data = try? Data(contentsOf: coreJSON),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let core = object["core"] as? [String: Any],
              let metadata = core["metadata"] as? [String: Any] else { return nil }
        return metadata["version"] as? String
    }
}

@MainActor
@Observable
final class PocketCoreSetupModel {
    var release: AvailablePocketCoreRelease?
    var card: PocketCardSelection?
    var isChecking = false
    var isPreparing = false
    var noReleaseIsPublished = false
    var errorMessage: String?
    var result: PocketCoreInstallResult?

    private let service: PocketCoreReleaseService

    init(service: PocketCoreReleaseService = PocketCoreReleaseService()) {
        self.service = service
    }

    var canPrepare: Bool {
        release != nil && card != nil && !isChecking && !isPreparing
    }

    func checkForRelease() {
        guard !isChecking, !isPreparing else { return }
        isChecking = true
        errorMessage = nil
        noReleaseIsPublished = false
        result = nil
        Task {
            defer { isChecking = false }
            do {
                release = try await service.latestRelease()
                noReleaseIsPublished = release == nil
            } catch {
                release = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func chooseCard() {
        guard !isPreparing else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the Analogue Pocket SD Card"
        panel.message = "Choose the mounted card itself. SwanSong merges only verified core files and does not erase games, saves, settings, or other cores."
        panel.prompt = "Use This Card"
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            card = try PocketCardInspector.inspect(url)
            errorMessage = nil
            result = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareCard() {
        guard let release, let card, canPrepare else { return }
        isPreparing = true
        errorMessage = nil
        result = nil
        Task {
            defer { isPreparing = false }
            do {
                let currentCard = try PocketCardInspector.inspect(card.rootURL)
                try requireSameCard(card, currentCard)
                let package = try await service.downloadPackage(release)
                let readyCard = try PocketCardInspector.inspect(card.rootURL)
                try requireSameCard(currentCard, readyCard)
                let destination = readyCard.rootURL
                result = try await Task.detached(priority: .userInitiated) {
                    try PocketCoreCardPreparer().apply(
                        package: package,
                        destinationURL: destination
                    )
                }.value
                self.card = try? PocketCardInspector.inspect(destination)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requireSameCard(
        _ expected: PocketCardSelection,
        _ observed: PocketCardSelection
    ) throws {
        guard observed.mountIdentity == expected.mountIdentity,
              observed.volumeName == expected.volumeName,
              observed.rootURL == expected.rootURL else {
            throw PocketCoreInstallerError.invalidDestination(
                "The mounted volume changed after it was selected. Choose the card again."
            )
        }
    }
}

struct PocketCoreSetupView: View {
    @Environment(\.openURL) private var openURL
    @State private var setup = PocketCoreSetupModel()
    @State private var showsPrepareConfirmation = false

    private static let releasesURL = URL(
        string: "https://github.com/RegionallyFamous/swansong-core/releases"
    )!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                releaseCard
                cardCard
                prepareCard
                safetyNote
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(SwanTheme.libraryBackground.ignoresSafeArea())
        .navigationTitle("Analogue Pocket")
        .accessibilityIdentifier(PocketCoreSetupAccessibility.page)
        .alert(
            "Prepare \(setup.card?.volumeName ?? "SD Card")?",
            isPresented: $showsPrepareConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Install SwanSong Core") {
                setup.prepareCard()
            }
        } message: {
            Text("SwanSong will install verified Core \(setup.release?.metadata.version ?? "") files on \(setup.card?.rootURL.path ?? "the selected card"). Existing games, saves, settings, and unrelated cores are left in place. Back up the card first.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "sdcard.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(SwanTheme.cyan)
                .frame(width: 56, height: 56)
                .background(SwanTheme.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text("Put SwanSong on your Pocket")
                    .font(.largeTitle.bold())
                Text("Install or update the first-party SwanSong Core on a mounted Analogue Pocket SD card. No external BIOS is needed.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var releaseCard: some View {
        stepCard(number: 1, title: "Verify the official Core release") {
            if setup.isChecking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking the official GitHub release…")
                }
            } else if let release = setup.release {
                statusRow(
                    symbol: "checkmark.seal.fill",
                    tint: .green,
                    title: "SwanSong Core \(release.metadata.version)",
                    detail: "Released \(release.metadata.releaseDate) · checksum and release authorization verified"
                )
                HStack {
                    Button("Check Again", action: setup.checkForRelease)
                    Button("View Release") {
                        openURL(release.releasePageURL)
                    }
                }
            } else if setup.noReleaseIsPublished {
                statusRow(
                    symbol: "clock.badge.exclamationmark",
                    tint: .orange,
                    title: "No verified Core release yet",
                    detail: "The installer stays locked until the SwanSong Core repository publishes an authorized stable release."
                )
                HStack {
                    Button("Check Again", action: setup.checkForRelease)
                    Button("Open Releases") {
                        openURL(Self.releasesURL)
                    }
                }
            } else {
                Text("SwanSong only checks the Core repository when you ask it to.")
                    .foregroundStyle(.secondary)
                Button("Check for Core Release", action: setup.checkForRelease)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(PocketCoreSetupAccessibility.checkRelease)
            }
        }
    }

    private var cardCard: some View {
        stepCard(number: 2, title: "Choose the mounted SD card") {
            if let card = setup.card {
                statusRow(
                    symbol: "externaldrive.fill.badge.checkmark",
                    tint: SwanTheme.cyan,
                    title: card.volumeName,
                    detail: cardDetail(card)
                )
                Text(card.rootURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Use an exFAT or FAT32 card mounted under /Volumes. A blank card or an existing Pocket card is accepted.")
                    .foregroundStyle(.secondary)
            }
            Button(setup.card == nil ? "Choose SD Card…" : "Choose Another Card…") {
                setup.chooseCard()
            }
            .disabled(setup.isPreparing)
            .accessibilityIdentifier(PocketCoreSetupAccessibility.chooseCard)
        }
    }

    private var prepareCard: some View {
        stepCard(number: 3, title: "Prepare and verify") {
            if setup.isPreparing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Downloading, verifying, and merging the Core files…")
                }
                Text("Keep the card connected until this finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let result = setup.result {
                statusRow(
                    symbol: "checkmark.circle.fill",
                    tint: .green,
                    title: "SD card is ready",
                    detail: "SwanSong Core \(result.version) verified · \(result.installedFileCount) file\(result.installedFileCount == 1 ? "" : "s") installed"
                )
                Button("Show Card in Finder") {
                    NSWorkspace.shared.open(result.destinationURL)
                }
                Text("Eject the card in Finder before removing it from the Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("The final confirmation names the exact card and Core version before any file is written.")
                    .foregroundStyle(.secondary)
                Button("Prepare SD Card…") {
                    showsPrepareConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!setup.canPrepare)
                .accessibilityIdentifier(PocketCoreSetupAccessibility.prepareCard)
            }

            if let error = setup.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pocket-core-error")
            }
        }
    }

    private var safetyNote: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("What this changes", systemImage: "shield.checkered")
                .font(.headline)
            Text("The verified package may add or replace SwanSong files below Assets, Cores, and Platforms. It never formats the card, downloads games or BIOS files, removes another core, or changes Saves, Memories, Settings, or Presets. Back up the full card before installing or updating.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stepCard<Content: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(SwanTheme.accent, in: Circle())
                Text(title)
                    .font(.title3.bold())
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

    private func statusRow(
        symbol: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cardDetail(_ card: PocketCardSelection) -> String {
        var details = [card.formatDescription]
        details.append(card.hasPocketLayout ? "existing Pocket layout" : "blank card")
        if let installed = card.installedCoreVersion {
            details.append("SwanSong Core \(installed) installed")
        }
        if let bytes = card.availableByteCount {
            details.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " free")
        }
        return details.joined(separator: " · ")
    }
}
