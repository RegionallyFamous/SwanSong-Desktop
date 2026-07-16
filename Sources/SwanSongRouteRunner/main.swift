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

    Replays a SwanSong deterministic input route from a clean power-on using
    the bundled engine. The explicit --enable-debug-tools flag is required.
    The command exits nonzero if the ROM, engine, route context, or final
    checkpoint does not exactly match the recorded proof.
    """

    static func main() {
        if CommandLine.arguments.dropFirst().contains("--help")
            || CommandLine.arguments.dropFirst().contains("-h") {
            print(usage)
            return
        }
        do {
            let passed = try run()
            if !passed { exit(1) }
        } catch {
            FileHandle.standardError.write(
                Data("SwanSongRouteRunner: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
    }

    private static func run() throws -> Bool {
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
