import CryptoKit
import Darwin
import Foundation
import SwanSongKit

private struct RouteRunnerOptions {
    var debugToolsEnabled = false
    var romURL: URL?
    var routeURL: URL?
    var outputURL: URL?
    var captureURL: URL?
}

private enum AutomationCommand: String {
    case capturePlan = "capture-plan"
    case probeRectangle = "probe-rectangle"
    case recordRoute = "record-route"
    case verifyPair = "verify-pair"
}

private enum PlaytestCommand: String {
    case playtestPlan = "playtest-plan"
}

private struct PlaytestOptions {
    var debugToolsEnabled = false
    var romURL: URL?
    var planURL: URL?
    var outputURL: URL?
    var captureURL: URL?
}

private struct AutomationOptions {
    var debugToolsEnabled = false
    var projectWritesAllowed = false
    var projectURL: URL?
    var planURL: URL?
    var routeURL: URL?
    var outputURL: URL?
    var role: TranslationROMRole?
    var frameIndex: UInt64?
    var rectangle: EngineDisplayRectangle?
}

private struct RouteRunReport: Codable {
    static let currentSchema = "swan-song-route-run-report-v1"

    let schema: String
    let startedAt: Date
    let finishedAt: Date
    let passed: Bool
    let appVersion: String?
    let appBuild: String?
    let engineBackend: String
    let engineBuildID: String
    let engineLibrarySHA256: String?
    let openIPLIdentifier: String
    let romPath: String
    let romByteCount: Int
    let romChecksum: UInt16
    let romSHA256: String
    let routePath: String
    let routeSchema: String
    let routeCreatedAt: Date
    let hardwareModel: String
    let rtcSeedUnixSeconds: UInt64
    let totalFrames: UInt64
    let scheduledInputTransitions: Int
    let scheduledInputFrames: UInt64
    let finalFrameNumber: UInt64
    let expectedCheckpointSHA256: String
    let observedCheckpointSHA256: String
    let checkpointMatched: Bool
    let finalCapturePath: String?
}

private struct RouteRunnerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
private struct SwanSongRouteRunner {
    private static let usage = """
    Usage:
      SwanSongRouteRunner --enable-debug-tools --rom GAME.wsc --route ROUTE.json [--output REPORT.json] [--capture FINAL.png]
      SwanSongRouteRunner playtest-plan --enable-debug-tools --rom GAME.wsc --plan PLAN.json [--output REPORT.json] [--capture FINAL.png]
      SwanSongRouteRunner capture-plan --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json [--output REPORT.json]
      SwanSongRouteRunner probe-rectangle --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json --role original|patched --frame INDEX --rect X,Y,WIDTH,HEIGHT [--output REPORT.json]
      SwanSongRouteRunner record-route --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json [--output REPORT.json]
      SwanSongRouteRunner verify-pair --enable-debug-tools --allow-project-writes --project PROJECT --route ROUTE.json [--output REPORT.json]

    The legacy form replays an existing deterministic route. playtest-plan
    runs a bounded visual/audio observation without writing game state.
    capture-plan privately persists the exact plan, both native frames, all
    deterministic context bindings, and a pixel-diff report after Capture
    Intake succeeds. probe-rectangle replays one project role from clean boot,
    saves detailed display-owner provenance privately, and emits only hashes
    and counts. record-route turns a declarative frame/input plan into a
    route-v3 proof from Original. verify-pair replays that route against
    Original and Patched, runs Capture Intake, and emits both immutable
    evidence manifests.
    Project-writing commands require both explicit guard flags and only accept
    project-scoped input and output paths.
    """

    static func main() {
        if CommandLine.arguments.dropFirst().contains("--help")
            || CommandLine.arguments.dropFirst().contains("-h") {
            print(usage)
            return
        }
        do {
            let first = CommandLine.arguments.dropFirst().first
            if let first, let command = PlaytestCommand(rawValue: first) {
                try runPlaytest(command)
                return
            }
            if let first, let command = AutomationCommand(rawValue: first) {
                try runAutomation(command)
                return
            }
            let passed = try runReplay()
            if !passed { exit(1) }
        } catch {
            FileHandle.standardError.write(
                Data("SwanSongRouteRunner: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
    }

    private static func runPlaytest(_ command: PlaytestCommand) throws {
        let options = try parsePlaytestOptions()
        guard options.debugToolsEnabled else {
            throw RouteRunnerError(
                message: "Homebrew playtesting is a debug tool. Pass --enable-debug-tools explicitly."
            )
        }
        guard let romURL = options.romURL, let planURL = options.planURL else {
            throw RouteRunnerError(message: "Missing --rom or --plan.\n\n\(usage)")
        }
        switch command {
        case .playtestPlan:
            let planData = try readLocalFile(
                planURL,
                maximumBytes: 1_048_576,
                label: "frame/input plan"
            )
            let plan = try JSONDecoder().decode(
                TranslationFrameInputPlan.self,
                from: planData
            )
            let image = try LibraryGameImageImporter.image(from: romURL)
            let result = try SwanSongPlaytester.run(image: image, plan: plan)
            if let captureURL = options.captureURL {
                try result.png.write(
                    to: captureURL.standardizedFileURL,
                    options: [.withoutOverwriting]
                )
            }
            try emit(result.report, to: options.outputURL)
        }
    }

    private static func runReplay() throws -> Bool {
        let options = try parseOptions()
        guard options.debugToolsEnabled else {
            throw RouteRunnerError(
                message: "Route execution is a debug tool. Pass --enable-debug-tools explicitly."
            )
        }
        guard let romURL = options.romURL, let routeURL = options.routeURL else {
            throw RouteRunnerError(message: usage)
        }

        let startedAt = Date()
        let routeData = try Data(contentsOf: routeURL, options: [.mappedIfSafe])
        let routeDecoder = JSONDecoder()
        routeDecoder.dateDecodingStrategy = .iso8601
        let route = try routeDecoder.decode(TranslationRoute.self, from: routeData)
        try route.validateForProof()
        guard route.totalFrames >= 3 else {
            throw RouteRunnerError(
                message: "A route proof must contain at least three presented frames."
            )
        }
        guard let start = route.start,
              let rtc = start.rtc,
              let checkpoint = route.checkpoint else {
            throw RouteRunnerError(message: "The route proof is missing its start context or checkpoint.")
        }

        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let romSHA256 = sha256(rom)
        guard route.sourceROM.byteCount == rom.count,
              route.sourceROM.sha256 == romSHA256 else {
            throw RouteRunnerError(
                message: "The ROM does not match the route's bound source digest."
            )
        }
        let metadata = try EngineSession.inspect(rom: rom)
        let engine = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: rtc.seedUnixSeconds),
            hardwareModel: start.engineHardwareModel
        )
        guard engine.capabilities.contains(.execution) else {
            throw RouteRunnerError(message: "The bundled live engine cannot execute routes.")
        }
        guard engine.backendName == start.engine.backend,
              engine.buildID == start.engine.buildID else {
            throw RouteRunnerError(
                message: "The bundled engine identity differs from the route. Re-record the route with this SwanSong build."
            )
        }
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == start.engineHardwareModel else {
            throw RouteRunnerError(
                message: "The engine selected different hardware than the route recorded."
            )
        }

        var frameIndex: UInt64 = 0
        var scheduledInputFrames: UInt64 = 0
        var finalFrame: EngineVideoFrame?
        while frameIndex < route.totalFrames {
            let input = route.input(at: frameIndex)
            if !input.isEmpty { scheduledInputFrames += 1 }
            try engine.setInput(input)
            try engine.runFrame()
            finalFrame = try engine.videoFrame()
            frameIndex += 1
        }
        guard let finalFrame else {
            throw RouteRunnerError(message: "The route produced no video frames.")
        }

        let observedCheckpoint = try TranslationRouteCheckpoint.fingerprint(finalFrame)
        let checkpointMatched = checkpoint.matches(finalFrame)
        var capturePath: String?
        if let captureURL = options.captureURL {
            let png = try EngineFramePNGCodec.encode(finalFrame)
            try png.write(to: captureURL, options: .atomic)
            capturePath = captureURL.standardizedFileURL.path
        }
        let appIdentity = bundledAppIdentity()
        let report = RouteRunReport(
            schema: RouteRunReport.currentSchema,
            startedAt: startedAt,
            finishedAt: Date(),
            passed: checkpointMatched,
            appVersion: appIdentity.version,
            appBuild: appIdentity.build,
            engineBackend: engine.backendName,
            engineBuildID: engine.buildID,
            engineLibrarySHA256: engineLibraryURL().flatMap {
                try? sha256(Data(contentsOf: $0, options: [.mappedIfSafe]))
            },
            openIPLIdentifier: WonderSwanOpenIPL.identifier,
            romPath: romURL.standardizedFileURL.path,
            romByteCount: rom.count,
            romChecksum: metadata.computedChecksum,
            romSHA256: romSHA256,
            routePath: routeURL.standardizedFileURL.path,
            routeSchema: route.schema,
            routeCreatedAt: route.createdAt,
            hardwareModel: start.hardwareModel.rawValue,
            rtcSeedUnixSeconds: rtc.seedUnixSeconds,
            totalFrames: route.totalFrames,
            scheduledInputTransitions: route.events.count,
            scheduledInputFrames: scheduledInputFrames,
            finalFrameNumber: finalFrame.number,
            expectedCheckpointSHA256: checkpoint.sha256,
            observedCheckpointSHA256: observedCheckpoint,
            checkpointMatched: checkpointMatched,
            finalCapturePath: capturePath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let reportData = try encoder.encode(report)
        if let outputURL = options.outputURL {
            try reportData.write(to: outputURL, options: .atomic)
        } else {
            FileHandle.standardOutput.write(reportData)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        return checkpointMatched
    }

    private static func runAutomation(_ command: AutomationCommand) throws {
        let options = try parseAutomationOptions()
        guard options.debugToolsEnabled else {
            throw RouteRunnerError(
                message: "Translation Lab automation is a debug tool. Pass --enable-debug-tools explicitly."
            )
        }
        guard options.projectWritesAllowed else {
            throw RouteRunnerError(
                message: "Translation Lab automation writes immutable project evidence. Pass --allow-project-writes explicitly."
            )
        }
        guard let projectURL = options.projectURL else {
            throw RouteRunnerError(message: "Missing --project.\n\n\(usage)")
        }
        let project = try TranslationProject(projectDirectory: projectURL)
        if let outputURL = options.outputURL {
            try validateNewOutput(outputURL, project: project)
        }

        switch command {
        case .capturePlan:
            guard let planURL = options.planURL else {
                throw RouteRunnerError(message: "Missing --plan.\n\n\(usage)")
            }
            let planData = try readProjectFile(
                planURL,
                project: project,
                maximumBytes: 1_048_576,
                label: "frame/input plan"
            )
            let plan = try JSONDecoder().decode(
                TranslationFrameInputPlan.self,
                from: planData
            )
            let report = try TranslationLabAutomation.capturePlan(
                project: project,
                plan: plan
            )
            try emit(report, to: options.outputURL)
        case .probeRectangle:
            guard let planURL = options.planURL,
                  let role = options.role,
                  let frameIndex = options.frameIndex,
                  let rectangle = options.rectangle else {
                throw RouteRunnerError(
                    message: "Missing --plan, --role, --frame, or --rect.\n\n\(usage)"
                )
            }
            let planData = try readProjectFile(
                planURL,
                project: project,
                maximumBytes: 1_048_576,
                label: "frame/input plan"
            )
            let plan = try JSONDecoder().decode(
                TranslationFrameInputPlan.self,
                from: planData
            )
            let report = try TranslationDisplayOwnerProbe.run(
                project: project,
                role: role,
                plan: plan,
                frameIndex: frameIndex,
                rectangle: rectangle
            )
            try emit(report, to: options.outputURL)
        case .recordRoute:
            guard let planURL = options.planURL else {
                throw RouteRunnerError(message: "Missing --plan.\n\n\(usage)")
            }
            let planData = try readProjectFile(
                planURL,
                project: project,
                maximumBytes: 1_048_576,
                label: "frame/input plan"
            )
            let plan = try JSONDecoder().decode(
                TranslationFrameInputPlan.self,
                from: planData
            )
            let report = try TranslationLabAutomation.recordRoute(
                project: project,
                plan: plan
            )
            try emit(report, to: options.outputURL)
        case .verifyPair:
            guard let routeURL = options.routeURL else {
                throw RouteRunnerError(message: "Missing --route.\n\n\(usage)")
            }
            let routeData = try readProjectFile(
                routeURL,
                project: project,
                maximumBytes: 4_194_304,
                label: "route"
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let route = try decoder.decode(TranslationRoute.self, from: routeData)
            let report = try TranslationLabAutomation.verifyPair(
                project: project,
                route: route,
                routeURL: routeURL.standardizedFileURL
            )
            try emit(report, to: options.outputURL)
        }
    }

    private static func parseOptions() throws -> RouteRunnerOptions {
        var options = RouteRunnerOptions()
        var index = 1
        while index < CommandLine.arguments.count {
            let argument = CommandLine.arguments[index]
            switch argument {
            case "--enable-debug-tools":
                options.debugToolsEnabled = true
                index += 1
            case "--rom", "--route", "--output", "--capture":
                guard index + 1 < CommandLine.arguments.count else {
                    throw RouteRunnerError(message: "Missing value for \(argument).\n\n\(usage)")
                }
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                switch argument {
                case "--rom": options.romURL = url
                case "--route": options.routeURL = url
                case "--output": options.outputURL = url
                case "--capture": options.captureURL = url
                default: break
                }
                index += 2
            default:
                throw RouteRunnerError(message: "Unknown option \(argument).\n\n\(usage)")
            }
        }
        return options
    }

    private static func parseAutomationOptions() throws -> AutomationOptions {
        var options = AutomationOptions()
        var index = 2
        while index < CommandLine.arguments.count {
            let argument = CommandLine.arguments[index]
            switch argument {
            case "--enable-debug-tools":
                options.debugToolsEnabled = true
                index += 1
            case "--allow-project-writes":
                options.projectWritesAllowed = true
                index += 1
            case "--project", "--plan", "--route", "--output":
                guard index + 1 < CommandLine.arguments.count else {
                    throw RouteRunnerError(message: "Missing value for \(argument).\n\n\(usage)")
                }
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                switch argument {
                case "--project": options.projectURL = url
                case "--plan": options.planURL = url
                case "--route": options.routeURL = url
                case "--output": options.outputURL = url
                default: break
                }
                index += 2
            case "--role":
                guard index + 1 < CommandLine.arguments.count,
                      let role = TranslationROMRole(
                        rawValue: CommandLine.arguments[index + 1]
                      ) else {
                    throw RouteRunnerError(
                        message: "--role must be original or patched.\n\n\(usage)"
                    )
                }
                options.role = role
                index += 2
            case "--frame":
                guard index + 1 < CommandLine.arguments.count,
                      let frame = UInt64(CommandLine.arguments[index + 1]) else {
                    throw RouteRunnerError(
                        message: "--frame must be a nonnegative integer.\n\n\(usage)"
                    )
                }
                options.frameIndex = frame
                index += 2
            case "--rect":
                guard index + 1 < CommandLine.arguments.count else {
                    throw RouteRunnerError(message: "Missing value for --rect.\n\n\(usage)")
                }
                options.rectangle = try parseRectangle(
                    CommandLine.arguments[index + 1]
                )
                index += 2
            default:
                throw RouteRunnerError(message: "Unknown option \(argument).\n\n\(usage)")
            }
        }
        return options
    }

    private static func parseRectangle(_ value: String) throws -> EngineDisplayRectangle {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let x = UInt16(parts[0]),
              let y = UInt16(parts[1]),
              let width = UInt16(parts[2]),
              let height = UInt16(parts[3]),
              width > 0,
              height > 0 else {
            throw RouteRunnerError(
                message: "--rect must be X,Y,WIDTH,HEIGHT using native nonnegative coordinates.\n\n\(usage)"
            )
        }
        return EngineDisplayRectangle(x: x, y: y, width: width, height: height)
    }

    private static func parsePlaytestOptions() throws -> PlaytestOptions {
        var options = PlaytestOptions()
        var index = 2
        while index < CommandLine.arguments.count {
            let argument = CommandLine.arguments[index]
            switch argument {
            case "--enable-debug-tools":
                options.debugToolsEnabled = true
                index += 1
            case "--rom", "--plan", "--output", "--capture":
                guard index + 1 < CommandLine.arguments.count else {
                    throw RouteRunnerError(message: "Missing value for \(argument).\n\n\(usage)")
                }
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                switch argument {
                case "--rom": options.romURL = url
                case "--plan": options.planURL = url
                case "--output": options.outputURL = url
                case "--capture": options.captureURL = url
                default: break
                }
                index += 2
            default:
                throw RouteRunnerError(message: "Unknown option \(argument).\n\n\(usage)")
            }
        }
        return options
    }

    private static func readLocalFile(
        _ url: URL,
        maximumBytes: Int,
        label: String
    ) throws -> Data {
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard resolved == standardized,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= maximumBytes else {
            throw RouteRunnerError(
                message: "The \(label) must be a bounded, nonsymlink regular file."
            )
        }
        let data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
        guard data.count == byteCount else {
            throw RouteRunnerError(message: "The \(label) changed while it was being read.")
        }
        return data
    }

    private static func readProjectFile(
        _ url: URL,
        project: TranslationProject,
        maximumBytes: Int,
        label: String
    ) throws -> Data {
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard resolved == standardized,
              project.contains(standardized),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        guard let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= maximumBytes else {
            throw RouteRunnerError(
                message: "The \(label) must be a nonempty regular file no larger than \(maximumBytes) bytes."
            )
        }
        let data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count == byteCount else {
            throw RouteRunnerError(message: "The \(label) changed while it was being read.")
        }
        return data
    }

    private static func validateNewOutput(
        _ outputURL: URL,
        project: TranslationProject
    ) throws {
        let standardized = outputURL.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let parentValues = try parent.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard resolvedParent == parent,
              project.contains(standardized),
              parentValues.isDirectory == true,
              parentValues.isSymbolicLink != true,
              !FileManager.default.fileExists(atPath: standardized.path) else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
    }

    private static func emit<T: Encodable>(_ report: T, to outputURL: URL?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(report)
        data.append(0x0A)
        if let outputURL {
            try data.write(to: outputURL.standardizedFileURL, options: [.withoutOverwriting])
        } else {
            FileHandle.standardOutput.write(data)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func engineLibraryURL() -> URL? {
        if let directory = ProcessInfo.processInfo.environment["SWAN_ARES_ENGINE_DIR"],
           !directory.isEmpty {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("libSwanAresEngine.dylib")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let candidate = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Frameworks", isDirectory: true)
            .appendingPathComponent("libSwanAresEngine.dylib")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func bundledAppIdentity() -> (version: String?, build: String?) {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let infoURL = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return (nil, nil)
        }
        return (
            object["CFBundleShortVersionString"] as? String,
            object["CFBundleVersion"] as? String
        )
    }
}
