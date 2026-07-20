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
    case exportStaticAnalysisSeed = "export-static-analysis-seed"
    case probeRectangle = "probe-rectangle"
    case probeRectangleSource = "probe-rectangle-source"
    case recordRoute = "record-route"
    case verifyPair = "verify-pair"
}

private enum PlaytestCommand: String {
    case playtestPlan = "playtest-plan"
}

private enum CapabilityCommand: String {
    case engineCapability = "engine-capability"
}

private struct CapabilityOptions {
    var debugToolsEnabled = false
    var outputURL: URL?
}

private struct AutomationMethodCapability: Codable {
    let command: String
    let reportSchema: String
    let planSchema: String
    let maximumPlanFrames: UInt64
    let requiresDebugGuard: Bool
    let requiresProjectWriteGuard: Bool
    let cleanBootReplay: Bool
}

private struct SourceProbeMethodCapability: Codable {
    let command: String
    let reportSchema: String
    let privateDetailsSchema: String
    let blockedReportSchema: String
    let planSchema: String
    let maximumPlanFrames: UInt64
    let maximumRectanglePixels: Int
    let maximumTraceRecords: Int
    let selectedComponents: [String]
    let requiresEngineABI: UInt32
    let requiredEngineCapabilities: [String]
    let requiresDebugGuard: Bool
    let requiresProjectWriteGuard: Bool
    let cleanBootReplay: Bool
    let saveStateRestoreAllowed: Bool
}

private struct RouteRunnerEngineCapabilityReport: Codable {
    static let currentSchema = "swan-song-route-runner-engine-capability-v1"

    let schema: String
    let engineABI: UInt32
    let engineBackend: String
    let engineBuildID: String
    let engineCapabilitiesRaw: UInt64
    let loadedDylibPath: String
    let loadedDylibByteCount: Int
    let loadedDylibSHA256: String
    let capturePlan: AutomationMethodCapability
    let probeRectangleSource: SourceProbeMethodCapability
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
    var sourceProbeURL: URL?
    var outputURL: URL?
    var role: TranslationROMRole?
    var frameIndex: UInt64?
    var rectangle: EngineDisplayRectangle?
    var components: [EngineDisplaySourceComponent]?
    var authorizationURL: URL?
    var capabilityReceiptURL: URL?
    var captureIntakeCapabilityReceiptURL: URL?
    var methodCapabilityReceiptURL: URL?
    var qualifiedMethodCapabilityReceiptURL: URL?
    var methodNativeMarkerURL: URL?
    var captureFrameSealURL: URL?
    var runDirectoryURL: URL?
    var publicDiagnosticKAT = false
    var commercialAuthorizedCapture = false
    var commercialCaptureContractKAT = false
    var commercialAuthorizedSourceProbe = false
    var commercialSourceContractKAT = false
    var publicCaptureBlockedPrefix = "none"
    var publicCaptureBlockedPrefixWasProvided = false
    var baseCapabilityKAT = false

    var hasAuthorizationEnvelopeOption: Bool {
        authorizationURL != nil
            || capabilityReceiptURL != nil
            || captureIntakeCapabilityReceiptURL != nil
            || methodCapabilityReceiptURL != nil
            || qualifiedMethodCapabilityReceiptURL != nil
            || methodNativeMarkerURL != nil
            || captureFrameSealURL != nil
            || runDirectoryURL != nil
            || publicDiagnosticKAT
            || commercialAuthorizedCapture
            || commercialCaptureContractKAT
            || commercialAuthorizedSourceProbe
            || commercialSourceContractKAT
            || publicCaptureBlockedPrefixWasProvided
    }
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

private struct SwanSongRouteRunner {
    private static let usage = """
    Usage:
      SwanSongRouteRunner --enable-debug-tools --rom GAME.wsc --route ROUTE.json [--output REPORT.json] [--capture FINAL.png]
      SwanSongRouteRunner engine-capability --enable-debug-tools [--output REPORT.json]
      SwanSongRouteRunner playtest-plan --enable-debug-tools --rom GAME.wsc --plan PLAN.json [--output REPORT.json] [--capture FINAL.png]
      SwanSongRouteRunner capture-plan --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json [--output REPORT.json]
        [--public-diagnostic-kat --authorization RUN/authorization.json --capability-receipt C.json --capture-intake-capability-receipt CAPTURE_INTAKE_C.json --method-capability-receipt M.json --run-directory RUN]
        [--public-capture-blocked-prefix none|original-complete]
      SwanSongRouteRunner export-static-analysis-seed --enable-debug-tools --allow-project-writes --project PROJECT --source-probe SOURCE_PROBE_DETAILS.json [--output REPORT.json]
      SwanSongRouteRunner probe-rectangle --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json --role original|patched --frame INDEX --rect X,Y,WIDTH,HEIGHT [--output REPORT.json]
      SwanSongRouteRunner probe-rectangle-source --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json --role original|patched --frame INDEX --rect X,Y,WIDTH,HEIGHT [--components mapCell,palette,raster,spriteAttribute] [--output REPORT.json]
        --base-capability-kat
      SwanSongRouteRunner probe-rectangle-source --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json --role original --frame 2 --rect 8,8,1,1 --components raster [--output RUN/report.json]
        [--public-diagnostic-kat --authorization RUN/authorization.json --capability-receipt C.json --method-capability-receipt M.json --method-native-marker MARKER.json --run-directory RUN]
      SwanSongRouteRunner probe-rectangle-source --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json --role original --frame 29 --rect 8,8,1,1 --components raster [--output RUN/report.json]
        --commercial-source-contract-kat --capture-frame-seal SEAL.json --authorization RUN/authorization.json --capability-receipt C.json --method-capability-receipt M.json --method-native-marker MARKER.json --run-directory RUN
      SwanSongRouteRunner probe-rectangle-source --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json --role original --frame 1839 --rect 48,56,120,16 --components raster [--output RUN/report.json]
        --commercial-authorized-source-probe --capture-frame-seal SEAL.json --authorization RUN/authorization.json --capability-receipt C.json --method-capability-receipt M.json --qualified-method-capability-receipt M2.json --method-native-marker MARKER.json --run-directory RUN
      SwanSongRouteRunner record-route --enable-debug-tools --allow-project-writes --project PROJECT --plan PLAN.json [--output REPORT.json]
      SwanSongRouteRunner verify-pair --enable-debug-tools --allow-project-writes --project PROJECT --route ROUTE.json [--output REPORT.json]

    The legacy form replays an existing deterministic route. playtest-plan
    runs a bounded visual/audio observation without writing game state.
    capture-plan privately persists the exact plan, both native frames, all
    deterministic context bindings, and a pixel-diff report after Capture
    Intake succeeds. probe-rectangle replays one project role from clean boot,
    saves detailed display-owner provenance privately, and emits only hashes
    and counts. probe-rectangle-source traces selected ABI 9 display components
    to bounded upstream cartridge lineage, while export-static-analysis-seed
    revalidates one complete private probe for exact-context disassembly.
    record-route turns a declarative frame/input plan into a route-v3 proof
    from Original. verify-pair replays that route against Original and Patched,
    runs Capture Intake, and emits both immutable evidence manifests.
    Project-writing commands require both explicit guard flags and only accept
    project-scoped input and output paths.
    engine-capability reports the exact dladdr-resolved engine image and the
    bounded command/schema/limit contract compiled into this runner.
    """

    static func main() {
        if CommandLine.arguments.dropFirst().contains("--help")
            || CommandLine.arguments.dropFirst().contains("-h") {
            print(usage)
            return
        }
        do {
            let first = CommandLine.arguments.dropFirst().first
            if let first, let command = CapabilityCommand(rawValue: first) {
                try runCapability(command)
                return
            }
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

    private static func runCapability(_ command: CapabilityCommand) throws {
        let options = try parseCapabilityOptions()
        guard options.debugToolsEnabled else {
            throw RouteRunnerError(
                message: "Engine capability inspection is a debug tool. Pass --enable-debug-tools explicitly."
            )
        }
        switch command {
        case .engineCapability:
            let engine = try EngineSession(
                rtcMode: .deterministic(seedUnixSeconds: 946_684_800),
                hardwareModel: .wonderSwanColor
            )
            let image = try loadedEngineImage()
            let capabilities = engine.capabilities
            let required: [(EngineCapabilities, String)] = [
                (.displayProvenance, "displayProvenance"),
                (.displaySourceProvenance, "displaySourceProvenance"),
                (.displaySourceComponentSelection, "displaySourceComponentSelection"),
                (.executedSourceReadContext, "executedSourceReadContext"),
                (.displaySpriteAttributeProvenance, "displaySpriteAttributeProvenance"),
            ]
            guard engine.abiVersion == 9,
                  required.allSatisfy({ capabilities.contains($0.0) }) else {
                throw RouteRunnerError(
                    message: "The loaded engine does not satisfy the ABI-9 source-probe method contract."
                )
            }
            let report = RouteRunnerEngineCapabilityReport(
                schema: RouteRunnerEngineCapabilityReport.currentSchema,
                engineABI: engine.abiVersion,
                engineBackend: engine.backendName,
                engineBuildID: engine.buildID,
                engineCapabilitiesRaw: capabilities.rawValue,
                loadedDylibPath: image.url.path,
                loadedDylibByteCount: image.data.count,
                loadedDylibSHA256: sha256(image.data),
                capturePlan: AutomationMethodCapability(
                    command: AutomationCommand.capturePlan.rawValue,
                    reportSchema: TranslationPersistedCaptureReport.currentSchema,
                    planSchema: TranslationFrameInputPlan.currentSchema,
                    maximumPlanFrames: TranslationFrameInputPlan.maximumFrames,
                    requiresDebugGuard: true,
                    requiresProjectWriteGuard: true,
                    cleanBootReplay: true
                ),
                probeRectangleSource: SourceProbeMethodCapability(
                    command: AutomationCommand.probeRectangleSource.rawValue,
                    reportSchema: TranslationDisplaySourceProbeReport.currentSchema,
                    privateDetailsSchema: TranslationDisplaySourceProbeDetails.currentSchema,
                    blockedReportSchema: TranslationDisplaySourceProbeBlockedDiagnostic.currentSchema,
                    planSchema: TranslationFrameInputPlan.currentSchema,
                    maximumPlanFrames: TranslationFrameInputPlan.maximumFrames,
                    maximumRectanglePixels: TranslationDisplaySourceProbe.maximumRectanglePixels,
                    maximumTraceRecords: TranslationDisplaySourceProbe.maximumTraceRecords,
                    selectedComponents: EngineDisplaySourceComponent.allCases.map(\.rawValue),
                    requiresEngineABI: 9,
                    requiredEngineCapabilities: required.map(\.1),
                    requiresDebugGuard: true,
                    requiresProjectWriteGuard: true,
                    cleanBootReplay: true,
                    saveStateRestoreAllowed: false
                )
            )
            try emit(report, to: options.outputURL)
        }
    }

    private static func parseCapabilityOptions() throws -> CapabilityOptions {
        var options = CapabilityOptions()
        var index = 2
        while index < CommandLine.arguments.count {
            let argument = CommandLine.arguments[index]
            switch argument {
            case "--enable-debug-tools":
                options.debugToolsEnabled = true
                index += 1
            case "--output":
                guard index + 1 < CommandLine.arguments.count else {
                    throw RouteRunnerError(message: "Missing value for --output.\n\n\(usage)")
                }
                options.outputURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                index += 2
            default:
                throw RouteRunnerError(message: "Unknown option \(argument).\n\n\(usage)")
            }
        }
        return options
    }

    private static func loadedEngineImage() throws -> (url: URL, data: Data) {
        guard let process = dlopen(nil, RTLD_NOW) else {
            throw RouteRunnerError(message: "Could not inspect the current process image table.")
        }
        defer { dlclose(process) }
        guard let symbol = dlsym(process, "swan_engine_abi_version") else {
            throw RouteRunnerError(message: "The loaded engine ABI symbol is unavailable.")
        }
        var information = Dl_info()
        guard dladdr(symbol, &information) != 0,
              let name = information.dli_fname else {
            throw RouteRunnerError(message: "dladdr could not resolve the loaded engine image.")
        }
        let canonicalPath: String
        do {
            canonicalPath = try SwanSongAuthorizedPathPolicy.canonicalExistingPath(
                String(cString: name)
            )
        } catch {
            throw RouteRunnerError(message: "The loaded engine image path is not canonical.")
        }
        let resolved = URL(fileURLWithPath: canonicalPath)
        let values = try resolved.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let expectedSize = values.fileSize,
              expectedSize > 0 else {
            throw RouteRunnerError(message: "The loaded engine image is not a nonempty regular file.")
        }
        let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
        guard data.count == expectedSize else {
            throw RouteRunnerError(message: "The loaded engine image changed while it was read.")
        }
        return (resolved, data)
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
        if options.baseCapabilityKAT, command != .probeRectangleSource {
            throw RouteRunnerError(
                message: "STOP_PREEXECUTION_CAPABILITY: --base-capability-kat is valid only for probe-rectangle-source."
            )
        }
        if options.hasAuthorizationEnvelopeOption,
           command != .capturePlan,
           command != .probeRectangleSource {
            throw RouteRunnerError(
                message: "STOP_PREEXECUTION_CAPABILITY: authorization-envelope options are not valid for \(command.rawValue)."
            )
        }
        if command == .capturePlan, options.hasAuthorizationEnvelopeOption {
            let modeCount = [
                options.publicDiagnosticKAT,
                options.commercialAuthorizedCapture,
                options.commercialCaptureContractKAT,
            ].filter { $0 }.count
            guard let planURL = options.planURL,
                  let authorizationURL = options.authorizationURL,
                  let capabilityReceiptURL = options.capabilityReceiptURL,
                  let captureIntakeCapabilityReceiptURL =
                    options.captureIntakeCapabilityReceiptURL,
                  let methodCapabilityReceiptURL = options.methodCapabilityReceiptURL,
                  let runDirectoryURL = options.runDirectoryURL,
                  modeCount == 1,
                  options.commercialAuthorizedCapture
                    ? options.qualifiedMethodCapabilityReceiptURL != nil
                    : options.qualifiedMethodCapabilityReceiptURL == nil,
                  (options.publicDiagnosticKAT
                    || !options.publicCaptureBlockedPrefixWasProvided),
                  options.methodNativeMarkerURL == nil,
                  options.captureFrameSealURL == nil,
                  !options.commercialAuthorizedSourceProbe,
                  !options.commercialSourceContractKAT else {
                throw RouteRunnerError(
                    message: "STOP_PREEXECUTION_CAPABILITY: an authorized capture-plan requires exactly one public, public commercial-contract, or commercial mode and the complete mode-specific A/C/Capture-Intake-C/M/run-directory input set; source-probe markers are not part of this contract.\n\n\(usage)"
                )
            }
            try AuthorizedCapturePlanRunner.run(AuthorizedCapturePlanInvocation(
                projectURL: projectURL,
                planURL: planURL,
                outputURL: options.outputURL,
                authorizationURL: authorizationURL,
                capabilityReceiptURL: capabilityReceiptURL,
                captureIntakeCapabilityReceiptURL:
                    captureIntakeCapabilityReceiptURL,
                methodCapabilityReceiptURL: methodCapabilityReceiptURL,
                qualifiedMethodCapabilityReceiptURL:
                    options.qualifiedMethodCapabilityReceiptURL,
                runDirectoryURL: runDirectoryURL,
                blockedPrefix: options.publicCaptureBlockedPrefix,
                publicDiagnosticKAT: options.publicDiagnosticKAT,
                commercialAuthorizedCapture: options.commercialAuthorizedCapture,
                commercialContractKAT: options.commercialCaptureContractKAT
            ))
            return
        }
        if command == .probeRectangleSource, options.hasAuthorizationEnvelopeOption {
            guard !options.baseCapabilityKAT else {
                throw RouteRunnerError(
                    message: "STOP_PREEXECUTION_CAPABILITY: --base-capability-kat and authorized source-probe modes are disjoint."
                )
            }
            let modeCount = [
                options.publicDiagnosticKAT,
                options.commercialSourceContractKAT,
                options.commercialAuthorizedSourceProbe,
            ].filter { $0 }.count
            guard let planURL = options.planURL,
                  let role = options.role,
                  let frameIndex = options.frameIndex,
                  let rectangle = options.rectangle,
                  let authorizationURL = options.authorizationURL,
                  let capabilityReceiptURL = options.capabilityReceiptURL,
                  let methodCapabilityReceiptURL = options.methodCapabilityReceiptURL,
                  let methodNativeMarkerURL = options.methodNativeMarkerURL,
                  let runDirectoryURL = options.runDirectoryURL,
                  modeCount == 1,
                  !options.commercialAuthorizedCapture,
                  !options.commercialCaptureContractKAT,
                  options.commercialAuthorizedSourceProbe
                    ? options.qualifiedMethodCapabilityReceiptURL != nil
                    : options.qualifiedMethodCapabilityReceiptURL == nil,
                  options.publicDiagnosticKAT
                    ? options.captureFrameSealURL == nil
                    : options.captureFrameSealURL != nil,
                  options.captureIntakeCapabilityReceiptURL == nil,
                  !options.publicCaptureBlockedPrefixWasProvided else {
                throw RouteRunnerError(
                    message: "STOP_PREEXECUTION_CAPABILITY: an authorized source probe requires exactly one diagnostic, public capture-contract, or commercial mode and its complete A/C/M/marker/seal/M2 input set.\n\n\(usage)"
                )
            }
            let components = (options.components
                ?? EngineDisplaySourceComponent.allCases).sorted {
                    $0.rawValue < $1.rawValue
                }
            try AuthorizedSourceProbeRunner.run(AuthorizedSourceProbeInvocation(
                projectURL: projectURL,
                planURL: planURL,
                role: role,
                frameIndex: frameIndex,
                rectangle: rectangle,
                components: components,
                outputURL: options.outputURL,
                authorizationURL: authorizationURL,
                capabilityReceiptURL: capabilityReceiptURL,
                methodCapabilityReceiptURL: methodCapabilityReceiptURL,
                qualifiedMethodCapabilityReceiptURL:
                    options.qualifiedMethodCapabilityReceiptURL,
                methodNativeMarkerURL: methodNativeMarkerURL,
                captureFrameSealURL: options.captureFrameSealURL,
                runDirectoryURL: runDirectoryURL,
                publicDiagnosticKAT: options.publicDiagnosticKAT,
                commercialContractKAT: options.commercialSourceContractKAT,
                commercialAuthorizedSourceProbe:
                    options.commercialAuthorizedSourceProbe
            ))
            return
        }
        if command == .probeRectangleSource, !options.baseCapabilityKAT {
            throw RouteRunnerError(
                message: "STOP_PREEXECUTION_CAPABILITY: probe-rectangle-source requires either the explicit public base-capability KAT or the complete public diagnostic A/C/M/marker envelope."
            )
        }
        if command == .probeRectangleSource {
            try validateBaseSourceProbeKAT(options: options, projectURL: projectURL)
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
        case .exportStaticAnalysisSeed:
            guard let sourceProbeURL = options.sourceProbeURL else {
                throw RouteRunnerError(
                    message: "Missing --source-probe.\n\n\(usage)"
                )
            }
            _ = try readProjectFile(
                sourceProbeURL,
                project: project,
                maximumBytes: 64 * 1_048_576,
                label: "source-probe details"
            )
            let report = try TranslationStaticAnalysisSeedExporter.run(
                project: project,
                sourceProbeDetailsURL: sourceProbeURL.standardizedFileURL
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
        case .probeRectangleSource:
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
            do {
                let report = try TranslationDisplaySourceProbe.run(
                    project: project,
                    role: role,
                    plan: plan,
                    frameIndex: frameIndex,
                    rectangle: rectangle,
                    components: options.components
                        ?? EngineDisplaySourceComponent.allCases
                )
                try emit(report, to: options.outputURL)
            } catch let diagnostic as TranslationDisplaySourceProbeBlockedDiagnostic {
                try emit(diagnostic, to: options.outputURL)
            }
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

    private static func validateBaseSourceProbeKAT(
        options: AutomationOptions,
        projectURL: URL
    ) throws {
        guard options.baseCapabilityKAT,
              options.role == .original,
              options.frameIndex == 2,
              options.components == [.raster],
              let planURL = options.planURL,
              let rectangle = options.rectangle else {
            throw RouteRunnerError(
                message: "STOP_PREEXECUTION_CAPABILITY: the base source-probe KAT arguments are not the pinned public control."
            )
        }
        let allowedRectangles: Set<String> = [
            "8,8,1,1", "0,0,1,1", "0,0,128,32", "0,0,129,32",
        ]
        let rectangleKey = "\(rectangle.x),\(rectangle.y),\(rectangle.width),\(rectangle.height)"
        guard allowedRectangles.contains(rectangleKey) else {
            throw RouteRunnerError(
                message: "STOP_PREEXECUTION_CAPABILITY: the base source-probe KAT rectangle is not allowlisted."
            )
        }
        let projectManifestURL = projectURL.appendingPathComponent("project.json")
        let projectData = try readLocalFile(
            projectManifestURL,
            maximumBytes: 1_048_576,
            label: "base-KAT project manifest"
        )
        let planData = try readLocalFile(
            planURL,
            maximumBytes: 1_048_576,
            label: "base-KAT frame/input plan"
        )
        guard sha256(projectData)
                == "000407d961fc3f0369b5d2aa3c67b01dd176657e1fc895443d677770b05a6af7",
              sha256(planData)
                == "76ca74825861056f5ee07d1c1cc6efd024d6b25440232a4f69e1bb20265b5e44" else {
            throw RouteRunnerError(
                message: "STOP_PREEXECUTION_CAPABILITY: the base source-probe KAT project or plan is not the pinned public fixture."
            )
        }
        let project = try TranslationProject(projectDirectory: projectURL)
        let romData = try readLocalFile(
            project.romURL(for: .original),
            maximumBytes: 16 * 1_048_576,
            label: "base-KAT public ROM"
        )
        let allowedROMs: Set<String> = [
            "3c2a3814ae9c93331370e70e9c3c4afb3e2b2c61a8d8a2e09e6f119857d7f20d",
            "c1df06910376640391b3342889effebe4c4302402dadaa2f1e0d7786f4c09ced",
        ]
        guard allowedROMs.contains(sha256(romData)) else {
            throw RouteRunnerError(
                message: "STOP_PREEXECUTION_CAPABILITY: the base source-probe KAT ROM is not an allowlisted public fixture."
            )
        }
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
            case "--public-diagnostic-kat":
                options.publicDiagnosticKAT = true
                index += 1
            case "--commercial-authorized-capture":
                options.commercialAuthorizedCapture = true
                index += 1
            case "--commercial-capture-contract-kat":
                options.commercialCaptureContractKAT = true
                index += 1
            case "--commercial-source-contract-kat":
                options.commercialSourceContractKAT = true
                index += 1
            case "--commercial-authorized-source-probe":
                options.commercialAuthorizedSourceProbe = true
                index += 1
            case "--base-capability-kat":
                options.baseCapabilityKAT = true
                index += 1
            case "--public-capture-blocked-prefix":
                guard index + 1 < CommandLine.arguments.count else {
                    throw RouteRunnerError(
                        message: "Missing value for --public-capture-blocked-prefix.\n\n\(usage)"
                    )
                }
                options.publicCaptureBlockedPrefix = CommandLine.arguments[index + 1]
                options.publicCaptureBlockedPrefixWasProvided = true
                index += 2
            case "--project", "--plan", "--route", "--source-probe", "--output",
                 "--authorization", "--capability-receipt",
                 "--capture-intake-capability-receipt",
                 "--method-capability-receipt",
                 "--qualified-method-capability-receipt", "--method-native-marker",
                 "--capture-frame-seal",
                 "--run-directory":
                guard index + 1 < CommandLine.arguments.count else {
                    throw RouteRunnerError(message: "Missing value for \(argument).\n\n\(usage)")
                }
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                switch argument {
                case "--project": options.projectURL = url
                case "--plan": options.planURL = url
                case "--route": options.routeURL = url
                case "--source-probe": options.sourceProbeURL = url
                case "--output": options.outputURL = url
                case "--authorization": options.authorizationURL = url
                case "--capability-receipt": options.capabilityReceiptURL = url
                case "--capture-intake-capability-receipt":
                    options.captureIntakeCapabilityReceiptURL = url
                case "--method-capability-receipt": options.methodCapabilityReceiptURL = url
                case "--qualified-method-capability-receipt":
                    options.qualifiedMethodCapabilityReceiptURL = url
                case "--method-native-marker": options.methodNativeMarkerURL = url
                case "--capture-frame-seal": options.captureFrameSealURL = url
                case "--run-directory": options.runDirectoryURL = url
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
            case "--components":
                guard index + 1 < CommandLine.arguments.count else {
                    throw RouteRunnerError(message: "Missing value for --components.\n\n\(usage)")
                }
                options.components = try parseComponents(
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

    private static func parseComponents(
        _ value: String
    ) throws -> [EngineDisplaySourceComponent] {
        let names = value.split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        let components = names.compactMap(EngineDisplaySourceComponent.init(rawValue:))
        guard !names.isEmpty,
              components.count == names.count,
              Set(components).count == components.count else {
            throw RouteRunnerError(
                message: "--components must be a nonempty, unique comma-separated list containing mapCell, raster, palette, or spriteAttribute.\n\n\(usage)"
            )
        }
        return components
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

SwanSongRouteRunner.main()
