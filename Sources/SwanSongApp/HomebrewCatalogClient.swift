import Foundation
import SwanSongKit

enum HomebrewCatalogNetworkError: LocalizedError, Equatable {
    case invalidSource
    case untrustedRedirect
    case unexpectedResponse
    case responseTooLarge
    case byteCountMismatch

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            "SwanSong refused a catalog or download address outside its first-party GitHub repository."
        case .untrustedRedirect:
            "GitHub redirected the download outside SwanSong’s trusted download hosts."
        case .unexpectedResponse:
            "GitHub did not return the requested catalog file."
        case .responseTooLarge:
            "The download exceeded SwanSong’s safety limit."
        case .byteCountMismatch:
            "The downloaded file size did not match the published catalog."
        }
    }
}

struct HomebrewCatalogWireBundle: Equatable, Sendable {
    let catalogData: Data
    let signatureData: Data
}

private struct HomebrewDownloadPolicy: Sendable {
    let maximumByteCount: Int
    let expectedByteCount: Int?
    let progress: (@Sendable (Double) -> Void)?
}

private final class HomebrewDownloadCancellation: @unchecked Sendable {
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

private final class HomebrewDownloadDelegate: NSObject, URLSessionDataDelegate,
    @unchecked Sendable {
    private final class Transfer: @unchecked Sendable {
        let continuation: CheckedContinuation<Data, Error>
        let policy: HomebrewDownloadPolicy
        var data: Data
        var advertisedByteCount: Int64?
        var hasContentEncoding = false
        var nextProgressByteCount = 64 * 1_024

        init(
            continuation: CheckedContinuation<Data, Error>,
            policy: HomebrewDownloadPolicy
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
        policy: HomebrewDownloadPolicy
    ) async throws -> Data {
        let cancellation = HomebrewDownloadCancellation()
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
                    throwing: HomebrewCatalogNetworkError.untrustedRedirect
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
        let failure: HomebrewCatalogNetworkError?
        lock.lock()
        if let transfer = transfers[dataTask.taskIdentifier] {
            if let response = response as? HTTPURLResponse {
                if (300..<400).contains(response.statusCode) {
                    failure = .untrustedRedirect
                } else if response.statusCode != 200 {
                    failure = .unexpectedResponse
                } else if response.expectedContentLength
                    > Int64(transfer.policy.maximumByteCount) {
                    failure = .responseTooLarge
                } else if let expectedByteCount = transfer.policy.expectedByteCount,
                          response.expectedContentLength >= 0,
                          response.expectedContentLength != Int64(expectedByteCount) {
                    failure = .byteCountMismatch
                } else {
                    failure = nil
                    if response.expectedContentLength >= 0 {
                        transfer.advertisedByteCount = response.expectedContentLength
                    }
                    transfer.hasContentEncoding = response.value(
                        forHTTPHeaderField: "Content-Encoding"
                    ) != nil
                }
            } else {
                failure = .unexpectedResponse
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
        var failure: HomebrewCatalogNetworkError?
        var progress: (@Sendable (Double) -> Void)?
        var progressValue: Double?

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
                if let expectedByteCount = transfer.policy.expectedByteCount,
                   transfer.data.count >= transfer.nextProgressByteCount,
                   transfer.data.count < expectedByteCount {
                    progress = transfer.policy.progress
                    progressValue = min(
                        1,
                        Double(transfer.data.count) / Double(expectedByteCount)
                    )
                    transfer.nextProgressByteCount = transfer.data.count + 64 * 1_024
                }
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
        } else if let progressValue {
            progress?(progressValue)
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
        if let expectedByteCount = transfer.policy.expectedByteCount,
           transfer.data.count != expectedByteCount {
            transfer.continuation.resume(
                throwing: HomebrewCatalogNetworkError.byteCountMismatch
            )
            return
        }
        if let advertisedByteCount = transfer.advertisedByteCount,
           !transfer.hasContentEncoding,
           transfer.data.count != Int(advertisedByteCount) {
            transfer.continuation.resume(
                throwing: HomebrewCatalogNetworkError.byteCountMismatch
            )
            return
        }
        transfer.policy.progress?(1)
        transfer.continuation.resume(returning: transfer.data)
    }

    private func removeTransfer(for taskIdentifier: Int) -> Transfer? {
        lock.lock()
        let transfer = transfers.removeValue(forKey: taskIdentifier)
        lock.unlock()
        return transfer
    }
}

struct HomebrewCatalogClient: Sendable {
    static let catalogURL = URL(
        string: "https://raw.githubusercontent.com/RegionallyFamous/swansong-story-forge/main/distribution/catalog-v1.json"
    )!
    static let signatureURL = URL(
        string: "https://raw.githubusercontent.com/RegionallyFamous/swansong-story-forge/main/distribution/catalog-v1.sig.json"
    )!

    private static let maximumCatalogBytes = 1_024 * 1_024
    private static let maximumSignatureBytes = 8 * 1_024
    private static let trustedRedirectHosts: Set<String> = [
        "github.com",
        "raw.githubusercontent.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    private let sourceURL: URL
    private let detachedSignatureURL: URL
    private let session: URLSession
    private let downloadDelegate: HomebrewDownloadDelegate
    private let trustsCatalogSource: @Sendable (URL) -> Bool
    private let trustsAssetSource: @Sendable (URL) -> Bool

    init(sourceURL: URL = Self.catalogURL) {
        let configuration = URLSessionConfiguration.ephemeral
        Self.harden(configuration)
        self.init(
            sourceURL: sourceURL,
            signatureURL: sourceURL == Self.catalogURL
                ? Self.signatureURL
                : Self.detachedSignatureURL(for: sourceURL),
            configuration: configuration,
            trustsCatalogSource: Self.isTrustedCatalogSource,
            trustsAssetSource: Self.isTrustedAssetSource,
            trustsRedirect: Self.isTrustedRedirect
        )
    }

    #if SWAN_SONG_AUTOMATION
    /// Test-only transport injection. Release builds expose only the pinned
    /// first-party initializer above.
    init(
        testSourceURL: URL,
        sessionConfiguration: URLSessionConfiguration,
        trustsSource: @escaping @Sendable (URL) -> Bool
    ) {
        Self.harden(sessionConfiguration)
        self.init(
            sourceURL: testSourceURL,
            signatureURL: Self.detachedSignatureURL(for: testSourceURL),
            configuration: sessionConfiguration,
            trustsCatalogSource: trustsSource,
            trustsAssetSource: trustsSource,
            trustsRedirect: trustsSource
        )
    }
    #endif

    private init(
        sourceURL: URL,
        signatureURL: URL,
        configuration: URLSessionConfiguration,
        trustsCatalogSource: @escaping @Sendable (URL) -> Bool,
        trustsAssetSource: @escaping @Sendable (URL) -> Bool,
        trustsRedirect: @escaping @Sendable (URL) -> Bool
    ) {
        self.sourceURL = sourceURL
        self.detachedSignatureURL = signatureURL
        self.trustsCatalogSource = trustsCatalogSource
        self.trustsAssetSource = trustsAssetSource
        let delegate = HomebrewDownloadDelegate(
            trustsRedirect: trustsRedirect
        )
        self.downloadDelegate = delegate
        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    private static func harden(_ configuration: URLSessionConfiguration) {
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
    }

    var catalogSourceURL: URL { sourceURL }
    var catalogSignatureSourceURL: URL { detachedSignatureURL }

    func fetchCatalogBundle() async throws -> HomebrewCatalogWireBundle {
        guard trustsCatalogSource(sourceURL),
              trustsCatalogSource(detachedSignatureURL) else {
            throw HomebrewCatalogNetworkError.invalidSource
        }
        let catalogData = try await boundedData(
            at: sourceURL,
            maximumByteCount: Self.maximumCatalogBytes,
            expectedByteCount: nil,
            progress: nil
        )
        let signatureData = try await boundedData(
            at: detachedSignatureURL,
            maximumByteCount: Self.maximumSignatureBytes,
            expectedByteCount: nil,
            progress: nil
        )
        return HomebrewCatalogWireBundle(
            catalogData: catalogData,
            signatureData: signatureData
        )
    }

    func fetchAsset(
        _ asset: HomebrewCatalogAsset,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        guard trustsAssetSource(asset.url) else {
            throw HomebrewCatalogNetworkError.invalidSource
        }
        guard asset.byteCount > 0 else {
            throw HomebrewCatalogNetworkError.byteCountMismatch
        }
        guard asset.byteCount <= GameROMValidationPolicy.maximumByteCount else {
            throw HomebrewCatalogNetworkError.responseTooLarge
        }
        guard Self.allowedAssetExtensions.contains(asset.fileExtension),
              asset.url.pathExtension == asset.fileExtension else {
            throw HomebrewCatalogNetworkError.invalidSource
        }
        return try await boundedData(
            at: asset.url,
            maximumByteCount: GameROMValidationPolicy.maximumByteCount,
            expectedByteCount: asset.byteCount,
            progress: progress
        )
    }

    private func boundedData(
        at url: URL,
        maximumByteCount: Int,
        expectedByteCount: Int?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, application/octet-stream;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("SwanSong-Homebrew-Catalog/1", forHTTPHeaderField: "User-Agent")

        return try await downloadDelegate.data(
            for: request,
            using: session,
            policy: HomebrewDownloadPolicy(
                maximumByteCount: maximumByteCount,
                expectedByteCount: expectedByteCount,
                progress: progress
            )
        )
    }

    private static func isTrustedCatalogSource(_ url: URL) -> Bool {
        guard let components = safeHTTPSComponents(url),
              components.host?.lowercased() == "raw.githubusercontent.com",
              [
                  "/RegionallyFamous/swansong-story-forge/main/distribution/catalog-v1.json",
                  "/RegionallyFamous/swansong-story-forge/main/distribution/catalog-v1.sig.json",
              ].contains(components.percentEncodedPath) else {
            return false
        }
        return true
    }

    private static func detachedSignatureURL(for catalogURL: URL) -> URL {
        catalogURL.deletingLastPathComponent().appendingPathComponent(
            "catalog-v1.sig.json"
        )
    }

    private static func isTrustedAssetSource(_ url: URL) -> Bool {
        guard let components = safeHTTPSComponents(url),
              components.host?.lowercased() == "github.com",
              let segments = strictPathSegments(components.percentEncodedPath),
              segments.count == 6,
              segments[0] == "RegionallyFamous",
              segments[1] == "swansong-story-forge",
              segments[2] == "releases",
              segments[3] == "download",
              !segments[4].isEmpty,
              !segments[5].isEmpty,
              allowedAssetExtensions.contains(url.pathExtension) else {
            return false
        }
        return true
    }

    private static let allowedAssetExtensions: Set<String> = [
        "ws", "wsc", "pc2", "pcv2",
    ]

    #if SWAN_SONG_AUTOMATION
    static func productionTrustsAssetSourceForTesting(_ url: URL) -> Bool {
        isTrustedAssetSource(url)
    }

    static func productionTrustsRedirectForTesting(_ url: URL) -> Bool {
        isTrustedRedirect(url)
    }
    #endif

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
}
