import CryptoKit
import Darwin
import Foundation

public enum TranslationROMRole: String, CaseIterable, Codable, Sendable {
    case original
    case patched

    public var title: String {
        switch self {
        case .original: "Original"
        case .patched: "Patched"
        }
    }
}

public enum TranslationLabError: LocalizedError, Equatable, Sendable {
    case invalidProject(String)
    case toolkitNotFound
    case unsafePath(String)
    case missingROM(TranslationROMRole)
    case nodeUnavailable
    case invalidRoute(String)
    case noRecordedFrames

    public var errorDescription: String? {
        switch self {
        case let .invalidProject(detail):
            "That folder is not a valid translation project: \(detail)"
        case .toolkitNotFound:
            "The WonderSwan translation toolkit could not be found above this project."
        case let .unsafePath(path):
            "The translation lab refused an unsafe path: \(path)"
        case let .missingROM(role):
            "The project does not currently contain its \(role.title.lowercased()) ROM."
        case .nodeUnavailable:
            "Node.js could not be found. Set WONDERSWAN_NODE or install Node before running toolkit stages."
        case let .invalidRoute(detail):
            "The recorded input route is invalid: \(detail)"
        case .noRecordedFrames:
            "No emulated frames were recorded."
        }
    }
}

public struct TranslationProject: Codable, Hashable, Identifiable, Sendable {
    public let rootURL: URL
    public let toolkitURL: URL
    public let title: String
    public let platform: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let originalROMURL: URL
    public let patchedROMURL: URL

    public var id: String { rootURL.path }
    public var slug: String { rootURL.lastPathComponent }
    public var routeHardwareModel: TranslationRouteHardwareModel {
        get throws {
            try TranslationRouteHardwareModel(projectPlatform: platform)
        }
    }
    public var firmwareKind: WonderSwanFirmwareKind {
        get throws {
            try routeHardwareModel.firmwareKind
        }
    }

    public init(projectDirectory: URL) throws {
        let selected = projectDirectory.standardizedFileURL
        let selectedValues = try? selected.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard selectedValues?.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(selected.path)
        }
        let unresolvedRoot = selectedValues?.isDirectory == true
            ? selected
            : selected.deletingLastPathComponent()
        let root = unresolvedRoot.resolvingSymlinksInPath().standardizedFileURL
        let configURL = root.appendingPathComponent("project.json", isDirectory: false)
        let values = try configURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw TranslationLabError.invalidProject("project.json is missing or is not a regular file")
        }

        let config: ProjectConfiguration
        do {
            config = try JSONDecoder().decode(
                ProjectConfiguration.self,
                from: Data(contentsOf: configURL)
            )
        } catch {
            throw TranslationLabError.invalidProject(error.localizedDescription)
        }
        guard !config.game.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationLabError.invalidProject("the game title is empty")
        }

        let toolkit = try Self.findToolkit(startingAt: root)
        self.rootURL = root
        self.toolkitURL = toolkit
        self.title = config.game.title
        self.platform = config.game.platform
        self.sourceLanguage = config.game.sourceLanguage
        self.targetLanguage = config.game.targetLanguage
        self.originalROMURL = try Self.resolveProjectPath(config.rom.original, root: root)
        self.patchedROMURL = try Self.resolveProjectPath(config.rom.patched, root: root)
    }

    public static func discover(at selectedURL: URL) throws -> [TranslationProject] {
        let unresolved = selectedURL.standardizedFileURL
        let fileManager = FileManager.default
        let values = try unresolved.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(unresolved.path)
        }
        let selected = unresolved.resolvingSymlinksInPath().standardizedFileURL
        if values.isRegularFile == true, selected.lastPathComponent == "project.json" {
            return [try TranslationProject(projectDirectory: selected.deletingLastPathComponent())]
        }
        guard values.isDirectory == true else {
            throw TranslationLabError.invalidProject("choose a project or toolkit folder")
        }
        if fileManager.fileExists(
            atPath: selected.appendingPathComponent("project.json").path
        ) {
            return [try TranslationProject(projectDirectory: selected)]
        }

        let projectsDirectory: URL
        if selected.lastPathComponent == "projects" {
            projectsDirectory = selected
        } else {
            projectsDirectory = selected.appendingPathComponent("projects", isDirectory: true)
        }
        let projectsValues = try? projectsDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard projectsValues?.isDirectory == true, projectsValues?.isSymbolicLink != true else {
            throw TranslationLabError.invalidProject(
                "no project.json or projects directory was found"
            )
        }

        let candidates = try fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var projects: [TranslationProject] = []
        for candidate in candidates {
            let candidateValues = try candidate.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard candidateValues.isDirectory == true, candidateValues.isSymbolicLink != true else {
                continue
            }
            guard fileManager.fileExists(
                atPath: candidate.appendingPathComponent("project.json").path
            ) else { continue }
            if let project = try? TranslationProject(projectDirectory: candidate) {
                projects.append(project)
            }
        }
        guard !projects.isEmpty else {
            throw TranslationLabError.invalidProject("the toolkit contains no readable projects")
        }
        return projects.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public func romURL(for role: TranslationROMRole) throws -> URL {
        let url = role == .original ? originalROMURL : patchedROMURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolved) else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let values = try? resolved.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw TranslationLabError.missingROM(role)
        }
        return resolved
    }

    public func contains(_ url: URL) -> Bool {
        Self.isDescendant(url.standardizedFileURL, of: rootURL)
    }

    public func relativePath(for url: URL) throws -> String {
        let standardized = url.standardizedFileURL
        guard contains(standardized) else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        return String(standardized.path.dropFirst(prefix.count))
    }

    private static func resolveProjectPath(_ path: String, root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else {
            throw TranslationLabError.unsafePath(path)
        }
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        guard isDescendant(candidate, of: root) else {
            throw TranslationLabError.unsafePath(path)
        }
        return candidate
    }

    private static func findToolkit(startingAt project: URL) throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["WONDERSWAN_TOOLKIT_DIR"],
           !configured.isEmpty {
            let candidate = URL(fileURLWithPath: configured, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            if isToolkit(candidate), isDescendant(project, of: candidate) {
                return candidate
            }
        }

        var candidate = project
        while true {
            if isToolkit(candidate) { return candidate }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
        throw TranslationLabError.toolkitNotFound
    }

    private static func isToolkit(_ url: URL) -> Bool {
        let cli = url.appendingPathComponent("bin/wstrans.mjs", isDirectory: false)
        let values = try? cli.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    private static func isDescendant(_ child: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }
}

public struct TranslationWorkspaceDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var projectPaths: [String]
    public var selectedProjectPath: String?

    public init(
        schemaVersion: Int = 1,
        projectPaths: [String] = [],
        selectedProjectPath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.projectPaths = projectPaths
        self.selectedProjectPath = selectedProjectPath
    }
}

public struct TranslationWorkspaceStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let root = SwanSongDataRootPolicy.defaultResolution(fileManager: fileManager).rootURL
        return Self(
            fileURL: root
                .appendingPathComponent("TranslationWorkspace.json")
        )
    }

    public func load() throws -> TranslationWorkspaceDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TranslationWorkspaceDocument()
        }
        let document = try JSONDecoder().decode(
            TranslationWorkspaceDocument.self,
            from: Data(contentsOf: fileURL)
        )
        guard document.schemaVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }

    public func save(_ document: TranslationWorkspaceDocument) throws {
        guard document.schemaVersion == 1 else {
            throw CocoaError(.fileWriteUnknown)
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private struct ProjectConfiguration: Decodable {
    struct Game: Decodable {
        let title: String
        let platform: String
        let sourceLanguage: String
        let targetLanguage: String
    }

    struct ROM: Decodable {
        let original: String
        let patched: String
    }

    let game: Game
    let rom: ROM
}

public enum TranslationReadinessStatus: String, Codable, Sendable {
    case complete = "COMPLETE"
    case pending = "PENDING"
    case blocked = "BLOCKED"
    case unknown = "UNKNOWN"
}

public struct TranslationCorpusMetrics: Codable, Equatable, Sendable {
    public let extracted: Int
    public let translated: Int
    public let tableEntries: Int
    public let fixedExtractors: Int
    public let pointerExtractors: Int

    public var translationFraction: Double {
        guard extracted > 0 else { return 0 }
        return min(Double(translated) / Double(extracted), 1)
    }
}

public struct TranslationReadinessPhase: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let status: TranslationReadinessStatus
    public let detail: String
    public let nextCommand: String?

    public var id: String { name }
}

public enum TranslationActionPriority: String, Codable, Sendable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case unknown = "UNKNOWN"
}

public struct TranslationNextAction: Codable, Equatable, Identifiable, Sendable {
    public let priority: TranslationActionPriority
    public let detail: String
    public let command: String?

    public var id: String { "\(priority.rawValue):\(detail)" }
}

public struct TranslationReadiness: Codable, Equatable, Sendable {
    public let status: TranslationReadinessStatus
    public let headline: String
    public let output: String
    public let metrics: TranslationCorpusMetrics?
    public let phases: [TranslationReadinessPhase]
    public let nextActions: [TranslationNextAction]

    public var completionFraction: Double {
        guard !phases.isEmpty else { return 0 }
        return Double(phases.filter { $0.status == .complete }.count) / Double(phases.count)
    }

    public init(output: String) {
        self.output = output
        let line = output.split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first { $0.hasPrefix("Readiness: ") }
        guard let line else {
            status = .unknown
            headline = "Readiness has not been checked"
            metrics = nil
            phases = []
            nextActions = []
            return
        }
        let remainder = String(line.dropFirst("Readiness: ".count))
        let token = remainder.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        status = TranslationReadinessStatus(rawValue: token) ?? .unknown
        headline = remainder
        metrics = Self.parseMetrics(lines: output.split(whereSeparator: \Character.isNewline).map(String.init))
        phases = Self.parsePhases(lines: output.split(whereSeparator: \Character.isNewline).map(String.init))
        nextActions = Self.parseNextActions(lines: output.split(whereSeparator: \Character.isNewline).map(String.init))
    }

    private static func parseMetrics(lines: [String]) -> TranslationCorpusMetrics? {
        guard let line = lines.first(where: { $0.hasPrefix("Strings: ") }) else { return nil }
        let pattern = #"^Strings: ([0-9]+) extracted, ([0-9]+) translated; table entries: ([0-9]+); extractors: ([0-9]+) fixed, ([0-9]+) pointer$"#
        guard let values = captures(pattern: pattern, text: line), values.count == 5 else {
            return nil
        }
        let numbers = values.compactMap(Int.init)
        guard numbers.count == 5 else { return nil }
        return TranslationCorpusMetrics(
            extracted: numbers[0],
            translated: numbers[1],
            tableEntries: numbers[2],
            fixedExtractors: numbers[3],
            pointerExtractors: numbers[4]
        )
    }

    private static func parsePhases(lines: [String]) -> [TranslationReadinessPhase] {
        let pattern = #"^(COMPLETE|PENDING|BLOCKED) ([^:]+): (.+)$"#
        var phases: [TranslationReadinessPhase] = []
        for line in lines {
            if line.hasPrefix("  Next: "), !phases.isEmpty {
                let previous = phases.removeLast()
                phases.append(
                    TranslationReadinessPhase(
                        name: previous.name,
                        status: previous.status,
                        detail: previous.detail,
                        nextCommand: String(line.dropFirst("  Next: ".count))
                    )
                )
                continue
            }
            guard let values = captures(pattern: pattern, text: line), values.count == 3 else {
                continue
            }
            phases.append(
                TranslationReadinessPhase(
                    name: values[1],
                    status: TranslationReadinessStatus(rawValue: values[0]) ?? .unknown,
                    detail: values[2],
                    nextCommand: nil
                )
            )
        }
        return phases
    }

    private static func parseNextActions(lines: [String]) -> [TranslationNextAction] {
        guard let start = lines.firstIndex(of: "Next actions:") else { return [] }
        let pattern = #"^- ([A-Z]+): (.+)$"#
        var actions: [TranslationNextAction] = []
        for line in lines.dropFirst(start + 1) {
            if line.hasPrefix("  "), !actions.isEmpty {
                let previous = actions.removeLast()
                actions.append(
                    TranslationNextAction(
                        priority: previous.priority,
                        detail: previous.detail,
                        command: line.trimmingCharacters(in: .whitespaces)
                    )
                )
                continue
            }
            guard let values = captures(pattern: pattern, text: line), values.count == 2 else {
                continue
            }
            actions.append(
                TranslationNextAction(
                    priority: TranslationActionPriority(rawValue: values[0]) ?? .unknown,
                    detail: values[1],
                    command: nil
                )
            )
        }
        return actions
    }

    private static func captures(pattern: String, text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}

public enum TranslationToolkitStage: Sendable {
    case status
    case qa
    case validate
    case packStrict
    case captureIntake(ramURL: URL, name: String)

    public var title: String {
        switch self {
        case .status: "Refresh Status"
        case .qa: "Translation QA"
        case .validate: "Validate Project"
        case .packStrict: "Strict Pack"
        case .captureIntake: "Register Runtime Capture"
        }
    }

    fileprivate func arguments(project: TranslationProject) throws -> [String] {
        let projectPath = project.rootURL.path
        switch self {
        case .status:
            return ["status", projectPath]
        case .qa:
            return ["qa", projectPath]
        case .validate:
            return ["validate", projectPath]
        case .packStrict:
            return ["pack", projectPath, "--strict", "true"]
        case let .captureIntake(ramURL, requestedName):
            guard project.contains(ramURL) else {
                throw TranslationLabError.unsafePath(ramURL.path)
            }
            let name = Self.safeName(requestedName)
            return [
                "capture-intake", projectPath,
                "--ram", ramURL.path,
                "--name", name,
                "--expect-size", "auto",
            ]
        }
    }

    private static func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "swan-song-capture" : String(result.prefix(80))
    }
}

public struct TranslationCommandResult: Codable, Equatable, Sendable {
    public let stageTitle: String
    public let exitCode: Int32
    public let output: String
    public let startedAt: Date
    public let finishedAt: Date

    public var succeeded: Bool { exitCode == 0 }
}

public enum TranslationToolkitRunner {
    public static func run(
        _ stage: TranslationToolkitStage,
        project: TranslationProject
    ) throws -> TranslationCommandResult {
        let startedAt = Date()
        let nodeURL = try findNode()
        let cliURL = project.toolkitURL.appendingPathComponent("bin/wstrans.mjs")
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [cliURL.path] + (try stage.arguments(project: project))
        process.currentDirectoryURL = project.toolkitURL
        var environment = ProcessInfo.processInfo.environment
        environment["WONDERSWAN_TOOLKIT_DIR"] = project.toolkitURL.path
        let usefulPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (usefulPaths + [currentPath]).joined(separator: ":")
        process.environment = environment

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-Translation-Command-\(UUID().uuidString).log"
        )
        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        try process.run()
        process.waitUntilExit()
        try outputHandle.synchronize()
        try outputHandle.close()

        let maximumBytes = 512 * 1024
        let inputHandle = try FileHandle(forReadingFrom: outputURL)
        defer { try? inputHandle.close() }
        let byteCount = try inputHandle.seekToEnd()
        let retainedByteCount = min(byteCount, UInt64(maximumBytes))
        try inputHandle.seek(toOffset: byteCount - retainedByteCount)
        let retained = try inputHandle.read(upToCount: Int(retainedByteCount)) ?? Data()
        let output = String(decoding: retained, as: UTF8.self)
        return TranslationCommandResult(
            stageTitle: stage.title,
            exitCode: process.terminationStatus,
            output: output,
            startedAt: startedAt,
            finishedAt: Date()
        )
    }

    private static func findNode() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let configured = environment["WONDERSWAN_NODE"], !configured.isEmpty {
            candidates.append(configured)
        }
        candidates += [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/node" }
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw TranslationLabError.nodeUnavailable
    }
}

public struct TranslationRouteEvent: Codable, Equatable, Sendable {
    public let frameIndex: UInt64
    public let inputMask: UInt32

    public init(frameIndex: UInt64, inputMask: UInt32) {
        self.frameIndex = frameIndex
        self.inputMask = inputMask
    }
}

public struct TranslationArtifactDigest: Codable, Equatable, Sendable {
    public let byteCount: Int
    public let sha256: String

    public init(byteCount: Int, sha256: String) {
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public enum TranslationRouteHardwareModel: String, CaseIterable, Codable, Sendable {
    case wonderSwan = "wonderswan"
    case wonderSwanColor = "wonderswan-color"
    case swanCrystal = "swan-crystal"
    case pocketChallengeV2 = "pocket-challenge-v2"

    /// Resolves the human-readable platform value stored by translation
    /// toolkit projects without changing that value on disk.
    public init(projectPlatform: String) throws {
        let normalized = projectPlatform
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        switch normalized {
        case "wonderswan", "ws":
            self = .wonderSwan
        case "wonderswancolor", "wsc":
            self = .wonderSwanColor
        case "swancrystal":
            self = .swanCrystal
        case "pocketchallengev2", "pocketchallenge2", "pcv2", "pc2":
            self = .pocketChallengeV2
        default:
            throw TranslationLabError.invalidProject(
                "the platform \(projectPlatform) is not supported"
            )
        }
    }

    /// Converts a concrete engine selection into its stable route identity.
    /// Automatic selection cannot be recorded because it would not preserve
    /// the hardware used at clean power-on.
    public init(engineHardwareModel: EngineHardwareModel) throws {
        switch engineHardwareModel {
        case .automatic:
            throw TranslationLabError.invalidRoute(
                "automatic hardware selection cannot be recorded in a deterministic route"
            )
        case .wonderSwan:
            self = .wonderSwan
        case .wonderSwanColor:
            self = .wonderSwanColor
        case .swanCrystal:
            self = .swanCrystal
        case .pocketChallengeV2:
            self = .pocketChallengeV2
        }
    }

    public var engineHardwareModel: EngineHardwareModel {
        switch self {
        case .wonderSwan: .wonderSwan
        case .wonderSwanColor: .wonderSwanColor
        case .swanCrystal: .swanCrystal
        case .pocketChallengeV2: .pocketChallengeV2
        }
    }

    public var firmwareKind: WonderSwanFirmwareKind {
        switch self {
        case .wonderSwan: .monochrome
        case .wonderSwanColor, .swanCrystal: .color
        case .pocketChallengeV2: .pocketChallengeV2
        }
    }

    /// Semantic controls accepted in deterministic routes for this hardware.
    /// Pocket Challenge V2 uses its nine dedicated bits rather than aliases
    /// of the WonderSwan keypad, preserving every labeled key independently.
    public var semanticInputs: [EngineInput] {
        switch self {
        case .wonderSwan, .wonderSwanColor, .swanCrystal:
            [
                .y1, .y2, .y3, .y4,
                .x1, .x2, .x3, .x4,
                .b, .a, .start, .volume, .power,
            ]
        case .pocketChallengeV2:
            [
                .pocketChallengeUp,
                .pocketChallengeRight,
                .pocketChallengeDown,
                .pocketChallengeLeft,
                .pocketChallengePass,
                .pocketChallengeCircle,
                .pocketChallengeClear,
                .pocketChallengeView,
                .pocketChallengeEscape,
            ]
        }
    }

    public var validInputMask: UInt32 {
        semanticInputs.reduce(UInt32(0)) { $0 | $1.rawValue }
    }
}

public enum TranslationRouteFirmwareSource: String, Codable, Hashable, Sendable {
    case installed
    case openIPL = "open-ipl"
    /// Legacy spelling retained so existing automation routes remain readable.
    case syntheticAutomation = "synthetic-automation"
}

public struct TranslationRouteFirmware: Codable, Equatable, Sendable {
    public let source: TranslationRouteFirmwareSource
    public let image: TranslationArtifactDigest?
    public let identifier: String?

    public init(
        source: TranslationRouteFirmwareSource,
        image: TranslationArtifactDigest? = nil,
        identifier: String? = nil
    ) {
        self.source = source
        self.image = image
        self.identifier = identifier
    }

    fileprivate func validate() throws {
        switch source {
        case .installed:
            guard let image else {
                throw TranslationLabError.invalidRoute("the legacy startup image is missing its digest")
            }
            try validateDigest(image, label: "legacy startup image")
            guard identifier == nil else {
                throw TranslationLabError.invalidRoute("the legacy startup image has an unexpected identifier")
            }
            throw TranslationLabError.invalidRoute(
                "this route predates Open-IPL-only playback; re-record it with the current SwanSong Open IPL"
            )
        case .openIPL, .syntheticAutomation:
            guard image == nil, identifier == WonderSwanOpenIPL.identifier else {
                throw TranslationLabError.invalidRoute("open IPL identity is invalid")
            }
        }
    }

    public func isRuntimeEquivalent(to other: Self) -> Bool {
        if self == other { return true }
        let openSources: Set<TranslationRouteFirmwareSource> = [
            .openIPL,
            .syntheticAutomation,
        ]
        return openSources.contains(source)
            && openSources.contains(other.source)
            && image == nil
            && other.image == nil
            && identifier == WonderSwanOpenIPL.identifier
            && other.identifier == WonderSwanOpenIPL.identifier
    }
}

public struct TranslationRouteEngineIdentity: Codable, Equatable, Sendable {
    public let backend: String
    public let buildID: String

    public init(backend: String, buildID: String) {
        self.backend = backend
        self.buildID = buildID
    }
}

public enum TranslationRouteRTCMode: String, Codable, Equatable, Sendable {
    case deterministic = "deterministic"
}

public struct TranslationRouteRTCContext: Codable, Equatable, Sendable {
    /// The fixed UTC instant used by every Translation Lab clean boot.
    /// 2000-01-01T00:00:00Z keeps route execution independent of the Mac's
    /// clock while normal library play continues to use wall-clock time.
    public static let proofSeedUnixSeconds: UInt64 = 946_684_800
    public static let proofSeedUTC = "2000-01-01T00:00:00Z"
    public static let proof = Self(
        mode: .deterministic,
        seedUnixSeconds: proofSeedUnixSeconds
    )

    public let mode: TranslationRouteRTCMode
    public let seedUnixSeconds: UInt64

    public init(
        mode: TranslationRouteRTCMode,
        seedUnixSeconds: UInt64
    ) {
        self.mode = mode
        self.seedUnixSeconds = seedUnixSeconds
    }

    fileprivate func validate() throws {
        guard mode == .deterministic,
              seedUnixSeconds == Self.proofSeedUnixSeconds else {
            throw TranslationLabError.invalidRoute(
                "the route RTC policy must use deterministic UTC \(Self.proofSeedUTC) (Unix \(Self.proofSeedUnixSeconds))"
            )
        }
    }
}

public struct TranslationRouteStartContext: Codable, Equatable, Sendable {
    public static let cleanPowerOnKind = "clean-power-on"
    public static let isolatedPersistencePolicy = "isolated-empty-v1"

    public let kind: String
    public let hardwareModel: TranslationRouteHardwareModel
    public let firmware: TranslationRouteFirmware
    public let persistencePolicy: String
    public let engine: TranslationRouteEngineIdentity
    public let rtc: TranslationRouteRTCContext?

    public var engineHardwareModel: EngineHardwareModel {
        hardwareModel.engineHardwareModel
    }

    public var firmwareKind: WonderSwanFirmwareKind {
        hardwareModel.firmwareKind
    }

    public init(
        kind: String = Self.cleanPowerOnKind,
        hardwareModel: TranslationRouteHardwareModel,
        firmware: TranslationRouteFirmware,
        persistencePolicy: String = Self.isolatedPersistencePolicy,
        engine: TranslationRouteEngineIdentity,
        rtc: TranslationRouteRTCContext = .proof
    ) {
        self.kind = kind
        self.hardwareModel = hardwareModel
        self.firmware = firmware
        self.persistencePolicy = persistencePolicy
        self.engine = engine
        self.rtc = rtc
    }

    fileprivate func validate(requiresRTC: Bool = true) throws {
        guard kind == Self.cleanPowerOnKind else {
            throw TranslationLabError.invalidRoute("the route does not begin at a clean power-on")
        }
        try firmware.validate()
        if let image = firmware.image,
           image.byteCount != firmwareKind.expectedByteCount {
            throw TranslationLabError.invalidRoute(
                "the legacy startup image size does not match the recorded \(firmwareKind.title) system"
            )
        }
        guard persistencePolicy == Self.isolatedPersistencePolicy else {
            throw TranslationLabError.invalidRoute("the route persistence policy is unsupported")
        }
        guard engine.backend == "ares", !engine.buildID.isEmpty else {
            throw TranslationLabError.invalidRoute("the route engine identity is unsupported")
        }
        if requiresRTC {
            guard let rtc else {
                throw TranslationLabError.invalidRoute(
                    "the deterministic RTC mode and seed are missing"
                )
            }
            try rtc.validate()
        } else if let rtc {
            try rtc.validate()
        }
    }
}

public enum TranslationRouteFrameOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

public struct TranslationGameRasterDescriptor: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let orientation: TranslationRouteFrameOrientation

    public init(
        width: Int,
        height: Int,
        orientation: TranslationRouteFrameOrientation
    ) {
        self.width = width
        self.height = height
        self.orientation = orientation
    }
}

/// The packed BGRA pixels belonging to the emulated game display.
///
/// Engine-owned stride padding and the separate 13-pixel hardware indicator
/// rail are intentionally excluded.
public struct TranslationGameRaster: Equatable, Sendable {
    public let descriptor: TranslationGameRasterDescriptor
    public let bgra8888: Data

    public init(descriptor: TranslationGameRasterDescriptor, bgra8888: Data) {
        self.descriptor = descriptor
        self.bgra8888 = bgra8888
    }

    public func rgb888() throws -> Data {
        try FrameDifferential.rgb888FromBGRA(
            bgra8888,
            frameWidth: descriptor.width,
            frameHeight: descriptor.height,
            strideBytes: descriptor.width * 4,
            contentWidth: descriptor.width,
            contentHeight: descriptor.height
        )
    }
}

public struct TranslationRouteCheckpoint: Codable, Equatable, Sendable {
    public static let pixelEncoding = "bgra8888-game-content-v1"

    public let frameIndex: UInt64
    public let width: Int
    public let height: Int
    public let orientation: TranslationRouteFrameOrientation
    public let pixelEncoding: String
    public let sha256: String

    public init(
        frameIndex: UInt64,
        width: Int,
        height: Int,
        orientation: TranslationRouteFrameOrientation,
        pixelEncoding: String = Self.pixelEncoding,
        sha256: String
    ) {
        self.frameIndex = frameIndex
        self.width = width
        self.height = height
        self.orientation = orientation
        self.pixelEncoding = pixelEncoding
        self.sha256 = sha256
    }

    public init(frameIndex: UInt64, frame: EngineVideoFrame) throws {
        self.init(
            frameIndex: frameIndex,
            width: frame.width,
            height: frame.height,
            orientation: frame.isVertical ? .vertical : .horizontal,
            sha256: try Self.fingerprint(frame)
        )
    }

    public func matches(_ frame: EngineVideoFrame) -> Bool {
        width == frame.width
            && height == frame.height
            && orientation == (frame.isVertical ? .vertical : .horizontal)
            && (try? Self.fingerprint(frame)) == sha256
    }

    public static func canonicalGameRaster(
        _ frame: EngineVideoFrame
    ) throws -> TranslationGameRaster {
        let contentWidth = frame.isVertical ? min(frame.width, 144) : min(frame.width, 224)
        let contentHeight = frame.isVertical ? min(frame.height, 224) : min(frame.height, 144)
        let (visibleRowBytes, rowBytesOverflow) = contentWidth.multipliedReportingOverflow(by: 4)
        let (requiredByteCount, requiredByteCountOverflow) = frame.strideBytes
            .multipliedReportingOverflow(by: frame.height)
        guard frame.width > 0,
              frame.height > 0,
              contentWidth > 0,
              contentHeight > 0,
              !rowBytesOverflow,
              !requiredByteCountOverflow,
              frame.strideBytes >= visibleRowBytes,
              frame.pixels.count >= requiredByteCount else {
            throw TranslationLabError.invalidRoute("the route checkpoint frame is malformed")
        }
        var pixels = Data(capacity: visibleRowBytes * contentHeight)
        for row in 0..<contentHeight {
            let start = row * frame.strideBytes
            pixels.append(contentsOf: frame.pixels[start..<(start + visibleRowBytes)])
        }
        return TranslationGameRaster(
            descriptor: TranslationGameRasterDescriptor(
                width: contentWidth,
                height: contentHeight,
                orientation: frame.isVertical ? .vertical : .horizontal
            ),
            bgra8888: pixels
        )
    }

    public static func fingerprint(_ frame: EngineVideoFrame) throws -> String {
        let raster = try canonicalGameRaster(frame)
        var canonical = Data(
            "\(pixelEncoding)\u{0}\(frame.width)x\(frame.height)\u{0}\(raster.descriptor.width)x\(raster.descriptor.height)\u{0}".utf8
        )
        canonical.append(frame.isVertical ? 1 : 0)
        canonical.append(raster.bgra8888)
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate func validate(totalFrames: UInt64) throws {
        guard totalFrames > 0, frameIndex == totalFrames - 1 else {
            throw TranslationLabError.invalidRoute("the checkpoint is not the final route frame")
        }
        guard width > 0, height > 0, pixelEncoding == Self.pixelEncoding else {
            throw TranslationLabError.invalidRoute("the checkpoint image format is unsupported")
        }
        try validateSHA256(sha256, label: "checkpoint")
    }
}

public enum TranslationRouteProofEligibility: Equatable, Sendable {
    case proofReady
    case legacyStartUnknown
    case rtcStartUnknown
    case invalidV2(String)
    case invalidV3(String)

    public var issue: String? {
        switch self {
        case .proofReady:
            nil
        case .legacyStartUnknown:
            "Legacy v1 route — clean-power-on start state was not recorded. Re-record it; new routes also bind a fixed UTC RTC seed."
        case .rtcStartUnknown:
            "Route v2 — RTC mode and seed were not recorded. Re-record it with deterministic UTC \(TranslationRouteRTCContext.proofSeedUTC) (Unix \(TranslationRouteRTCContext.proofSeedUnixSeconds))."
        case let .invalidV2(issue):
            issue
        case let .invalidV3(issue):
            issue
        }
    }
}

public struct TranslationRoute: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-input-route-v3"
    public static let rtcUnboundSchema = "swan-song-input-route-v2"
    public static let legacySchema = "swan-song-input-route-v1"

    public let schema: String
    public let createdAt: Date
    public let recordedFrom: TranslationROMRole
    public let sourceROM: TranslationArtifactDigest
    public let start: TranslationRouteStartContext?
    public let totalFrames: UInt64
    public let events: [TranslationRouteEvent]
    public let checkpoint: TranslationRouteCheckpoint?
    private let decodingIssue: String?

    public var sourceROMSHA256: String { sourceROM.sha256 }
    public var proofEligibility: TranslationRouteProofEligibility {
        switch schema {
        case Self.currentSchema:
            do {
                try validateForProof()
                return .proofReady
            } catch {
                return .invalidV3(error.localizedDescription)
            }
        case Self.rtcUnboundSchema:
            do {
                try validateV2ForMigration()
                return .rtcStartUnknown
            } catch {
                return .invalidV2(error.localizedDescription)
            }
        case Self.legacySchema:
            return .legacyStartUnknown
        default:
            return .invalidV3("The recorded input route uses an unsupported schema.")
        }
    }
    public var targetFrameNumber: UInt64? { checkpoint.map { $0.frameIndex + 1 } }

    public init(
        createdAt: Date = Date(),
        recordedFrom: TranslationROMRole,
        sourceROM: TranslationArtifactDigest,
        start: TranslationRouteStartContext,
        totalFrames: UInt64,
        events: [TranslationRouteEvent],
        checkpoint: TranslationRouteCheckpoint
    ) throws {
        self.schema = Self.currentSchema
        self.createdAt = createdAt
        self.recordedFrom = recordedFrom
        self.sourceROM = sourceROM
        self.start = start
        self.totalFrames = totalFrames
        self.events = events
        self.checkpoint = checkpoint
        self.decodingIssue = nil
        try validateForProof()
    }

    public func input(at frameIndex: UInt64) -> EngineInput {
        guard frameIndex < totalFrames else { return [] }
        var mask: UInt32 = 0
        for event in events {
            if event.frameIndex > frameIndex { break }
            mask = event.inputMask
        }
        return EngineInput(rawValue: mask)
    }

    public func validate() throws {
        if let decodingIssue {
            throw TranslationLabError.invalidRoute(decodingIssue)
        }
        guard schema == Self.currentSchema
                || schema == Self.rtcUnboundSchema
                || schema == Self.legacySchema else {
            throw TranslationLabError.invalidRoute("unsupported schema")
        }
        guard totalFrames > 0 else {
            throw TranslationLabError.invalidRoute("the route contains no frames")
        }
        guard events.first?.frameIndex == 0 else {
            throw TranslationLabError.invalidRoute("the first input event must start at frame zero")
        }
        var previous: UInt64?
        var previousMask: UInt32?
        // v1 did not serialize its hardware selection and therefore retains
        // the original WonderSwan input contract. Newer routes bind their
        // semantic controls to the recorded clean-boot hardware.
        let validInputMask = start?.hardwareModel.validInputMask
            ?? TranslationRouteHardwareModel.wonderSwan.validInputMask
        for event in events {
            guard event.frameIndex < totalFrames else {
                throw TranslationLabError.invalidRoute("an input event is beyond the end of the route")
            }
            if let previous, event.frameIndex <= previous {
                throw TranslationLabError.invalidRoute("input events are not strictly ordered")
            }
            guard event.inputMask & ~validInputMask == 0 else {
                throw TranslationLabError.invalidRoute("an input event contains unsupported controls")
            }
            if let previousMask, previousMask == event.inputMask {
                throw TranslationLabError.invalidRoute("adjacent input events repeat the same controls")
            }
            previous = event.frameIndex
            previousMask = event.inputMask
        }
        if schema == Self.legacySchema {
            guard start == nil, checkpoint == nil else {
                throw TranslationLabError.invalidRoute("legacy route metadata is inconsistent")
            }
        }
    }

    public func validateForProof() throws {
        try validate()
        guard schema == Self.currentSchema else {
            throw TranslationLabError.invalidRoute(
                proofEligibility.issue ?? "the route is not eligible for deterministic replay"
            )
        }
        guard recordedFrom == .original else {
            throw TranslationLabError.invalidRoute("proof routes must be recorded from Original")
        }
        try validateDigest(sourceROM, label: "source ROM")
        guard let start else {
            throw TranslationLabError.invalidRoute("the route start context is missing")
        }
        try start.validate()
        guard let checkpoint else {
            throw TranslationLabError.invalidRoute("the route checkpoint is missing")
        }
        try checkpoint.validate(totalFrames: totalFrames)
    }

    private func validateV2ForMigration() throws {
        try validate()
        guard schema == Self.rtcUnboundSchema else {
            throw TranslationLabError.invalidRoute("the route is not a version 2 route")
        }
        guard recordedFrom == .original else {
            throw TranslationLabError.invalidRoute("version 2 proof routes must be recorded from Original")
        }
        try validateDigest(sourceROM, label: "source ROM")
        guard let start else {
            throw TranslationLabError.invalidRoute("the version 2 route start context is missing")
        }
        try start.validate(requiresRTC: false)
        guard let checkpoint else {
            throw TranslationLabError.invalidRoute("the version 2 route checkpoint is missing")
        }
        try checkpoint.validate(totalFrames: totalFrames)
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case createdAt
        case recordedFrom
        case sourceROM
        case sourceROMSHA256
        case start
        case totalFrames
        case events
        case checkpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        switch schema {
        case Self.currentSchema, Self.rtcUnboundSchema:
            var malformedFields: [String] = []
            if let value = try? container.decode(Date.self, forKey: .createdAt) {
                createdAt = value
            } else {
                createdAt = .distantPast
                malformedFields.append(CodingKeys.createdAt.stringValue)
            }
            if let value = try? container.decode(TranslationROMRole.self, forKey: .recordedFrom) {
                recordedFrom = value
            } else {
                recordedFrom = .patched
                malformedFields.append(CodingKeys.recordedFrom.stringValue)
            }
            if let value = try? container.decode(TranslationArtifactDigest.self, forKey: .sourceROM) {
                sourceROM = value
            } else {
                sourceROM = TranslationArtifactDigest(byteCount: 0, sha256: "")
                malformedFields.append(CodingKeys.sourceROM.stringValue)
            }
            if let value = try? container.decode(TranslationRouteStartContext.self, forKey: .start) {
                start = value
            } else {
                start = nil
                malformedFields.append(CodingKeys.start.stringValue)
            }
            if let value = try? container.decode(UInt64.self, forKey: .totalFrames) {
                totalFrames = value
            } else {
                totalFrames = 0
                malformedFields.append(CodingKeys.totalFrames.stringValue)
            }
            if let value = try? container.decode([TranslationRouteEvent].self, forKey: .events) {
                events = value
            } else {
                events = []
                malformedFields.append(CodingKeys.events.stringValue)
            }
            if let value = try? container.decode(TranslationRouteCheckpoint.self, forKey: .checkpoint) {
                checkpoint = value
            } else {
                checkpoint = nil
                malformedFields.append(CodingKeys.checkpoint.stringValue)
            }
            let version = schema == Self.currentSchema ? "v3" : "v2"
            decodingIssue = malformedFields.isEmpty
                ? nil
                : "the \(version) payload has missing or malformed fields: \(malformedFields.joined(separator: ", "))"
        case Self.legacySchema:
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            recordedFrom = try container.decode(TranslationROMRole.self, forKey: .recordedFrom)
            sourceROM = TranslationArtifactDigest(
                byteCount: 0,
                sha256: try container.decode(String.self, forKey: .sourceROMSHA256)
            )
            start = nil
            totalFrames = try container.decode(UInt64.self, forKey: .totalFrames)
            events = try container.decode([TranslationRouteEvent].self, forKey: .events)
            checkpoint = nil
            decodingIssue = nil
        default:
            throw TranslationLabError.invalidRoute("unsupported schema")
        }
        if schema == Self.legacySchema {
            try validate()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(recordedFrom, forKey: .recordedFrom)
        try container.encode(totalFrames, forKey: .totalFrames)
        try container.encode(events, forKey: .events)
        if schema == Self.currentSchema || schema == Self.rtcUnboundSchema {
            try container.encode(sourceROM, forKey: .sourceROM)
            try container.encode(start, forKey: .start)
            try container.encode(checkpoint, forKey: .checkpoint)
        } else {
            try container.encode(sourceROM.sha256, forKey: .sourceROMSHA256)
        }
    }
}

public struct TranslationRouteRecorder: Sendable {
    private let role: TranslationROMRole
    private let sourceROM: TranslationArtifactDigest
    private let start: TranslationRouteStartContext
    private var firstFrameNumber: UInt64?
    private var lastFrameNumber: UInt64?
    private var lastInputMask: UInt32?
    private var events: [TranslationRouteEvent] = []
    private var checkpoint: TranslationRouteCheckpoint?

    public init(
        role: TranslationROMRole,
        sourceROM: TranslationArtifactDigest,
        start: TranslationRouteStartContext
    ) {
        self.role = role
        self.sourceROM = sourceROM
        self.start = start
    }

    public mutating func record(input: EngineInput, frame: EngineVideoFrame) throws {
        guard input.rawValue & ~start.hardwareModel.validInputMask == 0 else {
            throw TranslationLabError.invalidRoute(
                "the recorded input contains controls for different hardware"
            )
        }
        let frameNumber = frame.number
        if firstFrameNumber == nil {
            guard frameNumber == 1 else {
                throw TranslationLabError.invalidRoute(
                    "recording began after clean boot; start a new clean-boot test"
                )
            }
            firstFrameNumber = frameNumber
        }
        guard let firstFrameNumber, frameNumber >= firstFrameNumber else { return }
        if let lastFrameNumber, frameNumber != lastFrameNumber + 1 {
            throw TranslationLabError.invalidRoute("the recorded frame sequence is not contiguous")
        }
        let index = frameNumber - firstFrameNumber
        if lastInputMask != input.rawValue {
            events.append(TranslationRouteEvent(frameIndex: index, inputMask: input.rawValue))
            lastInputMask = input.rawValue
        }
        lastFrameNumber = frameNumber
        checkpoint = try TranslationRouteCheckpoint(frameIndex: index, frame: frame)
    }

    public func finish() throws -> TranslationRoute {
        guard let firstFrameNumber, let lastFrameNumber, let checkpoint else {
            throw TranslationLabError.noRecordedFrames
        }
        var normalizedEvents = events
        if normalizedEvents.first?.frameIndex != 0 {
            normalizedEvents.insert(TranslationRouteEvent(frameIndex: 0, inputMask: 0), at: 0)
        }
        return try TranslationRoute(
            recordedFrom: role,
            sourceROM: sourceROM,
            start: start,
            totalFrames: lastFrameNumber - firstFrameNumber + 1,
            events: normalizedEvents,
            checkpoint: checkpoint
        )
    }
}

private func validateDigest(_ digest: TranslationArtifactDigest, label: String) throws {
    guard digest.byteCount > 0 else {
        throw TranslationLabError.invalidRoute("the \(label) byte count is invalid")
    }
    try validateSHA256(digest.sha256, label: label)
}

private func validateSHA256(_ value: String, label: String) throws {
    guard value.count == 64,
          value == value.lowercased(),
          value.allSatisfy({ $0.isHexDigit }) else {
        throw TranslationLabError.invalidRoute("the \(label) digest is invalid")
    }
}

public struct TranslationEvidenceManifest: Codable, Equatable, Sendable {
    public let schema: String
    public let createdAt: Date
    public let projectTitle: String
    public let romRole: TranslationROMRole
    public let romRelativePath: String
    public let rom: TranslationArtifactDigest
    public let romFooterChecksum: UInt16
    public let backend: String
    public let frameNumber: UInt64
    public let frame: TranslationArtifactDigest
    public let gameFrameSHA256: String?
    public let state: TranslationArtifactDigest
    public let internalRAM: TranslationArtifactDigest
    public let route: TranslationArtifactDigest?
    public let isolatedPersistence: Bool
}

public struct TranslationEvidenceInput: Sendable {
    public let project: TranslationProject
    public let role: TranslationROMRole
    public let romURL: URL
    public let romFooterChecksum: UInt16
    public let backend: String
    public let frameNumber: UInt64
    public let framePNG: Data
    public let gameFrameSHA256: String?
    public let state: Data
    public let internalRAM: Data
    public let route: TranslationRoute?

    public init(
        project: TranslationProject,
        role: TranslationROMRole,
        romURL: URL,
        romFooterChecksum: UInt16,
        backend: String,
        frameNumber: UInt64,
        framePNG: Data,
        gameFrameSHA256: String? = nil,
        state: Data,
        internalRAM: Data,
        route: TranslationRoute?
    ) {
        self.project = project
        self.role = role
        self.romURL = romURL
        self.romFooterChecksum = romFooterChecksum
        self.backend = backend
        self.frameNumber = frameNumber
        self.framePNG = framePNG
        self.gameFrameSHA256 = gameFrameSHA256
        self.state = state
        self.internalRAM = internalRAM
        self.route = route
    }
}

public struct TranslationEvidenceArtifact: Codable, Hashable, Sendable {
    public let name: String
    public let directoryURL: URL
    public let manifestURL: URL
    public let frameURL: URL
    public let stateURL: URL
    public let internalRAMURL: URL

    public var routeURL: URL { directoryURL.appendingPathComponent("route.json") }
    public var reviewURL: URL { directoryURL.appendingPathComponent("review.json") }
}

public struct TranslationRouteTestCase: Codable, Equatable, Sendable {
    public let schema: String
    public let routeSHA256: String
    public let name: String
    public let note: String
    public let updatedAt: Date

    public init(
        routeSHA256: String,
        name: String,
        note: String = "",
        updatedAt: Date = Date()
    ) {
        self.schema = "swan-song-route-test-case-v1"
        self.routeSHA256 = routeSHA256
        self.name = name
        self.note = note
        self.updatedAt = updatedAt
    }
}

public struct TranslationRouteSummary: Identifiable, Sendable {
    public let fileURL: URL
    public let route: TranslationRoute
    public let routeDigest: TranslationArtifactDigest
    public let testCase: TranslationRouteTestCase?
    public let testCaseIssue: String?

    public var id: String { fileURL.path }

    public init(
        fileURL: URL,
        route: TranslationRoute,
        routeDigest: TranslationArtifactDigest,
        testCase: TranslationRouteTestCase? = nil,
        testCaseIssue: String? = nil
    ) {
        self.fileURL = fileURL
        self.route = route
        self.routeDigest = routeDigest
        self.testCase = testCase
        self.testCaseIssue = testCaseIssue
    }
}

public struct TranslationRouteBaseline: Codable, Equatable, Sendable {
    public let schema: String
    public let route: TranslationArtifactDigest
    public let evidenceName: String
    public let evidenceManifest: TranslationArtifactDigest
    public let frame: TranslationArtifactDigest
    public let frameNumber: UInt64
    public let createdAt: Date

    public init(
        route: TranslationArtifactDigest,
        evidenceName: String,
        evidenceManifest: TranslationArtifactDigest,
        frame: TranslationArtifactDigest,
        frameNumber: UInt64,
        createdAt: Date = Date()
    ) {
        self.schema = "swan-song-route-baseline-v1"
        self.route = route
        self.evidenceName = evidenceName
        self.evidenceManifest = evidenceManifest
        self.frame = frame
        self.frameNumber = frameNumber
        self.createdAt = createdAt
    }
}

public struct TranslationRouteBaselineSummary: Identifiable, Sendable {
    public let fileURL: URL
    public let baseline: TranslationRouteBaseline
    public let evidence: TranslationEvidenceSummary?
    public let integrityIssue: String?

    public var id: String { fileURL.path }
    public var isIntact: Bool { integrityIssue == nil && evidence?.isIntact == true }

    public init(
        fileURL: URL,
        baseline: TranslationRouteBaseline,
        evidence: TranslationEvidenceSummary?,
        integrityIssue: String?
    ) {
        self.fileURL = fileURL
        self.baseline = baseline
        self.evidence = evidence
        self.integrityIssue = integrityIssue
    }
}

public struct TranslationSuiteBaselineComparison: Codable, Equatable, Sendable {
    public let evidenceName: String
    public let difference: RGBFrameDifference
    public let changedBounds: RGBFrameBounds?

    public var hasVisualChanges: Bool {
        difference.differentPixelCount > 0
    }

    public init(
        evidenceName: String,
        difference: RGBFrameDifference,
        changedBounds: RGBFrameBounds?
    ) {
        self.evidenceName = evidenceName
        self.difference = difference
        self.changedBounds = changedBounds
    }
}

public struct TranslationSuiteCaseResult: Codable, Equatable, Sendable {
    public let route: TranslationArtifactDigest
    public let name: String
    public let originalEvidenceName: String
    public let patchedEvidenceName: String
    public let originalFrameNumber: UInt64
    public let patchedFrameNumber: UInt64
    public let difference: RGBFrameDifference
    public let changedBounds: RGBFrameBounds?
    public let baselineComparison: TranslationSuiteBaselineComparison?
    public let baselineIssue: String?

    public var hasVisualChanges: Bool {
        difference.differentPixelCount > 0
    }

    public init(
        route: TranslationArtifactDigest,
        name: String,
        originalEvidenceName: String,
        patchedEvidenceName: String,
        originalFrameNumber: UInt64,
        patchedFrameNumber: UInt64,
        difference: RGBFrameDifference,
        changedBounds: RGBFrameBounds?,
        baselineComparison: TranslationSuiteBaselineComparison? = nil,
        baselineIssue: String? = nil
    ) {
        self.route = route
        self.name = name
        self.originalEvidenceName = originalEvidenceName
        self.patchedEvidenceName = patchedEvidenceName
        self.originalFrameNumber = originalFrameNumber
        self.patchedFrameNumber = patchedFrameNumber
        self.difference = difference
        self.changedBounds = changedBounds
        self.baselineComparison = baselineComparison
        self.baselineIssue = baselineIssue
    }
}

public struct TranslationSuiteRun: Codable, Equatable, Sendable {
    public let schema: String
    public let projectTitle: String
    public let startedAt: Date
    public let completedAt: Date
    public let cases: [TranslationSuiteCaseResult]

    public var changedCaseCount: Int {
        cases.count(where: \.hasVisualChanges)
    }

    public var identicalCaseCount: Int {
        cases.count - changedCaseCount
    }

    public var changedFromBaselineCount: Int {
        cases.count { $0.baselineComparison?.hasVisualChanges == true }
    }

    public var stableAgainstBaselineCount: Int {
        cases.count {
            $0.baselineComparison.map { !$0.hasVisualChanges } == true
        }
    }

    public var unbaselinedCaseCount: Int {
        cases.count { $0.baselineComparison == nil }
    }

    public init(
        projectTitle: String,
        startedAt: Date,
        completedAt: Date = Date(),
        cases: [TranslationSuiteCaseResult]
    ) {
        self.schema = "swan-song-translation-suite-v1"
        self.projectTitle = projectTitle
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.cases = cases
    }
}

public struct TranslationSuiteRunSummary: Identifiable, Sendable {
    public let fileURL: URL
    public let run: TranslationSuiteRun

    public var id: String { fileURL.path }

    public init(fileURL: URL, run: TranslationSuiteRun) {
        self.fileURL = fileURL
        self.run = run
    }
}

public struct TranslationEvidenceSummary: Identifiable, Sendable {
    public let artifact: TranslationEvidenceArtifact
    public let manifest: TranslationEvidenceManifest?
    public let framePNG: Data?
    public let createdAt: Date
    public let integrityIssue: String?
    public let review: TranslationEvidenceReview?
    public let reviewIssue: String?

    public var id: String { artifact.directoryURL.path }
    public var isIntact: Bool { integrityIssue == nil && manifest != nil }
}

public enum TranslationEvidencePrivateArtifact: String, CaseIterable, Sendable {
    case textIntake = "text-intake.json"
    case translationDraft = "translation-draft.json"
}

public struct TranslationEvidenceStore: Sendable {
    public static let maximumPrivateArtifactBytes = 2 * 1_024 * 1_024

    public init() {}

    public func privateArtifactURL(
        _ kind: TranslationEvidencePrivateArtifact,
        evidence: TranslationEvidenceSummary,
        project: TranslationProject
    ) throws -> URL {
        let directory = evidence.artifact.directoryURL.standardizedFileURL
        let lab = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .standardizedFileURL
        guard safeEvidenceName(directory.lastPathComponent),
              directory.deletingLastPathComponent() == lab,
              project.contains(directory),
              FileManager.default.fileExists(atPath: directory.path) else {
            throw TranslationLabError.unsafePath(directory.path)
        }
        // Revalidate every project-relative directory component immediately
        // before deriving the private sidecar path. This rejects symlinked or
        // replaced capture ancestors rather than trusting the earlier index.
        _ = try prepareDirectory(directory, project: project)
        try securePrivateArtifactDirectory(directory, project: project)
        let target = directory
            .appendingPathComponent(kind.rawValue, isDirectory: false)
            .standardizedFileURL
        guard project.contains(target), target.deletingLastPathComponent() == directory else {
            throw TranslationLabError.unsafePath(target.path)
        }
        return target
    }

    public func privateArtifactExists(
        _ kind: TranslationEvidencePrivateArtifact,
        evidence: TranslationEvidenceSummary,
        project: TranslationProject
    ) throws -> Bool {
        let url = try privateArtifactURL(kind, evidence: evidence, project: project)
        guard try privateArtifactNodeExists(url) else { return false }
        try securePrivateArtifactFile(url, project: project)
        return true
    }

    public func loadPrivateArtifact(
        _ kind: TranslationEvidencePrivateArtifact,
        evidence: TranslationEvidenceSummary,
        project: TranslationProject
    ) throws -> Data? {
        let url = try privateArtifactURL(kind, evidence: evidence, project: project)
        guard try privateArtifactNodeExists(url) else { return nil }
        try securePrivateArtifactFile(url, project: project)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= Self.maximumPrivateArtifactBytes else {
            throw TranslationLabError.invalidProject(
                "the private \(kind.rawValue) sidecar exceeds its size limit"
            )
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= Self.maximumPrivateArtifactBytes else {
            throw TranslationLabError.invalidProject(
                "the private \(kind.rawValue) sidecar changed while it was being read"
            )
        }
        return data
    }

    @discardableResult
    public func savePrivateArtifact(
        _ data: Data,
        kind: TranslationEvidencePrivateArtifact,
        evidence: TranslationEvidenceSummary,
        project: TranslationProject
    ) throws -> URL {
        guard !data.isEmpty, data.count <= Self.maximumPrivateArtifactBytes else {
            throw TranslationLabError.invalidProject(
                "the private \(kind.rawValue) sidecar exceeds its size limit"
            )
        }
        let url = try privateArtifactURL(kind, evidence: evidence, project: project)
        if try privateArtifactNodeExists(url) {
            try securePrivateArtifactFile(url, project: project)
        }
        // Revalidate the complete directory chain again at the write boundary
        // so UI time between selection and save cannot silently follow a new
        // symlink or non-directory ancestor.
        _ = try privateArtifactURL(kind, evidence: evidence, project: project)
        try data.write(to: url, options: [.atomic])
        try securePrivateArtifactFile(url, project: project)
        let writtenValues = try url.resourceValues(forKeys: [.fileSizeKey])
        guard writtenValues.fileSize == data.count else {
            throw TranslationLabError.invalidProject(
                "the private \(kind.rawValue) sidecar was not written completely"
            )
        }
        return url
    }

    /// Removes only the named private sidecar after repeating the same path
    /// and regular-file checks used for reads and writes. Callers should put
    /// an explicit destructive confirmation in front of this operation.
    @discardableResult
    public func removePrivateArtifact(
        _ kind: TranslationEvidencePrivateArtifact,
        evidence: TranslationEvidenceSummary,
        project: TranslationProject
    ) throws -> Bool {
        let url = try privateArtifactURL(kind, evidence: evidence, project: project)
        guard try privateArtifactNodeExists(url) else { return false }
        try securePrivateArtifactFile(url, project: project)
        _ = try privateArtifactURL(kind, evidence: evidence, project: project)
        try securePrivateArtifactFile(url, project: project)
        try FileManager.default.removeItem(at: url)
        guard try !privateArtifactNodeExists(url) else {
            throw TranslationLabError.invalidProject(
                "the private \(kind.rawValue) sidecar could not be removed"
            )
        }
        return true
    }

    public func saveRoute(
        _ route: TranslationRoute,
        project: TranslationProject
    ) throws -> URL {
        try route.validateForProof()
        let routes = try prepareDirectory(
            project.rootURL
                .appendingPathComponent("analysis", isDirectory: true)
                .appendingPathComponent("swan-song-lab", isDirectory: true)
                .appendingPathComponent("routes", isDirectory: true),
            project: project
        )
        let name = "route-\(timestamp(route.createdAt))-\(UUID().uuidString.prefix(8)).json"
        let target = routes.appendingPathComponent(name)
        let data = try Self.encoded(route)
        try writeNewFile(data, to: target, project: project)
        return target
    }

    public func latestRoute(project: TranslationProject) throws -> (URL, TranslationRoute)? {
        guard let latest = try listRoutes(project: project).first else { return nil }
        return (latest.fileURL, latest.route)
    }

    public func listRoutes(project: TranslationProject) throws -> [TranslationRouteSummary] {
        let routes = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("routes", isDirectory: true)
        guard FileManager.default.fileExists(atPath: routes.path) else { return [] }
        _ = try prepareDirectory(routes, project: project)
        let urls = try FileManager.default.contentsOfDirectory(
            at: routes,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let candidates = urls.compactMap { url -> TranslationRouteSummary? in
            guard url.pathExtension.lowercased() == "json" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]) else { return nil }
            guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: url),
                  let route = try? decoder.decode(TranslationRoute.self, from: data) else { return nil }
            let routeDigest = Self.digest(data)
            var testCase: TranslationRouteTestCase?
            var testCaseIssue: String?
            do {
                testCase = try loadTestCase(
                    routeSHA256: routeDigest.sha256,
                    project: project
                )
            } catch {
                testCaseIssue = error.localizedDescription
            }
            return TranslationRouteSummary(
                fileURL: url,
                route: route,
                routeDigest: routeDigest,
                testCase: testCase,
                testCaseIssue: testCaseIssue
            )
        }
        return candidates.sorted { $0.route.createdAt > $1.route.createdAt }
    }

    @discardableResult
    public func saveTestCase(
        name: String,
        note: String,
        route summary: TranslationRouteSummary,
        project: TranslationProject,
        updatedAt: Date = Date()
    ) throws -> TranslationRouteTestCase {
        try validateRegularFile(summary.fileURL, project: project)
        let routeData = try Data(contentsOf: summary.fileURL)
        let routeDigest = Self.digest(routeData)
        guard routeDigest == summary.routeDigest else {
            throw TranslationLabError.invalidRoute(
                "the route changed after it was indexed"
            )
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw TranslationLabError.invalidProject("the test-case name is empty")
        }
        guard normalizedName.count <= 120 else {
            throw TranslationLabError.invalidProject("the test-case name is longer than 120 characters")
        }
        guard normalizedNote.count <= 4_000 else {
            throw TranslationLabError.invalidProject("the test-case note is longer than 4,000 characters")
        }

        let testCase = TranslationRouteTestCase(
            routeSHA256: routeDigest.sha256,
            name: normalizedName,
            note: normalizedNote,
            updatedAt: updatedAt
        )
        let directory = try prepareDirectory(
            testCasesDirectory(project: project),
            project: project
        )
        let target = directory.appendingPathComponent(
            "case-\(routeDigest.sha256).json",
            isDirectory: false
        )
        if FileManager.default.fileExists(atPath: target.path) {
            try validateRegularFile(target, project: project)
        } else {
            guard project.contains(target) else {
                throw TranslationLabError.unsafePath(target.path)
            }
        }
        try Self.encoded(testCase).write(to: target, options: [.atomic])
        return testCase
    }

    @discardableResult
    public func saveBaseline(
        evidence: TranslationEvidenceSummary,
        route summary: TranslationRouteSummary,
        project: TranslationProject,
        createdAt: Date = Date()
    ) throws -> TranslationRouteBaseline {
        guard
            evidence.isIntact,
            evidence.review?.status == .approved,
            evidence.reviewIssue == nil,
            let manifest = evidence.manifest,
            manifest.romRole == .patched,
            manifest.route == summary.routeDigest
        else {
            throw TranslationLabError.invalidProject(
                "a baseline must be intact, Approved patched evidence bound to this exact route"
            )
        }
        try validateRegularFile(summary.fileURL, project: project)
        guard Self.digest(try Data(contentsOf: summary.fileURL)) == summary.routeDigest else {
            throw TranslationLabError.invalidRoute("the route changed after it was indexed")
        }
        try validateEvidenceDirectoryForBaseline(
            evidence.artifact.directoryURL,
            project: project
        )
        try validateRegularFile(evidence.artifact.manifestURL, project: project)
        let manifestData = try Data(contentsOf: evidence.artifact.manifestURL)
        let baseline = TranslationRouteBaseline(
            route: summary.routeDigest,
            evidenceName: evidence.artifact.name,
            evidenceManifest: Self.digest(manifestData),
            frame: manifest.frame,
            frameNumber: manifest.frameNumber,
            createdAt: createdAt
        )
        let directory = try prepareDirectory(
            baselinesDirectory(project: project),
            project: project
        )
        let target = directory.appendingPathComponent(
            "baseline-\(summary.routeDigest.sha256).json",
            isDirectory: false
        )
        if FileManager.default.fileExists(atPath: target.path) {
            try validateRegularFile(target, project: project)
        }
        try Self.encoded(baseline).write(to: target, options: [.atomic])
        return baseline
    }

    public func removeBaseline(
        route summary: TranslationRouteSummary,
        project: TranslationProject
    ) throws {
        let target = baselinesDirectory(project: project).appendingPathComponent(
            "baseline-\(summary.routeDigest.sha256).json",
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try validateRegularFile(target, project: project)
        try FileManager.default.removeItem(at: target)
    }

    public func listBaselines(
        project: TranslationProject
    ) throws -> [TranslationRouteBaselineSummary] {
        let directory = baselinesDirectory(project: project)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        _ = try prepareDirectory(directory, project: project)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let evidenceByName = Dictionary(
            uniqueKeysWithValues: try listEvidence(project: project).map {
                ($0.artifact.name, $0)
            }
        )
        let routeDigests = Set(
            try listRoutes(project: project).map(\.routeDigest.sha256)
        )
        return urls.compactMap { url -> TranslationRouteBaselineSummary? in
            guard url.pathExtension.lowercased() == "json" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]), values.isRegularFile == true, values.isSymbolicLink != true else {
                return nil
            }
            guard
                let data = try? Data(contentsOf: url),
                let baseline = try? decoder.decode(TranslationRouteBaseline.self, from: data)
            else { return nil }
            let evidence = evidenceByName[baseline.evidenceName]
            var issue: String?
            do {
                try validateBaseline(
                    baseline,
                    fileURL: url,
                    evidence: evidence,
                    routeDigests: routeDigests,
                    project: project
                )
            } catch {
                issue = error.localizedDescription
            }
            return TranslationRouteBaselineSummary(
                fileURL: url,
                baseline: baseline,
                evidence: evidence,
                integrityIssue: issue
            )
        }
        .sorted { $0.baseline.createdAt > $1.baseline.createdAt }
    }

    @discardableResult
    public func saveSuiteRun(
        _ run: TranslationSuiteRun,
        project: TranslationProject
    ) throws -> URL {
        try validateSuiteRun(run, project: project)
        let directory = try prepareDirectory(
            suiteRunsDirectory(project: project),
            project: project
        )
        let target = directory.appendingPathComponent(
            "suite-\(timestamp(run.completedAt))-\(UUID().uuidString.prefix(8)).json",
            isDirectory: false
        )
        try writeNewFile(Self.encoded(run), to: target, project: project)
        return target
    }

    public func listSuiteRuns(
        project: TranslationProject
    ) throws -> [TranslationSuiteRunSummary] {
        let directory = suiteRunsDirectory(project: project)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        _ = try prepareDirectory(directory, project: project)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let runs = urls.compactMap { url -> TranslationSuiteRunSummary? in
            guard url.pathExtension.lowercased() == "json" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]), values.isRegularFile == true, values.isSymbolicLink != true else {
                return nil
            }
            guard
                let data = try? Data(contentsOf: url),
                let run = try? decoder.decode(TranslationSuiteRun.self, from: data),
                (try? validateSuiteRun(run, project: project)) != nil
            else { return nil }
            return TranslationSuiteRunSummary(fileURL: url, run: run)
        }
        return runs.sorted { $0.run.completedAt > $1.run.completedAt }
    }

    public func listEvidence(project: TranslationProject) throws -> [TranslationEvidenceSummary] {
        let lab = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
        guard FileManager.default.fileExists(atPath: lab.path) else { return [] }
        _ = try prepareDirectory(lab, project: project)
        let directories = try FileManager.default.contentsOfDirectory(
            at: lab,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles]
        )
        var summaries: [TranslationEvidenceSummary] = []
        for directory in directories where directory.lastPathComponent.hasPrefix("capture-") {
            let values = try directory.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey,
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let artifact = TranslationEvidenceArtifact(
                name: directory.lastPathComponent,
                directoryURL: directory,
                manifestURL: directory.appendingPathComponent("manifest.json"),
                frameURL: directory.appendingPathComponent("frame.png"),
                stateURL: directory.appendingPathComponent("runtime.state"),
                internalRAMURL: directory.appendingPathComponent("ram.bin")
            )
            var manifest: TranslationEvidenceManifest?
            var framePNG: Data?
            var issue: String?
            var review: TranslationEvidenceReview?
            var reviewIssue: String?
            do {
                try validateRegularFile(artifact.manifestURL, project: project)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                manifest = try decoder.decode(
                    TranslationEvidenceManifest.self,
                    from: Data(contentsOf: artifact.manifestURL)
                )
                guard manifest?.schema == "swan-song-translation-evidence-v1" else {
                    throw TranslationLabError.invalidProject("unsupported evidence manifest")
                }
                guard manifest?.projectTitle == project.title else {
                    throw TranslationLabError.invalidProject("evidence belongs to another project")
                }
                guard manifest?.isolatedPersistence == true else {
                    throw TranslationLabError.invalidProject("evidence did not use isolated persistence")
                }
                try validateRegularFile(artifact.frameURL, project: project)
                try validateRegularFile(artifact.stateURL, project: project)
                try validateRegularFile(artifact.internalRAMURL, project: project)
                let frame = try Data(contentsOf: artifact.frameURL)
                let state = try Data(contentsOf: artifact.stateURL)
                let ram = try Data(contentsOf: artifact.internalRAMURL)
                framePNG = frame
                if let manifest {
                    guard Self.digest(frame) == manifest.frame else {
                        throw TranslationLabError.invalidProject("frame digest mismatch")
                    }
                    guard Self.digest(state) == manifest.state else {
                        throw TranslationLabError.invalidProject("state digest mismatch")
                    }
                    guard Self.digest(ram) == manifest.internalRAM else {
                        throw TranslationLabError.invalidProject("RAM digest mismatch")
                    }
                    if let expectedRoute = manifest.route {
                        let routeURL = directory.appendingPathComponent("route.json")
                        try validateRegularFile(routeURL, project: project)
                        guard Self.digest(try Data(contentsOf: routeURL)) == expectedRoute else {
                            throw TranslationLabError.invalidProject("route digest mismatch")
                        }
                    }
                }
            } catch {
                issue = error.localizedDescription
                if framePNG == nil,
                   (try? validateRegularFile(artifact.frameURL, project: project)) != nil {
                    framePNG = try? Data(contentsOf: artifact.frameURL)
                }
            }
            if FileManager.default.fileExists(atPath: artifact.reviewURL.path) {
                do {
                    try validateRegularFile(artifact.reviewURL, project: project)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let decoded = try decoder.decode(
                        TranslationEvidenceReview.self,
                        from: Data(contentsOf: artifact.reviewURL)
                    )
                    guard decoded.schema == "swan-song-evidence-review-v1" else {
                        throw TranslationLabError.invalidProject("unsupported evidence review")
                    }
                    review = decoded
                } catch {
                    reviewIssue = error.localizedDescription
                }
            }
            summaries.append(
                TranslationEvidenceSummary(
                    artifact: artifact,
                    manifest: manifest,
                    framePNG: framePNG,
                    createdAt: manifest?.createdAt ?? values.contentModificationDate ?? .distantPast,
                    integrityIssue: issue,
                    review: review,
                    reviewIssue: reviewIssue
                )
            )
        }
        return summaries.sorted { $0.createdAt > $1.createdAt }
    }

    public func loadInternalRAM(
        for evidence: TranslationEvidenceSummary,
        project: TranslationProject
    ) throws -> Data {
        guard evidence.isIntact, let indexedManifest = evidence.manifest else {
            throw TranslationRAMInspectionError.damagedEvidence(
                evidence.integrityIssue ?? "the evidence manifest is unavailable"
            )
        }
        try validateEvidenceDirectoryForBaseline(
            evidence.artifact.directoryURL,
            project: project
        )
        try validateRegularFile(evidence.artifact.manifestURL, project: project)
        try validateRegularFile(evidence.artifact.internalRAMURL, project: project)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let currentManifest = try decoder.decode(
            TranslationEvidenceManifest.self,
            from: Data(contentsOf: evidence.artifact.manifestURL)
        )
        guard
            currentManifest == indexedManifest,
            currentManifest.schema == "swan-song-translation-evidence-v1",
            currentManifest.projectTitle == project.title,
            currentManifest.isolatedPersistence
        else {
            throw TranslationRAMInspectionError.damagedEvidence(
                "the evidence manifest changed after it was indexed"
            )
        }

        let ram = try Data(contentsOf: evidence.artifact.internalRAMURL)
        guard Self.digest(ram) == currentManifest.internalRAM else {
            throw TranslationRAMInspectionError.damagedEvidence(
                "the RAM digest no longer matches the evidence manifest"
            )
        }
        return ram
    }

    public func compareInternalRAM(
        _ first: TranslationEvidenceSummary,
        _ second: TranslationEvidenceSummary,
        project: TranslationProject
    ) throws -> TranslationRAMComparison {
        guard
            let firstManifest = first.manifest,
            let secondManifest = second.manifest,
            first.isIntact,
            second.isIntact
        else {
            throw TranslationRAMInspectionError.damagedEvidence(
                first.integrityIssue ?? second.integrityIssue ?? "one capture is incomplete"
            )
        }

        let original: TranslationEvidenceSummary
        let patched: TranslationEvidenceSummary
        let originalManifest: TranslationEvidenceManifest
        let patchedManifest: TranslationEvidenceManifest
        switch (firstManifest.romRole, secondManifest.romRole) {
        case (.original, .patched):
            (original, patched) = (first, second)
            (originalManifest, patchedManifest) = (firstManifest, secondManifest)
        case (.patched, .original):
            (original, patched) = (second, first)
            (originalManifest, patchedManifest) = (secondManifest, firstManifest)
        default:
            throw TranslationRAMInspectionError.oppositeRolesRequired
        }

        guard
            let originalRoute = originalManifest.route,
            let patchedRoute = patchedManifest.route,
            originalRoute == patchedRoute
        else {
            throw TranslationRAMInspectionError.exactRouteRequired
        }
        guard originalManifest.frameNumber == patchedManifest.frameNumber else {
            throw TranslationRAMInspectionError.frameMismatch(
                original: originalManifest.frameNumber,
                patched: patchedManifest.frameNumber
            )
        }

        let originalRAM = try loadInternalRAM(for: original, project: project)
        let patchedRAM = try loadInternalRAM(for: patched, project: project)
        return try TranslationRAMComparison(
            originalEvidenceName: original.artifact.name,
            patchedEvidenceName: patched.artifact.name,
            route: originalRoute,
            originalFrameNumber: originalManifest.frameNumber,
            patchedFrameNumber: patchedManifest.frameNumber,
            original: originalRAM,
            patched: patchedRAM
        )
    }

    public func capture(_ input: TranslationEvidenceInput) throws -> TranslationEvidenceArtifact {
        guard input.project.contains(input.romURL) else {
            throw TranslationLabError.unsafePath(input.romURL.path)
        }
        let romData = try Data(contentsOf: input.romURL, options: [.mappedIfSafe])
        let createdAt = Date()
        let captureName = "capture-\(timestamp(createdAt))-\(input.role.rawValue)-\(UUID().uuidString.prefix(8))"
        let lab = try prepareDirectory(
            input.project.rootURL
                .appendingPathComponent("analysis", isDirectory: true)
                .appendingPathComponent("swan-song-lab", isDirectory: true),
            project: input.project
        )
        let staging = lab.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let final = lab.appendingPathComponent(captureName, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        var committed = false
        defer {
            if !committed { try? FileManager.default.removeItem(at: staging) }
        }

        let frameURL = staging.appendingPathComponent("frame.png")
        let stateURL = staging.appendingPathComponent("runtime.state")
        let ramURL = staging.appendingPathComponent("ram.bin")
        try input.framePNG.write(to: frameURL, options: [.atomic])
        try input.state.write(to: stateURL, options: [.atomic])
        try input.internalRAM.write(to: ramURL, options: [.atomic])

        var routeDigest: TranslationArtifactDigest?
        if let route = input.route {
            try route.validateForProof()
            guard let gameFrameSHA256 = input.gameFrameSHA256 else {
                throw TranslationLabError.invalidProject(
                    "routed evidence is missing its native game-frame fingerprint"
                )
            }
            try validateSHA256(gameFrameSHA256, label: "game frame")
            if input.role == .original,
               gameFrameSHA256 != route.checkpoint?.sha256 {
                throw TranslationLabError.invalidProject(
                    "Original evidence does not match the route checkpoint"
                )
            }
            let routeData = try Self.encoded(route)
            try routeData.write(to: staging.appendingPathComponent("route.json"), options: [.atomic])
            routeDigest = Self.digest(routeData)
        }

        let manifest = TranslationEvidenceManifest(
            schema: "swan-song-translation-evidence-v1",
            createdAt: createdAt,
            projectTitle: input.project.title,
            romRole: input.role,
            romRelativePath: try input.project.relativePath(for: input.romURL),
            rom: Self.digest(romData),
            romFooterChecksum: input.romFooterChecksum,
            backend: input.backend,
            frameNumber: input.frameNumber,
            frame: Self.digest(input.framePNG),
            gameFrameSHA256: input.gameFrameSHA256,
            state: Self.digest(input.state),
            internalRAM: Self.digest(input.internalRAM),
            route: routeDigest,
            isolatedPersistence: true
        )
        let manifestData = try Self.encoded(manifest)
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: [.atomic])
        try FileManager.default.moveItem(at: staging, to: final)
        committed = true

        return TranslationEvidenceArtifact(
            name: captureName,
            directoryURL: final,
            manifestURL: final.appendingPathComponent("manifest.json"),
            frameURL: final.appendingPathComponent("frame.png"),
            stateURL: final.appendingPathComponent("runtime.state"),
            internalRAMURL: final.appendingPathComponent("ram.bin")
        )
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ data: Data) -> TranslationArtifactDigest {
        TranslationArtifactDigest(byteCount: data.count, sha256: sha256(data))
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func loadTestCase(
        routeSHA256: String,
        project: TranslationProject
    ) throws -> TranslationRouteTestCase? {
        let url = testCasesDirectory(project: project).appendingPathComponent(
            "case-\(routeSHA256).json",
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try validateRegularFile(url, project: project)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let testCase = try decoder.decode(
            TranslationRouteTestCase.self,
            from: Data(contentsOf: url)
        )
        guard
            testCase.schema == "swan-song-route-test-case-v1",
            testCase.routeSHA256 == routeSHA256,
            !testCase.name.isEmpty,
            testCase.name.count <= 120,
            testCase.name == testCase.name.trimmingCharacters(in: .whitespacesAndNewlines),
            testCase.note.count <= 4_000,
            testCase.note == testCase.note.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw TranslationLabError.invalidProject(
                "route test-case metadata is invalid"
            )
        }
        return testCase
    }

    private func testCasesDirectory(project: TranslationProject) -> URL {
        project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("test-cases", isDirectory: true)
    }

    private func baselinesDirectory(project: TranslationProject) -> URL {
        project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("baselines", isDirectory: true)
    }

    private func suiteRunsDirectory(project: TranslationProject) -> URL {
        project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("suite-runs", isDirectory: true)
    }

    private func validateBaseline(
        _ baseline: TranslationRouteBaseline,
        fileURL: URL,
        evidence: TranslationEvidenceSummary?,
        routeDigests: Set<String>,
        project: TranslationProject
    ) throws {
        guard
            baseline.schema == "swan-song-route-baseline-v1",
            baseline.route.byteCount > 0,
            baseline.route.sha256.count == 64,
            baseline.route.sha256.allSatisfy({ $0.isHexDigit }),
            routeDigests.contains(baseline.route.sha256),
            fileURL.lastPathComponent == "baseline-\(baseline.route.sha256).json",
            safeEvidenceName(baseline.evidenceName),
            baseline.evidenceManifest.byteCount > 0,
            baseline.evidenceManifest.sha256.count == 64,
            baseline.evidenceManifest.sha256.allSatisfy({ $0.isHexDigit }),
            baseline.frame.byteCount > 0,
            baseline.frame.sha256.count == 64,
            baseline.frame.sha256.allSatisfy({ $0.isHexDigit })
        else {
            throw TranslationLabError.invalidProject("route baseline metadata is invalid")
        }
        guard
            let evidence,
            evidence.isIntact,
            evidence.review?.status == .approved,
            evidence.reviewIssue == nil,
            let manifest = evidence.manifest,
            manifest.romRole == .patched,
            manifest.route == baseline.route,
            manifest.frame == baseline.frame,
            manifest.frameNumber == baseline.frameNumber
        else {
            throw TranslationLabError.invalidProject(
                "the approved patched evidence behind this baseline is missing or no longer valid"
            )
        }
        try validateEvidenceDirectoryForBaseline(
            evidence.artifact.directoryURL,
            project: project
        )
        try validateRegularFile(evidence.artifact.manifestURL, project: project)
        guard Self.digest(try Data(contentsOf: evidence.artifact.manifestURL))
            == baseline.evidenceManifest else {
            throw TranslationLabError.invalidProject(
                "the evidence manifest behind this baseline changed"
            )
        }
    }

    private func validateEvidenceDirectoryForBaseline(
        _ url: URL,
        project: TranslationProject
    ) throws {
        guard project.contains(url) else {
            throw TranslationLabError.unsafePath(url.path)
        }
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(url.path)
        }
    }

    private func validateSuiteRun(
        _ run: TranslationSuiteRun,
        project: TranslationProject
    ) throws {
        guard
            run.schema == "swan-song-translation-suite-v1",
            run.projectTitle == project.title,
            run.completedAt >= run.startedAt,
            !run.cases.isEmpty
        else {
            throw TranslationLabError.invalidProject("translation suite report metadata is invalid")
        }
        var routeDigests = Set<String>()
        for result in run.cases {
            let digest = result.route.sha256
            guard
                result.route.byteCount > 0,
                digest.count == 64,
                digest.allSatisfy({ $0.isHexDigit }),
                routeDigests.insert(digest).inserted,
                !result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                result.name.count <= 120,
                safeEvidenceName(result.originalEvidenceName),
                safeEvidenceName(result.patchedEvidenceName)
            else {
                throw TranslationLabError.invalidProject("translation suite case metadata is invalid")
            }
            try validateSuiteDifference(
                result.difference,
                changedBounds: result.changedBounds,
                label: "Original/Patched"
            )
            if let baseline = result.baselineComparison {
                guard
                    result.baselineIssue == nil,
                    safeEvidenceName(baseline.evidenceName)
                else {
                    throw TranslationLabError.invalidProject(
                        "translation suite baseline reference is invalid"
                    )
                }
                try validateSuiteDifference(
                    baseline.difference,
                    changedBounds: baseline.changedBounds,
                    label: "baseline"
                )
            } else if let issue = result.baselineIssue {
                guard
                    !issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    issue.count <= 1_000
                else {
                    throw TranslationLabError.invalidProject(
                        "translation suite baseline issue is invalid"
                    )
                }
            }
        }
    }

    private func validateSuiteDifference(
        _ difference: RGBFrameDifference,
        changedBounds: RGBFrameBounds?,
        label: String
    ) throws {
        guard
            difference.pixelCount > 0,
            difference.differentPixelCount >= 0,
            difference.differentPixelCount <= difference.pixelCount,
            difference.meanAbsoluteChannelError >= 0,
            difference.meanAbsoluteChannelError <= 255
        else {
            throw TranslationLabError.invalidProject(
                "translation suite \(label) difference metrics are invalid"
            )
        }
        if let bounds = changedBounds {
            guard
                difference.differentPixelCount > 0,
                bounds.x >= 0,
                bounds.y >= 0,
                bounds.width > 0,
                bounds.height > 0
            else {
                throw TranslationLabError.invalidProject(
                    "translation suite \(label) change bounds are invalid"
                )
            }
        } else if difference.differentPixelCount > 0 {
            throw TranslationLabError.invalidProject(
                "translation suite \(label) change bounds are missing"
            )
        }
    }

    private func safeEvidenceName(_ name: String) -> Bool {
        name.hasPrefix("capture-")
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
    }

    private func prepareDirectory(_ url: URL, project: TranslationProject) throws -> URL {
        guard project.contains(url) else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let fileManager = FileManager.default
        let relative = try project.relativePath(for: url)
        var current = project.rootURL
        for component in relative.split(separator: "/").map(String.init) {
            current.appendPathComponent(component, isDirectory: true)
            if fileManager.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw TranslationLabError.unsafePath(current.path)
                }
            } else {
                try fileManager.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
        return url
    }

    private func writeNewFile(_ data: Data, to url: URL, project: TranslationProject) throws {
        guard project.contains(url), !FileManager.default.fileExists(atPath: url.path) else {
            throw TranslationLabError.unsafePath(url.path)
        }
        try data.write(to: url, options: [.atomic])
    }

    private func validateRegularFile(_ url: URL, project: TranslationProject) throws {
        guard project.contains(url) else {
            throw TranslationLabError.unsafePath(url.path)
        }
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(url.path)
        }
    }

    private func securePrivateArtifactDirectory(
        _ url: URL,
        project: TranslationProject
    ) throws {
        guard project.contains(url) else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(url.path)
        }
        try validatePrivateArtifactIdentity(url, kind: .directory)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: url.path
        )
        let status = try validatePrivateArtifactIdentity(url, kind: .directory)
        guard Int(status.st_mode & 0o777) == 0o700 else {
            throw TranslationLabError.invalidProject(
                "the private evidence directory could not be restricted to its owner"
            )
        }
    }

    private func securePrivateArtifactFile(
        _ url: URL,
        project: TranslationProject
    ) throws {
        try validateRegularFile(url, project: project)
        try validatePrivateArtifactIdentity(url, kind: .regularFile)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
        try validateRegularFile(url, project: project)
        let status = try validatePrivateArtifactIdentity(url, kind: .regularFile)
        guard Int(status.st_mode & 0o777) == 0o600 else {
            throw TranslationLabError.invalidProject(
                "the private sidecar could not be restricted to its owner"
            )
        }
    }

    private enum PrivateArtifactNodeKind {
        case directory
        case regularFile
    }

    @discardableResult
    private func validatePrivateArtifactIdentity(
        _ url: URL,
        kind: PrivateArtifactNodeKind
    ) throws -> stat {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              status.st_uid == getuid() else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let nodeType = status.st_mode & mode_t(S_IFMT)
        switch kind {
        case .directory:
            guard nodeType == mode_t(S_IFDIR) else {
                throw TranslationLabError.unsafePath(url.path)
            }
        case .regularFile:
            guard nodeType == mode_t(S_IFREG), status.st_nlink == 1 else {
                throw TranslationLabError.unsafePath(url.path)
            }
        }
        return status
    }

    private func privateArtifactNodeExists(_ url: URL) throws -> Bool {
        var status = stat()
        if lstat(url.path, &status) == 0 { return true }
        if errno == ENOENT { return false }
        throw TranslationLabError.unsafePath(url.path)
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}
