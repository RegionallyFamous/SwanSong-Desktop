import Foundation

public enum SwanSongDataRootSource: Equatable, Sendable {
    case defaultLocation
    case environmentOverride
    case rejectedBundleContainedOverride
}

public struct SwanSongDataRootResolution: Equatable, Sendable {
    public let rootURL: URL
    public let source: SwanSongDataRootSource

    public init(rootURL: URL, source: SwanSongDataRootSource) {
        self.rootURL = rootURL.standardizedFileURL
        self.source = source
    }
}

/// Resolves SwanSong's shared data root without allowing an environment
/// override to redirect mutable data into the signed application bundle.
public enum SwanSongDataRootPolicy {
    public static let environmentKey = "SWAN_SONG_DATA_DIR"

    public static func defaultResolution(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL
    ) -> SwanSongDataRootResolution {
        let applicationSupportRoot = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        let fallbackRoot = applicationSupportRoot.appendingPathComponent(
            "SwanSong",
            isDirectory: true
        )
        let requestedRoot = environment[environmentKey].flatMap { path -> URL? in
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return resolve(
            requestedRoot: requestedRoot,
            bundleURL: bundleURL,
            fallbackRoot: fallbackRoot,
            fileManager: fileManager
        )
    }

    /// Pure policy entry point with injectable paths for diagnostics and checks.
    /// This function never creates or changes anything on disk.
    public static func resolve(
        requestedRoot: URL?,
        bundleURL: URL,
        fallbackRoot: URL,
        fileManager: FileManager = .default
    ) -> SwanSongDataRootResolution {
        let fallbackRoot = fallbackRoot.standardizedFileURL
        guard let requestedRoot else {
            return SwanSongDataRootResolution(
                rootURL: fallbackRoot,
                source: .defaultLocation
            )
        }

        let standardizedRequestedRoot = requestedRoot.standardizedFileURL
        let standardizedBundleURL = bundleURL.standardizedFileURL
        let lexicallyContained = isEqualOrDescendant(
            standardizedRequestedRoot,
            of: standardizedBundleURL
        )
        let resolvedContained = isEqualOrDescendant(
            canonicalized(standardizedRequestedRoot, fileManager: fileManager),
            of: canonicalized(standardizedBundleURL, fileManager: fileManager)
        )
        guard !lexicallyContained, !resolvedContained else {
            return SwanSongDataRootResolution(
                rootURL: fallbackRoot,
                source: .rejectedBundleContainedOverride
            )
        }

        return SwanSongDataRootResolution(
            rootURL: standardizedRequestedRoot,
            source: .environmentOverride
        )
    }

    private static func canonicalized(
        _ url: URL,
        fileManager: FileManager
    ) -> URL {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []

        while existingAncestor.path != "/",
              !fileManager.fileExists(atPath: existingAncestor.path) {
            missingComponents.append(existingAncestor.lastPathComponent)
            existingAncestor.deleteLastPathComponent()
        }

        var resolved = existingAncestor
            .resolvingSymlinksInPath()
            .standardizedFileURL
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }

    private static func isEqualOrDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }
}
