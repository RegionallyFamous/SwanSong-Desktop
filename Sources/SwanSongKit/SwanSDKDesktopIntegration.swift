import Foundation

public enum SwanSDKRecipe: String, CaseIterable, Codable, Identifiable, Sendable {
    case arcadeAction = "arcade-action"
    case menuPuzzle = "menu-puzzle"
    case gridTactics = "grid-tactics"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .arcadeAction: "Arcade Action"
        case .menuPuzzle: "Menu Puzzle"
        case .gridTactics: "Grid Tactics"
        }
    }

    public var summary: String {
        switch self {
        case .arcadeAction:
            "Immediate movement, scoring, hazards, and a short repeatable loop."
        case .menuPuzzle:
            "Cursor-driven screens, rules, feedback, and deterministic resets."
        case .gridTactics:
            "A turn-based board, selection states, movement, and victory checks."
        }
    }
}

public enum SwanSDKWorkspaceAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case newProject = "New"
    case assets = "Assets"
    case build = "Build"
    case test = "Test"
    case play = "Play"
    case profile = "Profile"
    case evidence = "Evidence"
    case release = "Release"

    public var id: String { rawValue }
}

public enum SwanSDKCommand: Equatable, Sendable {
    case newProject(name: String, recipe: SwanSDKRecipe, parentDirectory: URL)
    case assets(manifest: URL)
    case build(manifest: URL, target: String? = nil)
    case test(manifest: URL)
    case play(manifest: URL, scenario: String)
    case report(manifest: URL)
    case doctor(manifest: URL?, timeoutSeconds: Int? = nil)
    case optimize(manifest: URL, assetID: String? = nil)
    case fuzz(manifest: URL, seed: UInt64, cases: Int, frames: Int)
    case laboratory(manifest: URL, testCase: String, rtcSeed: Int64? = nil)
    case scenarioRecord(manifest: URL, inputLog: URL, outputPlan: URL)
    case dev(manifest: URL, scenario: String?, once: Bool)
    case profile(manifest: URL, trace: URL? = nil)
    case evidenceDiff(before: URL, after: URL)
    case release(manifest: URL, output: URL?, notes: URL?, timeoutSeconds: Int? = nil)

    public var action: SwanSDKWorkspaceAction? {
        switch self {
        case .newProject: .newProject
        case .assets: .assets
        case .build: .build
        case .test: .test
        case .play: .play
        case .report, .profile: .profile
        case .doctor: nil
        case .optimize: .assets
        case .fuzz, .laboratory: .test
        case .scenarioRecord, .dev: .play
        case .evidenceDiff: .evidence
        case .release: .release
        }
    }

    public var arguments: [String] {
        switch self {
        case let .newProject(name, recipe, parentDirectory):
            return [
                "new", name,
                "--template", recipe.rawValue,
                "--directory", parentDirectory.appendingPathComponent(name, isDirectory: true).path,
            ]
        case let .assets(manifest):
            return ["assets", "--project", manifest.path]
        case let .build(manifest, target):
            if let target, !target.isEmpty {
                return ["build", "--project", manifest.path, "--target", target]
            } else {
                return ["build", "--project", manifest.path]
            }
        case let .test(manifest):
            return ["test", "--project", manifest.path]
        case let .play(manifest, scenario):
            return ["play", scenario, "--project", manifest.path]
        case let .report(manifest):
            return ["report", "--project", manifest.path, "--json"]
        case let .doctor(manifest, timeoutSeconds):
            var arguments = ["doctor"]
            if let manifest { arguments += ["--project", manifest.path] }
            if let timeoutSeconds { arguments += ["--timeout", String(timeoutSeconds)] }
            arguments.append("--json")
            return arguments
        case let .optimize(manifest, assetID):
            var arguments = ["optimize", "--project", manifest.path]
            if let assetID, !assetID.isEmpty { arguments += ["--asset", assetID] }
            arguments.append("--json")
            return arguments
        case let .fuzz(manifest, seed, cases, frames):
            return [
                "fuzz", "--project", manifest.path,
                "--seed", String(seed), "--cases", String(cases),
                "--frames", String(frames), "--json",
            ]
        case let .laboratory(manifest, testCase, rtcSeed):
            var arguments = ["lab", "--project", manifest.path, "--case", testCase]
            if let rtcSeed { arguments += ["--rtc-seed", String(rtcSeed)] }
            arguments.append("--json")
            return arguments
        case let .scenarioRecord(manifest, inputLog, outputPlan):
            return [
                "scenario-record", "--project", manifest.path,
                "--input-log", inputLog.path, "--output", outputPlan.path,
                "--json",
            ]
        case let .dev(manifest, scenario, once):
            var arguments = ["dev", "--project", manifest.path]
            if let scenario, !scenario.isEmpty { arguments += ["--scenario", scenario] }
            if once { arguments.append("--once") }
            arguments.append("--json")
            return arguments
        case let .profile(manifest, trace):
            var arguments = ["profile", "--project", manifest.path]
            if let trace { arguments += ["--trace", trace.path] }
            arguments.append("--json")
            return arguments
        case let .evidenceDiff(before, after):
            return [
                "evidence-diff", "--before", before.path,
                "--after", after.path, "--json",
            ]
        case let .release(manifest, output, notes, timeoutSeconds):
            var arguments = ["release", "--project", manifest.path]
            if let output { arguments += ["--output", output.path] }
            if let notes { arguments += ["--notes", notes.path] }
            if let timeoutSeconds { arguments += ["--timeout", String(timeoutSeconds)] }
            arguments.append("--json")
            return arguments
        }
    }

    public var workingDirectory: URL? {
        switch self {
        case let .newProject(_, _, parentDirectory):
            parentDirectory
        case let .assets(manifest), let .build(manifest, _),
             let .test(manifest), let .play(manifest, _),
             let .report(manifest), let .optimize(manifest, _),
             let .fuzz(manifest, _, _, _), let .laboratory(manifest, _, _),
             let .scenarioRecord(manifest, _, _), let .dev(manifest, _, _),
             let .profile(manifest, _), let .release(manifest, _, _, _):
            manifest.deletingLastPathComponent()
        case let .doctor(manifest, _):
            manifest?.deletingLastPathComponent()
        case let .evidenceDiff(before, _):
            before.deletingLastPathComponent()
        }
    }

    public var expectedJSONSchema: String? {
        switch self {
        case .report: "swansong-resource-report-v1"
        case .doctor: "swansong-doctor-report-v1"
        case .optimize: "swansong-asset-optimization-report-v1"
        case .fuzz: "swansong-fuzz-report-v1"
        case .laboratory: "swansong-laboratory-report-v1"
        case .scenarioRecord: "swansong-scenario-record-report-v1"
        case .dev: "swansong-dev-event-v1"
        case .profile: "swansong-profile-report-v1"
        case .evidenceDiff: "swansong-evidence-diff-v1"
        case .release: "swansong-release-report-v1"
        case .newProject, .assets, .build, .test, .play: nil
        }
    }

    public var emitsJSONLines: Bool {
        if case .dev = self { true } else { false }
    }
}

public enum SwanSDKIntegrationError: LocalizedError, Equatable {
    case invalidSDKLocation(String)
    case commandAlreadyRunning
    case commandNotRunning
    case commandFailed(status: Int32, detail: String)
    case malformedContract(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSDKLocation(detail): detail
        case .commandAlreadyRunning: "Another SwanSong SDK command is already running."
        case .commandNotRunning: "No SwanSong SDK command is running."
        case let .commandFailed(status, detail):
            "The SwanSong SDK command exited with status \(status). \(detail)"
        case let .malformedContract(detail): detail
        }
    }
}

public struct SwanSDKCLIResolution: Equatable, Sendable {
    public let sdkRoot: URL
    public let executableURL: URL
    public let argumentPrefix: [String]
    public let environment: [String: String]

    public init(
        sdkRoot: URL,
        executableURL: URL,
        argumentPrefix: [String],
        environment: [String: String]
    ) {
        self.sdkRoot = sdkRoot
        self.executableURL = executableURL
        self.argumentPrefix = argumentPrefix
        self.environment = environment
    }

    public static func resolve(
        sdkRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        let root = sdkRoot.standardizedFileURL.resolvingSymlinksInPath()
        let schema = root.appendingPathComponent("schema/swan.schema.json")
        let recipes = root.appendingPathComponent("templates", isDirectory: true)
        guard FileManager.default.fileExists(atPath: schema.path),
              FileManager.default.fileExists(atPath: recipes.path) else {
            throw SwanSDKIntegrationError.invalidSDKLocation(
                "Choose a SwanSong SDK folder containing schema/swan.schema.json and templates/."
            )
        }

        let bundledCLI = root.appendingPathComponent("bin/swan")
        if FileManager.default.isExecutableFile(atPath: bundledCLI.path) {
            return Self(
                sdkRoot: root,
                executableURL: bundledCLI,
                argumentPrefix: [],
                environment: ["SWANSONG_SDK_DIR": root.path]
            )
        }

        let module = root.appendingPathComponent("python/swansong_sdk/cli.py")
        guard FileManager.default.fileExists(atPath: module.path) else {
            throw SwanSDKIntegrationError.invalidSDKLocation(
                "The selected SDK does not contain bin/swan or python/swansong_sdk/cli.py."
            )
        }
        var additions = [
            "SWANSONG_SDK_DIR": root.path,
            "PYTHONPATH": root.appendingPathComponent("python").path,
        ]
        if let existing = environment["PYTHONPATH"], !existing.isEmpty {
            additions["PYTHONPATH"]! += ":\(existing)"
        }
        let bundledPython = root.appendingPathComponent("runtime/bin/python3")
        if FileManager.default.isExecutableFile(atPath: bundledPython.path) {
            return Self(
                sdkRoot: root,
                executableURL: bundledPython,
                argumentPrefix: ["-m", "swansong_sdk.cli"],
                environment: additions
            )
        }
        return Self(
            sdkRoot: root,
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            argumentPrefix: ["python3", "-m", "swansong_sdk.cli"],
            environment: additions
        )
    }

    public func invocation(for command: SwanSDKCommand) -> SwanSDKCommandInvocation {
        SwanSDKCommandInvocation(
            executableURL: executableURL,
            arguments: argumentPrefix + command.arguments,
            workingDirectory: command.workingDirectory ?? sdkRoot,
            environment: environment
        )
    }
}

public struct SwanSDKCommandInvocation: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let workingDirectory: URL
    public let environment: [String: String]
}

public struct SwanSDKCommandResult: Equatable, Sendable {
    public let status: Int32
    public let standardOutput: String
    public let standardError: String

    public init(status: Int32, standardOutput: String, standardError: String) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { status == 0 }

    public var diagnostics: String {
        [standardOutput, standardError]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: standardOutput.isEmpty || standardError.isEmpty ? "" : "\n")
    }
}

public enum SwanSDKOutputStream: String, Sendable {
    case standardOutput
    case standardError
}

public final class SwanSDKSubprocessRunner: @unchecked Sendable {
    public init() {}

    public func run(
        _ invocation: SwanSDKCommandInvocation,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        onOutput: (@Sendable (SwanSDKOutputStream, String) -> Void)? = nil
    ) async throws -> SwanSDKCommandResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-SDK-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let stdoutURL = directory.appendingPathComponent("stdout.txt")
        let stderrURL = directory.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory
        process.environment = inheritedEnvironment.merging(invocation.environment) { _, supplied in
            supplied
        }
        process.standardOutput = stdout
        process.standardError = stderr

        let statuses = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }
        try process.run()
        // Keep the termination wait outside the caller's cancellation tree.
        // AsyncStream.next() is itself cancellation-aware; awaiting it directly
        // can return nil while Process is still exiting, at which point reading
        // terminationStatus raises an Objective-C exception.
        let terminationWaiter = Task.detached { () -> Int32? in
            var iterator = statuses.makeAsyncIterator()
            return await iterator.next()
        }
        let monitor = Task.detached {
            await Self.monitor(
                standardOutput: stdoutURL,
                standardError: stderrURL,
                onOutput: onOutput
            )
        }
        let status = await withTaskCancellationHandler {
            await terminationWaiter.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        guard let status else {
            throw SwanSDKIntegrationError.commandFailed(
                status: -1,
                detail: "The SDK process ended without a termination status."
            )
        }
        monitor.cancel()
        _ = await monitor.value
        try stdout.synchronize()
        try stderr.synchronize()
        let output = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let error = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        if Task.isCancelled { throw CancellationError() }
        return SwanSDKCommandResult(
            status: status,
            standardOutput: output,
            standardError: error
        )
    }

    private static func monitor(
        standardOutput: URL,
        standardError: URL,
        onOutput: (@Sendable (SwanSDKOutputStream, String) -> Void)?
    ) async {
        var outputOffset: UInt64 = 0
        var errorOffset: UInt64 = 0
        repeat {
            outputOffset = readNewText(
                at: standardOutput,
                offset: outputOffset,
                stream: .standardOutput,
                onOutput: onOutput
            )
            errorOffset = readNewText(
                at: standardError,
                offset: errorOffset,
                stream: .standardError,
                onOutput: onOutput
            )
            if !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(75))
            }
        } while !Task.isCancelled
        _ = readNewText(
            at: standardOutput,
            offset: outputOffset,
            stream: .standardOutput,
            onOutput: onOutput
        )
        _ = readNewText(
            at: standardError,
            offset: errorOffset,
            stream: .standardError,
            onOutput: onOutput
        )
    }

    private static func readNewText(
        at url: URL,
        offset: UInt64,
        stream: SwanSDKOutputStream,
        onOutput: (@Sendable (SwanSDKOutputStream, String) -> Void)?
    ) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd(), !data.isEmpty else { return offset }
            onOutput?(stream, String(decoding: data, as: UTF8.self))
            return offset + UInt64(data.count)
        } catch {
            return offset
        }
    }
}

public struct SwanSDKWorkspaceStateMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle(lastAction: SwanSDKWorkspaceAction?, succeeded: Bool?)
        case running(id: UUID, action: SwanSDKWorkspaceAction)
    }

    public private(set) var phase: Phase = .idle(lastAction: nil, succeeded: nil)

    public init() {}

    @discardableResult
    public mutating func start(_ action: SwanSDKWorkspaceAction) throws -> UUID {
        guard case .idle = phase else {
            throw SwanSDKIntegrationError.commandAlreadyRunning
        }
        let id = UUID()
        phase = .running(id: id, action: action)
        return id
    }

    public mutating func finish(id: UUID, succeeded: Bool) throws {
        guard case let .running(activeID, action) = phase, activeID == id else {
            throw SwanSDKIntegrationError.commandNotRunning
        }
        phase = .idle(lastAction: action, succeeded: succeeded)
    }
}

public struct SwanSDKPlayContract: Codable, Equatable, Sendable {
    public struct Game: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let rom: String
    }

    public struct Scenario: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let goal: String
        public let plan: String
        public let requiredChecks: [String]
        public let requiresAudioEvidence: Bool
        public let freshBoot: Bool
        public let requiresMediaInspection: Bool
    }

    public let schema: String
    public let game: Game
    public let controls: [String: [String]]
    public let scenarios: [Scenario]

    public static func decode(_ data: Data) throws -> Self {
        let contract = try JSONDecoder().decode(Self.self, from: data)
        guard contract.schema == "swan-song-game-contract-v1" else {
            throw SwanSDKIntegrationError.malformedContract(
                "Unsupported play contract schema: \(contract.schema)"
            )
        }
        return contract
    }
}

public struct SwanSDKResourceReport: Codable, Equatable, Sendable {
    public struct SceneUsage: Codable, Equatable, Identifiable, Sendable {
        public let scene: String
        public let vramTiles: Int
        public let palettes: Int
        public var id: String { scene }
    }

    public struct Asset: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let type: String
        public let source: String
        public let sha256: String
        public let sourceBytes: Int
        public let tileBytes: Int
        public let uniqueTiles: Int
        public let converter: String
    }

    public let schema: String
    public let project: String
    public let sourceAssetBytes: Int
    public let generatedTileBytes: Int
    public let audioBytes: Int
    public let uniqueTiles: Int
    public let sceneUsage: [SceneUsage]
    public let reserved: [String: Int]
    public let budgets: [String: Int]
    public let assets: [Asset]
    public let romBytes: Int?
    public let linkedInternalRamBytes: Int?
    public let linkedMonoAreaBytes: Int?
    public let linkedColorAreaBytes: Int?
    public let internalRamHardwareBytes: Int?
    public let monoAreaHardwareBytes: Int?
    public let colorAreaHardwareBytes: Int?
    public let budgetFailures: [String]?

    public static func decode(_ data: Data) throws -> Self {
        let report = try JSONDecoder().decode(Self.self, from: data)
        guard report.schema == "swansong-resource-report-v1" else {
            throw SwanSDKIntegrationError.malformedContract(
                "Unsupported resource report schema: \(report.schema)"
            )
        }
        return report
    }
}

public struct SwanSDKSchemaSummary: Equatable, Sendable {
    public let title: String
    public let version: Int

    public static func load(from sdkRoot: URL) throws -> Self {
        let url = sdkRoot.appendingPathComponent("schema/swan.schema.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let document = object as? [String: Any],
              let title = document["title"] as? String,
              let properties = document["properties"] as? [String: Any],
              let schemaVersion = properties["schema_version"] as? [String: Any],
              let version = schemaVersion["const"] as? Int else {
            throw SwanSDKIntegrationError.malformedContract(
                "The SDK manifest schema does not declare schema_version."
            )
        }
        return Self(title: title, version: version)
    }
}

public struct SwanSDKPackageSummary: Equatable, Sendable {
    public let version: String

    public static func load(from sdkRoot: URL) throws -> Self {
        let text = try String(
            contentsOf: sdkRoot.appendingPathComponent("pyproject.toml"),
            encoding: .utf8
        )
        var isProjectTable = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                isProjectTable = line == "[project]"
                continue
            }
            guard isProjectTable, line.hasPrefix("version") else { continue }
            let pieces = line.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let value = pieces[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return Self(version: value) }
        }
        throw SwanSDKIntegrationError.malformedContract(
            "The SDK pyproject.toml does not declare project.version."
        )
    }
}

public struct SwanSDKToolchainSummary: Equatable, Sendable {
    public let nativePackages: [String]
    public let canonicalImage: String?

    public static func load(from sdkRoot: URL) throws -> Self {
        let text = try String(
            contentsOf: sdkRoot.appendingPathComponent("toolchain.lock"),
            encoding: .utf8
        )
        let lines = text.split(separator: "\n").map(String.init)
        return Self(
            nativePackages: lines.filter {
                !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("ci:")
                    && !$0.hasPrefix("cbrzeszczot/")
            },
            canonicalImage: lines.first { $0.hasPrefix("cbrzeszczot/") }
        )
    }
}

public enum SwanSDKJSONValue: Codable, Equatable, Sendable {
    case object([String: SwanSDKJSONValue])
    case array([SwanSDKJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: Self].self) { self = .object(value) }
        else if let value = try? container.decode([Self].self) { self = .array(value) }
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> SwanSDKJSONValue? {
        guard case let .object(values) = self else { return nil }
        return values[key]
    }

    public var displayString: String? {
        switch self {
        case let .string(value): value
        case let .number(value): value.rounded() == value ? String(Int(value)) : String(value)
        case let .bool(value): value ? "true" : "false"
        case .object, .array, .null: nil
        }
    }
}

public struct SwanSDKStructuredReport: Equatable, Sendable {
    public let schema: String
    public let documents: [SwanSDKJSONValue]
    public let formattedJSON: String

    public static func decode(
        _ data: Data,
        expectedSchema: String,
        jsonLines: Bool = false
    ) throws -> Self {
        let payloads: [Data]
        if jsonLines {
            payloads = data.split(separator: 0x0a).compactMap { line in
                let text = String(decoding: line, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : Data(text.utf8)
            }
        } else {
            payloads = [data]
        }
        guard !payloads.isEmpty else {
            throw SwanSDKIntegrationError.malformedContract(
                "The SDK returned no structured JSON."
            )
        }
        let documents = try payloads.map {
            try JSONDecoder().decode(SwanSDKJSONValue.self, from: $0)
        }
        for document in documents {
            guard document["schema"]?.displayString == expectedSchema else {
                let found = document["schema"]?.displayString ?? "missing"
                throw SwanSDKIntegrationError.malformedContract(
                    "Unsupported SDK report schema: \(found); expected \(expectedSchema)."
                )
            }
        }
        return Self(
            schema: expectedSchema,
            documents: documents,
            formattedJSON: try payloads.map(prettyJSON).joined(separator: "\n")
        )
    }
}

public struct SwanSDKFrameInputPlan: Codable, Equatable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public let frameIndex: UInt64
        public let inputs: [String]

        public init(frameIndex: UInt64, inputs: [String]) {
            self.frameIndex = frameIndex
            self.inputs = inputs
        }
    }

    public static let currentSchema = "swan-song-frame-input-plan-v1"

    public let schema: String
    public let totalFrames: UInt64
    public let events: [Event]

    public init(
        schema: String = Self.currentSchema,
        totalFrames: UInt64,
        events: [Event]
    ) {
        self.schema = schema
        self.totalFrames = totalFrames
        self.events = events
    }

    public static func decode(_ data: Data) throws -> Self {
        let plan = try JSONDecoder().decode(Self.self, from: data)
        guard plan.schema == Self.currentSchema else {
            throw SwanSDKIntegrationError.malformedContract(
                "Unsupported scenario plan schema: \(plan.schema)."
            )
        }
        return plan
    }

    public func formattedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self) + "\n"
    }
}

public struct SwanSDKEvidence: Equatable, Sendable {
    public let scenarioID: String
    public let directoryURL: URL
    public let frameURL: URL
    public let audioURL: URL
    public let planURL: URL
    public let evidence: SwanSDKJSONValue
    public let formattedPlan: String
    public let formattedEvidence: String
    public let audioMetrics: SwanSDKWAVMetrics?

    public static func load(
        projectRoot: URL,
        scenario: SwanSDKPlayContract.Scenario
    ) throws -> Self {
        let directory = projectRoot
            .appendingPathComponent("build/swansong", isDirectory: true)
            .appendingPathComponent(scenario.id, isDirectory: true)
        let evidenceURL = directory.appendingPathComponent("evidence.json")
        let evidenceData = try Data(contentsOf: evidenceURL)
        let evidence = try JSONDecoder().decode(SwanSDKJSONValue.self, from: evidenceData)
        let planURL = projectRoot.appendingPathComponent(scenario.plan)
        let planData = try Data(contentsOf: planURL)
        let formattedPlan = try prettyJSON(planData)
        return Self(
            scenarioID: scenario.id,
            directoryURL: directory,
            frameURL: directory.appendingPathComponent("frame.png"),
            audioURL: directory.appendingPathComponent("audio.wav"),
            planURL: planURL,
            evidence: evidence,
            formattedPlan: formattedPlan,
            formattedEvidence: try prettyJSON(evidenceData),
            audioMetrics: try? SwanSDKWAVMetrics.load(
                from: directory.appendingPathComponent("audio.wav")
            )
        )
    }
}

public struct SwanSDKWAVMetrics: Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let bitsPerSample: Int
    public let frameCount: Int

    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(frameCount) / Double(sampleRate)
    }

    public static func load(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        guard data.count >= 44,
              String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else {
            throw SwanSDKIntegrationError.malformedContract("Evidence audio is not a WAV file.")
        }
        func littleEndianUInt16(_ offset: Int) -> UInt16 {
            UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }
        func littleEndianUInt32(_ offset: Int) -> UInt32 {
            UInt32(data[offset])
                | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16
                | UInt32(data[offset + 3]) << 24
        }
        let channels = Int(littleEndianUInt16(22))
        let sampleRate = Int(littleEndianUInt32(24))
        let bits = Int(littleEndianUInt16(34))
        var dataSize = 0
        var cursor = 12
        while cursor + 8 <= data.count {
            let identifier = String(decoding: data[cursor..<(cursor + 4)], as: UTF8.self)
            let size = Int(littleEndianUInt32(cursor + 4))
            if identifier == "data" {
                dataSize = min(size, max(0, data.count - cursor - 8))
                break
            }
            cursor += 8 + size + (size % 2)
        }
        let bytesPerFrame = max(1, channels * max(1, bits / 8))
        return Self(
            sampleRate: sampleRate,
            channelCount: channels,
            bitsPerSample: bits,
            frameCount: dataSize / bytesPerFrame
        )
    }
}

private func prettyJSON(_ data: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: data)
    let formatted = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    return String(decoding: formatted, as: UTF8.self)
}
