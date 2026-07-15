import Foundation

public struct GameImportPlan: Sendable {
    public let files: [URL]
    public let unsupportedFiles: [URL]
    public let duplicateCount: Int

    public init(files: [URL], unsupportedFiles: [URL], duplicateCount: Int) {
        self.files = files
        self.unsupportedFiles = unsupportedFiles
        self.duplicateCount = duplicateCount
    }
}

public struct GameImportFailure: Equatable, Sendable {
    public let fileName: String
    public let reason: String

    public init(fileName: String, reason: String) {
        self.fileName = fileName
        self.reason = reason
    }
}

public struct GameImportBatchResult: Sendable {
    public let games: [GameRecord]
    public let importedGameIDs: [GameRecord.ID]
    public let addedCount: Int
    public let updatedCount: Int
    public let duplicateCount: Int
    public let failures: [GameImportFailure]
    public let createdManagedReferences: [ManagedGameReference]

    public init(
        games: [GameRecord],
        importedGameIDs: [GameRecord.ID],
        addedCount: Int,
        updatedCount: Int,
        duplicateCount: Int,
        failures: [GameImportFailure],
        createdManagedReferences: [ManagedGameReference] = []
    ) {
        self.games = games
        self.importedGameIDs = importedGameIDs
        self.addedCount = addedCount
        self.updatedCount = updatedCount
        self.duplicateCount = duplicateCount
        self.failures = failures
        self.createdManagedReferences = createdManagedReferences
    }

    public var successCount: Int { addedCount + updatedCount }
}

public struct GameImportPlanner: Sendable {
    public init() {}

    public func plan(_ urls: [URL]) -> GameImportPlan {
        var unique: [URL] = []
        var seen = Set<String>()
        var duplicateCount = 0

        for url in urls {
            let normalized = Self.normalizedURL(url)
            let identity = Self.identity(for: normalized)
            guard seen.insert(identity).inserted else {
                duplicateCount += 1
                continue
            }
            unique.append(normalized)
        }

        unique.sort(by: Self.orderedBefore)
        return GameImportPlan(
            files: unique.filter(Self.isSupportedGameFile),
            unsupportedFiles: unique.filter { !Self.isSupportedGameFile($0) },
            duplicateCount: duplicateCount
        )
    }

    public func files(
        in folderURL: URL,
        recursively: Bool = true,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let folder = Self.normalizedURL(folderURL)
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let urls: [URL]
        if recursively {
            guard let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw CocoaError(.fileReadUnknown)
            }
            var discovered: [URL] = []
            while let candidate = enumerator.nextObject() as? URL {
                let resourceValues = try? candidate.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ])
                if resourceValues?.isDirectory == true {
                    if resourceValues?.isSymbolicLink == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if resourceValues?.isRegularFile == true,
                   Self.isSupportedGameFile(candidate) {
                    discovered.append(candidate)
                }
            }
            urls = discovered
        } else {
            urls = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ).filter { candidate in
                let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && Self.isSupportedGameFile(candidate)
            }
        }

        return plan(urls).files
    }

    public static func isSupportedGameFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "ws", "wsc", "pc2", "pcv2", "zip": true
        default: false
        }
    }

    public static func normalizedURL(_ url: URL) -> URL {
        // Preserve the submitted path so the importer can still detect and
        // reject symbolic links during its regular-file preflight.
        url.standardizedFileURL
    }

    public static func identity(for url: URL) -> String {
        let normalized = normalizedURL(url)
        // Path identity is intentionally used before preflight. Asking the file
        // system for a resource identifier follows symbolic links and can let a
        // rejected link suppress a safe source selected in the same batch.
        return "path:\(normalized.path.precomposedStringWithCanonicalMapping)"
    }

    private static func orderedBefore(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = lhs.path.precomposedStringWithCanonicalMapping
        let right = rhs.path.precomposedStringWithCanonicalMapping
        let order = left.compare(
            right,
            options: [.caseInsensitive, .numeric],
            range: nil,
            locale: Locale(identifier: "en_US_POSIX")
        )
        return order == .orderedSame ? left < right : order == .orderedAscending
    }
}

public struct GameBatchImporter: Sendable {
    private let planner: GameImportPlanner
    private let managedStore: ManagedGameStore

    public init(
        planner: GameImportPlanner = GameImportPlanner(),
        managedStore: ManagedGameStore = .defaultStore()
    ) {
        self.planner = planner
        self.managedStore = managedStore
    }

    public func importFiles(
        _ urls: [URL],
        into existingGames: [GameRecord]
    ) -> GameImportBatchResult {
        let plan = planner.plan(urls)
        var games = existingGames
        var idsByIdentity: [String: Int] = [:]
        var idsByDigest: [String: Int] = [:]
        for (index, game) in games.enumerated() {
            let identity = GameImportPlanner.identity(for: game.fileURL)
            if idsByIdentity[identity] == nil {
                idsByIdentity[identity] = index
            }
            if let digest = game.managedROM?.sha256 {
                let contentIdentity = Self.contentIdentity(
                    sha256: digest,
                    hardwareModel: game.resolvedHardwareModel
                )
                if idsByDigest[contentIdentity] == nil {
                    idsByDigest[contentIdentity] = index
                }
            }
        }

        var addedCount = 0
        var updatedCount = 0
        var importedGameIDs: [GameRecord.ID] = []
        var createdManagedReferences = Set<ManagedGameReference>()
        var importedDigests = Set<String>()
        var contentDuplicateCount = 0
        var failures = plan.unsupportedFiles.map {
            GameImportFailure(
                fileName: $0.lastPathComponent,
                reason: "Choose a .ws, .wsc, .pc2, .pcv2, or ZIP containing one game."
            )
        }

        for url in plan.files {
            do {
                let image = try LibraryGameImageImporter.image(from: url)
                let installed = try managedStore.install(image)
                if installed.created { createdManagedReferences.insert(installed.reference) }

                let contentIdentity = Self.contentIdentity(
                    sha256: image.sha256,
                    hardwareModel: image.hardwareModel
                )
                guard importedDigests.insert(contentIdentity).inserted else {
                    contentDuplicateCount += 1
                    continue
                }
                let sourceIdentity = GameImportPlanner.identity(for: url)
                if let index = idsByDigest[contentIdentity]
                    ?? idsByIdentity[sourceIdentity] {
                    // Preserve the stable identity, title, favorite, timestamps,
                    // saves, states, and artwork while adopting the private copy.
                    games[index].fileURL = installed.fileURL
                    games[index].metadata = image.metadata
                    games[index].managedROM = installed.reference
                    games[index].preferredHardwareModel = image.hardwareModel
                    if games[index].sourceFileName == nil {
                        games[index].sourceFileName = image.sourceFileName
                    }
                    idsByDigest[contentIdentity] = index
                    importedGameIDs.append(games[index].id)
                    updatedCount += 1
                } else {
                    let imported = GameRecord(
                        title: image.suggestedTitle,
                        fileURL: installed.fileURL,
                        metadata: image.metadata,
                        managedROM: installed.reference,
                        sourceFileName: image.sourceFileName,
                        preferredHardwareModel: image.hardwareModel
                    )
                    games.append(imported)
                    idsByDigest[contentIdentity] = games.count - 1
                    importedGameIDs.append(imported.id)
                    addedCount += 1
                }
            } catch {
                failures.append(
                    GameImportFailure(
                        fileName: url.lastPathComponent,
                        reason: Self.failureReason(for: error)
                    )
                )
            }
        }

        return GameImportBatchResult(
            games: games,
            importedGameIDs: importedGameIDs,
            addedCount: addedCount,
            updatedCount: updatedCount,
            duplicateCount: plan.duplicateCount + contentDuplicateCount,
            failures: failures,
            createdManagedReferences: Array(createdManagedReferences)
        )
    }

    private static func contentIdentity(
        sha256: String,
        hardwareModel: EngineHardwareModel
    ) -> String {
        "\(hardwareModel.rawValue):\(sha256.lowercased())"
    }

    private static func failureReason(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        if let engineError = error as? SwanEngineError {
            return engineError.detail
        }
        if let cocoaError = error as? CocoaError {
            switch cocoaError.code {
            case .fileReadNoSuchFile:
                return "The file could not be found."
            case .fileReadNoPermission:
                return "SwanSong does not have permission to read this file."
            case .fileReadUnsupportedScheme:
                return "Choose a .ws, .wsc, .pc2, .pcv2, or ZIP containing one game."
            default:
                return "The file could not be read."
            }
        }
        return "The file could not be inspected."
    }
}
