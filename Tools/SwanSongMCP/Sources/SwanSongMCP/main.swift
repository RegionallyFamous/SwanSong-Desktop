import CryptoKit
import Foundation
import SwanSongKit

private typealias JSONDictionary = [String: Any]

private struct SwanSongMCPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class LiveAppClient: @unchecked Sendable {
    func request(
        method: String,
        arguments: JSONDictionary = [:]
    ) throws -> (String, JSONDictionary) {
        let argumentData = try JSONSerialization.data(
            withJSONObject: arguments,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let argumentJSON = String(decoding: argumentData, as: UTF8.self)
        let response = try SwanSongUnixSocketIO.connectAndExchange(
            request: SwanSongLocalMCPRequest(
                method: method,
                argumentsJSON: argumentJSON
            )
        )
        if let error = response.error {
            throw SwanSongMCPError(message: error)
        }
        guard let json = response.json,
              let dictionary = try JSONSerialization.jsonObject(
                with: Data(json.utf8)
              ) as? JSONDictionary else {
            throw SwanSongMCPError(message: "SwanSong returned an invalid response.")
        }
        return (json, dictionary)
    }
}

private final class ObservedPlayRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var session: TranslationObservedPlaySession?

    func start(
        project: TranslationProject,
        role: TranslationROMRole
    ) throws -> TranslationObservedPlayStartReport {
        lock.lock()
        defer { lock.unlock() }
        guard session == nil else {
            throw SwanSongMCPError(
                message: "An observed-play session is already active. Finish or cancel it first."
            )
        }
        try TranslationObservedPlaySession.markAbandonedSessionsInterrupted(
            project: project
        )
        let created = try TranslationObservedPlaySession(project: project, role: role)
        let report = try created.startReport()
        session = created
        return report
    }

    func resume(
        project: TranslationProject,
        sessionID: String
    ) throws -> TranslationObservedPlayResumeReport {
        lock.lock()
        defer { lock.unlock() }
        guard session == nil else {
            throw SwanSongMCPError(
                message: "An observed-play session is already active. Finish or cancel it first."
            )
        }
        try TranslationObservedPlaySession.markAbandonedSessionsInterrupted(
            project: project
        )
        let recovered = try TranslationObservedPlaySession.resume(
            project: project,
            sessionID: sessionID
        )
        let report = try recovered.resumeReport()
        session = recovered
        return report
    }

    func step(
        sessionID: String,
        inputs: [String],
        frames: UInt64
    ) throws -> TranslationObservedPlayStepCapture {
        lock.lock()
        defer { lock.unlock() }
        let current = try requireSession(sessionID)
        return try current.step(inputs: inputs, frames: frames)
    }

    func sequence(
        sessionID: String,
        segments: [TranslationObservedPlaySequenceSegment]
    ) throws -> TranslationObservedPlaySequenceCapture {
        lock.lock()
        defer { lock.unlock() }
        let current = try requireSession(sessionID)
        return try current.stepSequence(segments)
    }

    func branch(
        sessionID: String,
        throughFrame: UInt64
    ) throws -> TranslationObservedPlayBranchReport {
        lock.lock()
        defer { lock.unlock() }
        let current = try requireSession(sessionID)
        let branch = try current.branch(throughFrame: throughFrame)
        do {
            _ = try current.cancel()
            session = branch.session
            return branch.report
        } catch {
            _ = try? branch.session.cancel()
            throw error
        }
    }

    func finish(sessionID: String) throws -> TranslationObservedPlayFinishReport {
        lock.lock()
        defer { lock.unlock() }
        let current = try requireSession(sessionID)
        let report = try current.finish()
        session = nil
        return report
    }

    func cancel(sessionID: String) throws -> TranslationObservedPlayCancelReport {
        lock.lock()
        defer { lock.unlock() }
        let current = try requireSession(sessionID)
        let report = try current.cancel()
        session = nil
        return report
    }

    private func requireSession(
        _ sessionID: String
    ) throws -> TranslationObservedPlaySession {
        guard let session, session.id == sessionID else {
            throw SwanSongMCPError(message: "That observed-play session is not active.")
        }
        return session
    }
}

@main
private enum SwanSongMCPServer {
    private static let protocolVersion = "2025-11-25"
    private static let liveApp = LiveAppClient()
    private static let observedPlay = ObservedPlayRegistry()
    private static let instructions = "Controls a running SwanSong app through its opt-in local bridge, runs guarded Translation Lab evidence workflows, and can execute bounded deterministic homebrew playtest plans through SwanSong's own engine. Studio tools expose only one already-open project slot without its name or path, and invoke only a fixed SDK 0.5 allowlist after confirmProjectWrites=true: doctor, assets, build, test, play, play-all, profile, optimize preview, fuzz, lab, one-shot dev, migration preview, and hardware capacity. Playtest and observed-step tools return a rendered game frame and audio window only when confirmShareCapture=true. A single playtest may also return the SDK's bounded, structurally validated semantic trace when captureSDKTrace=true and confirmShareSDKTrace=true. The server must never expose ROM, save, state, persistence, raw RAM, tile, palette, map-cell, sprite/OAM attribute, CPU-writer, conservative-origin, cartridge-range, address, or mapper values. Translation tools only accept project-contained files and require confirmProjectWrites=true. Persisted translation captures privately retain both native frames, the exact plan, deterministic context hashes, and pixel-diff evidence inside the selected project. Display-owner probes and static-analysis seeds retain detailed source evidence privately and return only hashes and aggregate counts. Observed play holds a private ownership lease, atomically saves its cumulative from-boot plan after every step, marks crash-abandoned sessions interrupted, recovers only by clean-boot plan replay, and creates final evidence only by another clean-boot replay. A successful execution is observation evidence, not proof that a game mechanic passed; inspect the frame, listen to relevant audio, and exercise the declared game contract."

    static func main() {
        if Array(CommandLine.arguments.dropFirst()) == [
            "--signed-release-source-lineage-context-kat"
        ] {
            do {
                let result = try TranslationDisplaySourceProbe
                    .signedReleaseExecutedReadContextKAT()
                FileHandle.standardOutput.write(Data("\(result)\n".utf8))
            } catch {
                FileHandle.standardError.write(
                    Data("SwanSongMCP: signed release context control failed\n".utf8)
                )
                exit(1)
            }
            return
        }
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            do {
                if let response = try response(to: Data(line.utf8)) {
                    try write(response)
                }
            } catch {
                let failure = rpcError(
                    id: NSNull(),
                    code: -32603,
                    message: error.localizedDescription
                )
                try? write(failure)
            }
        }
    }

    private static func response(to data: Data) throws -> JSONDictionary? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let request = object as? JSONDictionary,
              request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            return rpcError(id: requestID(from: object), code: -32600, message: "Invalid Request")
        }

        // Notifications intentionally have no response.
        guard let id = request["id"] else { return nil }
        let parameters = request["params"] as? JSONDictionary ?? [:]
        switch method {
        case "initialize":
            return rpcResult(
                id: id,
                result: [
                    "protocolVersion": protocolVersion,
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "swansong", "version": "1.0.0"],
                    "instructions": instructions,
                ]
            )
        case "ping":
            return rpcResult(id: id, result: [:])
        case "tools/list":
            return rpcResult(id: id, result: ["tools": tools])
        case "tools/call":
            guard let name = parameters["name"] as? String else {
                return rpcError(id: id, code: -32602, message: "Tool name is required")
            }
            let arguments = parameters["arguments"] as? JSONDictionary ?? [:]
            return rpcResult(id: id, result: callTool(name: name, arguments: arguments))
        default:
            return rpcError(id: id, code: -32601, message: "Method not found")
        }
    }

    private static func requestID(from object: Any) -> Any {
        (object as? JSONDictionary)?["id"] ?? NSNull()
    }

    private static func rpcResult(id: Any, result: Any) -> JSONDictionary {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func rpcError(id: Any, code: Int, message: String) -> JSONDictionary {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message],
        ]
    }

    private static func write(_ response: JSONDictionary) throws {
        var data = try JSONSerialization.data(
            withJSONObject: response,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static var tools: [JSONDictionary] {
        [
            tool(
                name: "swansong_status",
                title: "Read SwanSong Status",
                description: "Read limited state from the running SwanSong app. Returns the current section, library count, and playback readiness without game titles, paths, ROMs, saves, memory, or screenshots.",
                inputSchema: objectSchema(),
                readOnly: true,
                destructive: false,
                idempotent: true
            ),
            tool(
                name: "swansong_navigate",
                title: "Navigate SwanSong",
                description: "Change the visible SwanSong section while no game is running.",
                inputSchema: objectSchema(
                    properties: [
                        "section": enumSchema(
                            ["library", "favorites", "recent", "homebrew", "patches", "pocket", "translation", "studio"],
                            description: "The destination section."
                        ),
                    ],
                    required: ["section"]
                ),
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                name: "swansong_player",
                title: "Control SwanSong Playback",
                description: "Start the already-selected library game, pause, resume, or stop the running player. The tool cannot choose a file or reveal game data.",
                inputSchema: objectSchema(
                    properties: [
                        "action": enumSchema(
                            ["play-selected", "pause", "resume", "stop"],
                            description: "The playback action."
                        ),
                    ],
                    required: ["action"]
                ),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_studio_projects",
                title: "Read SwanSong Studio Projects",
                description: "Read bounded status for the single project already open in Studio. Returns counts, readiness, and resolved tool versions without project names, paths, source, assets, ROMs, diagnostics, or evidence.",
                inputSchema: objectSchema(),
                readOnly: true,
                destructive: false,
                idempotent: true
            ),
            tool(
                name: "swansong_studio_action",
                title: "Run SwanSong Studio Action",
                description: "Invoke one existing SDK action against the project already open in Studio. The fixed allowlist cannot choose paths, edit files directly, create projects, release packages, or execute a shell command.",
                inputSchema: objectSchema(
                    properties: [
                        "action": enumSchema(
                            [
                                "doctor", "assets", "build", "test", "play", "play-all",
                                "profile", "optimize", "fuzz", "lab", "dev-once",
                                "migrate-preview", "hardware-capacity",
                            ],
                            description: "Existing Studio action to invoke."
                        ),
                        "confirmProjectWrites": [
                            "type": "boolean",
                            "description": "Must be true to permit the selected SDK action in the already-open project.",
                        ],
                    ],
                    required: ["action", "confirmProjectWrites"]
                ),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_playtest_plan",
                title: "Run SwanSong Playtest Plan",
                description: "Boot an authorized local WonderSwan ROM in SwanSong's own deterministic engine, apply a bounded exact-frame input plan, and return the final rendered game frame and final audio window plus its complete replay trace. Requires explicit confirmation that the captures may be shared with the MCP client.",
                inputSchema: playtestSchema(),
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                name: "swansong_observed_play_start",
                title: "Start Observed Play",
                description: "Start one isolated project-bound local play session using clean power-on, fixed RTC, and empty persistence. SwanSong creates a private cumulative from-boot plan immediately.",
                inputSchema: observedPlayStartSchema(),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_observed_play_resume",
                title: "Resume Observed Play",
                description: "Recover an interrupted private observed-play session by validating its saved manifest and exact cumulative plan, then replaying that plan from clean boot under the original fixed engine, RTC, ROM, and empty-persistence bindings.",
                inputSchema: observedPlayResumeSchema(),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_observed_play_step",
                title: "Step Observed Play",
                description: "Hold one visible native input combination for a bounded number of frames, return the resulting frame and audio window, and atomically extend the private cumulative from-boot plan. The cumulative session may exceed the one-shot 12,000-frame limit.",
                inputSchema: observedPlayStepSchema(),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_observed_play_sequence",
                title: "Append Observed Play Sequence",
                description: "Atomically append a bounded sequence of native input holds, capture selected named checkpoints, and return the final native frame and audio window. The cumulative plan is saved only after every segment succeeds.",
                inputSchema: observedPlaySequenceSchema(),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_observed_play_branch",
                title: "Branch Observed Play Prefix",
                description: "Create a new active observed-play route from an exact saved prefix by replaying that prefix from clean boot, then close the source session while preserving its private plan.",
                inputSchema: observedPlayBranchSchema(),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_observed_play_finish",
                title: "Finish Observed Play",
                description: "Close the retained live state and replay its exact cumulative plan from clean boot against Original and Patched, producing the normal immutable paired capture evidence.",
                inputSchema: observedPlayCloseSchema(),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_observed_play_cancel",
                title: "Cancel Observed Play",
                description: "Close the retained live state without generating paired proof. The cumulative private plan and cancelled session manifest remain in the project.",
                inputSchema: observedPlayCloseSchema(),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_capture_plan",
                title: "Persist Translation Capture",
                description: "Run one project-contained frame/input plan from Original, replay it against Patched, run Capture Intake for both roles, then privately persist both native frames, the exact plan, deterministic ROM/engine/RTC/persistence bindings, and the pixel-diff report as one immutable project pair.",
                inputSchema: projectWriteSchema(fileKey: "planPath"),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_probe_rectangle",
                title: "Probe Display Rectangle Owner",
                description: "Replay a project-contained exact frame/input plan from clean power-on to one frame, privately retain per-pixel layer, map-cell or sprite/OAM attribute, tile/raster, palette, and CPU-writer provenance, and return only source-free hashes and aggregate counts.",
                inputSchema: displayOwnerProbeSchema(),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_probe_rectangle_source",
                title: "Trace Display Rectangle to Cartridge Sources",
                description: "Ask SwanSong's signed, capture-authorized runner to replay an authenticated Original frame from clean power-on, privately retain exact cartridge lineage and every outside display consumer, and return only the authorized source-free public report.",
                inputSchema: displayOwnerProbeSchema(
                    includeComponents: true,
                    requireAuthorizedSourceEnvelope: true
                ),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_export_static_analysis_seed",
                title: "Export Private Static-Analysis Seed",
                description: "Revalidate one current complete ABI-9 source-probe artifact and privately export deterministic cartridge ranges plus executed caller, operand, mapper, and sprite-attribute anchors for Ghidra or pypcode. Returns only source-free counts, completeness flags, and hashes; static analysis never authorizes a patch.",
                inputSchema: projectWriteSchema(fileKey: "sourceProbeDetailsPath"),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_record_route",
                title: "Record Translation Route",
                description: "Create an immutable route-v3 proof from a project-contained frame/input plan using Original, clean power-on, empty persistence, and SwanSong's fixed proof RTC. Writes a new route inside the project.",
                inputSchema: projectWriteSchema(fileKey: "planPath"),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_verify_pair",
                title: "Verify Translation Pair",
                description: "Replay one project route against Original and Patched, capture both native endpoints, run Capture Intake twice, re-index both immutable manifests, and return the paired evidence identities. Writes new evidence inside the project.",
                inputSchema: projectWriteSchema(fileKey: "routePath"),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
        ]
    }

    private static func tool(
        name: String,
        title: String,
        description: String,
        inputSchema: JSONDictionary,
        readOnly: Bool,
        destructive: Bool,
        idempotent: Bool
    ) -> JSONDictionary {
        [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
            "annotations": [
                "title": title,
                "readOnlyHint": readOnly,
                "destructiveHint": destructive,
                "idempotentHint": idempotent,
                "openWorldHint": false,
            ],
        ]
    }

    private static func callTool(
        name: String,
        arguments: JSONDictionary
    ) -> JSONDictionary {
        do {
            switch name {
            case "swansong_status":
                return try liveResult(method: "status")
            case "swansong_navigate":
                guard let section = arguments["section"] as? String else {
                    throw SwanSongMCPError(message: "section is required")
                }
                return try liveResult(method: "navigate", arguments: ["section": section])
            case "swansong_player":
                guard let action = arguments["action"] as? String else {
                    throw SwanSongMCPError(message: "action is required")
                }
                return try liveResult(method: "player", arguments: ["action": action])
            case "swansong_studio_projects":
                return try liveResult(method: "studio-projects")
            case "swansong_studio_action":
                guard arguments["confirmProjectWrites"] as? Bool == true else {
                    throw SwanSongMCPError(
                        message: "Set confirmProjectWrites to true after confirming the current Studio project may be built or updated."
                    )
                }
                guard let action = arguments["action"] as? String else {
                    throw SwanSongMCPError(message: "action is required")
                }
                return try liveResult(
                    method: "studio-action",
                    arguments: [
                        "action": action,
                        "confirmProjectWrites": true,
                    ]
                )
            case "swansong_playtest_plan":
                return try playtest(arguments: arguments)
            case "swansong_observed_play_start":
                return try observedPlayStart(arguments: arguments)
            case "swansong_observed_play_resume":
                return try observedPlayResume(arguments: arguments)
            case "swansong_observed_play_step":
                return try observedPlayStep(arguments: arguments)
            case "swansong_observed_play_sequence":
                return try observedPlaySequence(arguments: arguments)
            case "swansong_observed_play_branch":
                return try observedPlayBranch(arguments: arguments)
            case "swansong_observed_play_finish":
                return try observedPlayFinish(arguments: arguments)
            case "swansong_observed_play_cancel":
                return try observedPlayCancel(arguments: arguments)
            case "swansong_translation_capture_plan":
                return try capturePlan(arguments: arguments)
            case "swansong_translation_probe_rectangle":
                return try probeRectangle(arguments: arguments)
            case "swansong_translation_probe_rectangle_source":
                return try probeRectangleSource(arguments: arguments)
            case "swansong_translation_export_static_analysis_seed":
                return try exportStaticAnalysisSeed(arguments: arguments)
            case "swansong_translation_record_route":
                return try recordRoute(arguments: arguments)
            case "swansong_translation_verify_pair":
                return try verifyPair(arguments: arguments)
            default:
                throw SwanSongMCPError(message: "Unknown SwanSong tool \(name)")
            }
        } catch {
            return [
                "content": [["type": "text", "text": error.localizedDescription]],
                "isError": true,
            ]
        }
    }

    private static func liveResult(
        method: String,
        arguments: JSONDictionary = [:]
    ) throws -> JSONDictionary {
        let (json, structured) = try liveApp.request(method: method, arguments: arguments)
        return [
            "content": [["type": "text", "text": json]],
            "structuredContent": structured,
            "isError": false,
        ]
    }

    private static func recordRoute(arguments: JSONDictionary) throws -> JSONDictionary {
        let (project, fileURL) = try projectWriteArguments(
            arguments,
            fileKey: "planPath"
        )
        let planData = try readProjectFile(fileURL, project: project, maximumBytes: 1_048_576)
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        return try reportResult(
            TranslationLabAutomation.recordRoute(project: project, plan: plan)
        )
    }

    private static func capturePlan(arguments: JSONDictionary) throws -> JSONDictionary {
        let (project, fileURL) = try projectWriteArguments(
            arguments,
            fileKey: "planPath"
        )
        let planData = try readProjectFile(fileURL, project: project, maximumBytes: 1_048_576)
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        return try reportResult(
            TranslationLabAutomation.capturePlan(project: project, plan: plan)
        )
    }

    private static func probeRectangle(arguments: JSONDictionary) throws -> JSONDictionary {
        let input = try rectangleProbeArguments(arguments)
        return try reportResult(
            TranslationDisplayOwnerProbe.run(
                project: input.project,
                role: input.role,
                plan: input.plan,
                frameIndex: input.frameIndex,
                rectangle: input.rectangle
            )
        )
    }

    private static func probeRectangleSource(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        let input = try rectangleProbeArguments(arguments)
        let componentValues = arguments["components"] as? [String]
            ?? EngineDisplaySourceComponent.allCases.map(\.rawValue)
        let components = componentValues.compactMap(EngineDisplaySourceComponent.init(rawValue:))
        guard !componentValues.isEmpty,
              components.count == componentValues.count,
              Set(components).count == components.count else {
            throw SwanSongMCPError(
                message: "components must be a nonempty, unique array containing mapCell, raster, palette, or spriteAttribute"
            )
        }
        let authorizationPath = try requiredAbsolutePath(
            arguments,
            key: "authorizationPath"
        )
        let capabilityReceiptPath = try requiredAbsolutePath(
            arguments,
            key: "capabilityReceiptPath"
        )
        let methodCapabilityReceiptPath = try requiredAbsolutePath(
            arguments,
            key: "methodCapabilityReceiptPath"
        )
        let qualifiedMethodCapabilityReceiptPath = try requiredAbsolutePath(
            arguments,
            key: "qualifiedMethodCapabilityReceiptPath"
        )
        let methodNativeMarkerPath = try requiredAbsolutePath(
            arguments,
            key: "methodNativeMarkerPath"
        )
        let captureFrameSealPath = try requiredAbsolutePath(
            arguments,
            key: "captureFrameSealPath"
        )
        let runDirectoryPath = try requiredAbsolutePath(
            arguments,
            key: "runDirectoryPath"
        )
        let reportPath = try requiredAbsolutePath(arguments, key: "reportPath")
        let runner = try bundledRouteRunnerURL()
        let selectedComponents = components.sorted { $0.rawValue < $1.rawValue }
        let process = Process()
        process.executableURL = runner
        process.arguments = [
            "probe-rectangle-source",
            "--enable-debug-tools",
            "--allow-project-writes",
            "--project", input.project.rootURL.path,
            "--plan", input.planURL.path,
            "--role", input.role.rawValue,
            "--frame", String(input.frameIndex),
            "--rect", [
                input.rectangle.x,
                input.rectangle.y,
                input.rectangle.width,
                input.rectangle.height,
            ].map(String.init).joined(separator: ","),
            "--components", selectedComponents.map(\.rawValue).joined(separator: ","),
            "--output", reportPath,
            "--commercial-authorized-source-probe",
            "--authorization", authorizationPath,
            "--capability-receipt", capabilityReceiptPath,
            "--method-capability-receipt", methodCapabilityReceiptPath,
            "--qualified-method-capability-receipt",
            qualifiedMethodCapabilityReceiptPath,
            "--method-native-marker", methodNativeMarkerPath,
            "--capture-frame-seal", captureFrameSealPath,
            "--run-directory", runDirectoryPath,
        ]
        process.currentDirectoryURL = runner.deletingLastPathComponent()
        process.environment = [
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin",
            "TZ": "UTC",
        ]
        let retainedOutput = Pipe()
        process.standardOutput = retainedOutput.fileHandleForWriting
        process.standardError = retainedOutput.fileHandleForWriting
        try process.run()
        try retainedOutput.fileHandleForWriting.close()
        let runnerOutput = retainedOutput.fileHandleForReading.readDataToEndOfFile()
        try retainedOutput.fileHandleForReading.close()
        process.waitUntilExit()
        guard process.terminationReason == .exit,
              process.terminationStatus == 0 else {
            throw SwanSongMCPError(
                message: "The signed SwanSong runner refused the authorized source probe. No private runner diagnostics were shared."
            )
        }
        let closureSummary = try validateAuthorizedClosureSummary(runnerOutput)
        return try authorizedPublicReportResult(
            at: URL(fileURLWithPath: reportPath),
            runDirectory: URL(fileURLWithPath: runDirectoryPath, isDirectory: true),
            closureSummary: closureSummary
        )
    }

    private static func requiredAbsolutePath(
        _ arguments: JSONDictionary,
        key: String
    ) throws -> String {
        guard let value = arguments[key] as? String,
              (value as NSString).isAbsolutePath else {
            throw SwanSongMCPError(message: "\(key) must be an absolute path.")
        }
        return value
    }

    private static func bundledRouteRunnerURL() throws -> URL {
        guard let helper = Bundle.main.executableURL?.standardizedFileURL else {
            throw SwanSongMCPError(
                message: "The signed SwanSong helper could not locate itself."
            )
        }
        let helpers = helper.deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers",
              helpers.deletingLastPathComponent().lastPathComponent == "Contents" else {
            throw SwanSongMCPError(
                message: "Authorized source probing is available only from the installed SwanSong app."
            )
        }
        let runner = helpers.appendingPathComponent(
            "SwanSongRouteRunner",
            isDirectory: false
        )
        let values = try runner.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              FileManager.default.isExecutableFile(atPath: runner.path),
              runner.resolvingSymlinksInPath().standardizedFileURL == runner else {
            throw SwanSongMCPError(
                message: "The bundled SwanSong runner failed local validation."
            )
        }
        return runner
    }

    private struct AuthorizedClosureSummary {
        let status: String
        let nonce: String
        let closureByteCount: Int
        let closureSHA256: String
    }

    private static func validateAuthorizedClosureSummary(
        _ data: Data
    ) throws -> AuthorizedClosureSummary {
        guard data.count > 0,
              data.count <= 64 * 1_024,
              let value = try JSONSerialization.jsonObject(with: data)
                as? JSONDictionary,
              value["schema"] as? String
                == "swan-song-authorized-method-closure-summary-v1",
              value["method"] as? String == "probe-rectangle-source",
              let status = value["status"] as? String,
              ["complete", "blocked"].contains(status),
              let nonce = value["nonce"] as? String,
              nonce.range(of: "^[0-9a-f]{64}$", options: .regularExpression)
                != nil,
              let closure = value["closure"] as? JSONDictionary,
              let byteCount = exactPositiveInteger(closure["byteCount"]),
              byteCount <= 4 * 1_024 * 1_024,
              let sha256 = closure["sha256"] as? String,
              sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression)
                != nil else {
            throw SwanSongMCPError(
                message: "The signed SwanSong runner did not return a valid closure summary."
            )
        }
        return AuthorizedClosureSummary(
            status: status,
            nonce: nonce,
            closureByteCount: byteCount,
            closureSHA256: sha256
        )
    }

    private static func authorizedPublicReportResult(
        at url: URL,
        runDirectory: URL,
        closureSummary: AuthorizedClosureSummary
    ) throws -> JSONDictionary {
        let canonicalRun = runDirectory.standardizedFileURL
            .resolvingSymlinksInPath().standardizedFileURL
        guard canonicalRun == runDirectory.standardizedFileURL else {
            throw SwanSongMCPError(
                message: "The authorized source-probe run directory is unsafe."
            )
        }
        let closureURL = canonicalRun.appendingPathComponent(
            "closure.json",
            isDirectory: false
        )
        let closureData = try boundedRegularFileData(
            at: closureURL,
            maximumBytes: 4 * 1_024 * 1_024
        )
        guard closureData.count == closureSummary.closureByteCount,
              sha256(closureData) == closureSummary.closureSHA256,
              let closure = try JSONSerialization.jsonObject(with: closureData)
                as? JSONDictionary,
              closure["schema"] as? String
                == "swan-song-authorized-method-closure-v1",
              closure["method"] as? String == "probe-rectangle-source",
              closure["status"] as? String == closureSummary.status,
              closure["nonce"] as? String == closureSummary.nonce,
              closure["writtenLast"] as? Bool == true,
              let reportRecord = closure["report"] as? JSONDictionary,
              reportRecord["role"] as? String == "report",
              let relativePath = reportRecord["relativePath"] as? String,
              relativePath == "report.json",
              let reportByteCount = exactPositiveInteger(
                reportRecord["byteCount"]
              ),
              reportByteCount <= 4 * 1_024 * 1_024,
              let reportSHA256 = reportRecord["sha256"] as? String,
              reportSHA256.range(
                of: "^[0-9a-f]{64}$",
                options: .regularExpression
              ) != nil,
              try closureBindsCurrentMCPHelper(closure) else {
            throw SwanSongMCPError(
                message: "The authorized source-probe closure is unsafe or incomplete."
            )
        }
        let expectedReportURL = canonicalRun.appendingPathComponent(
            relativePath,
            isDirectory: false
        ).standardizedFileURL
        guard expectedReportURL == url.standardizedFileURL else {
            throw SwanSongMCPError(
                message: "The authorized public source-probe report path drifted."
            )
        }
        let data = try boundedRegularFileData(
            at: expectedReportURL,
            maximumBytes: 4 * 1_024 * 1_024
        )
        guard data.count == reportByteCount,
              sha256(data) == reportSHA256,
              let object = try JSONSerialization.jsonObject(with: data)
                as? JSONDictionary,
              let schema = object["schema"] as? String,
              [
                "swan-song-authorized-capture-bound-display-source-probe-report-v2",
                "swan-song-authorized-capture-bound-display-source-probe-blocked-report-v2",
              ].contains(schema),
              (reportRecord["schema"] as? String) == schema,
              object["method"] as? String == "probe-rectangle-source",
              let status = object["status"] as? String,
              status == closureSummary.status,
              !containsPrivateSourceField(object) else {
            throw SwanSongMCPError(
                message: "The signed SwanSong runner produced an unsafe public report."
            )
        }
        return [
            "content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
            "structuredContent": object,
            "isError": status == "blocked",
        ]
    }

    private static func boundedRegularFileData(
        at url: URL,
        maximumBytes: Int
    ) throws -> Data {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard url.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= maximumBytes else {
            throw SwanSongMCPError(
                message: "An authorized source-probe artifact is unavailable."
            )
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == byteCount else {
            throw SwanSongMCPError(
                message: "An authorized source-probe artifact changed while it was read."
            )
        }
        return data
    }

    private static func closureBindsCurrentMCPHelper(
        _ closure: JSONDictionary
    ) throws -> Bool {
        guard let executable = Bundle.main.executableURL?.standardizedFileURL,
              let binding = closure["mcpHelper"] as? JSONDictionary,
              binding["canonicalPath"] as? String == executable.path,
              let artifact = binding["artifact"] as? JSONDictionary,
              let byteCount = exactPositiveInteger(artifact["byteCount"]),
              let digest = artifact["sha256"] as? String else {
            return false
        }
        let data = try boundedRegularFileData(
            at: executable,
            maximumBytes: 128 * 1_024 * 1_024
        )
        return data.count == byteCount && sha256(data) == digest
    }

    private static func exactPositiveInteger(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              String(cString: number.objCType) != "c" else { return nil }
        let value = number.int64Value
        guard value > 0,
              value <= Int64(Int.max),
              number.doubleValue == Double(value) else { return nil }
        return Int(value)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func containsPrivateSourceField(_ value: Any) -> Bool {
        let forbidden = Set([
            "sourceaddress", "sourcebytecount", "cartridgeoffset",
            "cartridgelength", "cartridgerange", "cartridgeranges",
            "romrange", "romranges", "immediatecaller", "callersegment",
            "calleroffset", "operandsegment", "operandoffset",
            "mapperwindow", "mapperbank", "mapperstate",
            "resolvedcartridgeoperand", "generaldmasourceoperand",
            "executedreadcontext", "readcontext", "sourcebytes",
        ])
        if let dictionary = value as? JSONDictionary {
            return dictionary.contains { key, child in
                forbidden.contains(key.lowercased())
                    || containsPrivateSourceField(child)
            }
        }
        if let array = value as? [Any] {
            return array.contains(where: containsPrivateSourceField)
        }
        return false
    }

    private static func exportStaticAnalysisSeed(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        guard arguments["confirmProjectWrites"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmProjectWrites to true after confirming the selected project may receive a private static-analysis seed."
            )
        }
        do {
            let (project, sourceProbeDetailsURL) = try projectWriteArguments(
                arguments,
                fileKey: "sourceProbeDetailsPath"
            )
            return try reportResult(TranslationStaticAnalysisSeedExporter.run(
                project: project,
                sourceProbeDetailsURL: sourceProbeDetailsURL
            ))
        } catch {
            throw SwanSongMCPError(
                message: "Static-analysis seed export was refused because the private source probe or its current project bindings are unsafe, stale, damaged, or incomplete."
            )
        }
    }

    private struct RectangleProbeInput {
        let project: TranslationProject
        let planURL: URL
        let role: TranslationROMRole
        let plan: TranslationFrameInputPlan
        let frameIndex: UInt64
        let rectangle: EngineDisplayRectangle
    }

    private static func rectangleProbeArguments(
        _ arguments: JSONDictionary
    ) throws -> RectangleProbeInput {
        let (project, fileURL) = try projectWriteArguments(
            arguments,
            fileKey: "planPath"
        )
        guard let roleValue = arguments["role"] as? String,
              let role = TranslationROMRole(rawValue: roleValue),
              let frameNumber = arguments["frameIndex"] as? NSNumber,
              let rectangle = arguments["rectangle"] as? JSONDictionary,
              let x = rectangle["x"] as? NSNumber,
              let y = rectangle["y"] as? NSNumber,
              let width = rectangle["width"] as? NSNumber,
              let height = rectangle["height"] as? NSNumber else {
            throw SwanSongMCPError(
                message: "role, frameIndex, and a complete rectangle are required"
            )
        }
        let integers = [frameNumber, x, y, width, height].map(\.int64Value)
        guard integers.allSatisfy({ $0 >= 0 }),
              integers[1...].allSatisfy({ $0 <= Int64(UInt16.max) }) else {
            throw SwanSongMCPError(message: "Probe coordinates and frameIndex are out of range.")
        }
        let planData = try readProjectFile(
            fileURL,
            project: project,
            maximumBytes: 1_048_576
        )
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        return RectangleProbeInput(
            project: project,
            planURL: fileURL,
            role: role,
            plan: plan,
            frameIndex: UInt64(integers[0]),
            rectangle: EngineDisplayRectangle(
                x: UInt16(integers[1]),
                y: UInt16(integers[2]),
                width: UInt16(integers[3]),
                height: UInt16(integers[4])
            )
        )
    }

    private static func playtest(arguments: JSONDictionary) throws -> JSONDictionary {
        guard arguments["confirmShareCapture"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmShareCapture to true after confirming that the rendered game frame and final audio window may be shared with this MCP client."
            )
        }
        guard let romPath = arguments["romPath"] as? String,
              let planValue = arguments["plan"] else {
            throw SwanSongMCPError(message: "romPath and plan are required")
        }
        let captureSDKTrace = arguments["captureSDKTrace"] as? Bool == true
        if captureSDKTrace && arguments["confirmShareSDKTrace"] as? Bool != true {
            throw SwanSongMCPError(
                message: "Set confirmShareSDKTrace to true after confirming that the SDK's bounded semantic gameplay trace may be shared with this MCP client."
            )
        }
        guard (romPath as NSString).isAbsolutePath else {
            throw SwanSongMCPError(message: "romPath must be an absolute path.")
        }
        let romURL = URL(fileURLWithPath: romPath).standardizedFileURL
        let resolvedROMURL = romURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try romURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard resolvedROMURL == romURL,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= SwanSongPlaytester.maximumROMBytes else {
            throw SwanSongMCPError(message: "The ROM must be a bounded, nonsymlink regular file.")
        }
        let suffix = romURL.pathExtension.lowercased()
        guard suffix == "ws" || suffix == "wsc" else {
            throw SwanSongMCPError(message: "The playtest tool accepts only .ws and .wsc ROM files.")
        }
        let image = try LibraryGameImageImporter.image(from: romURL)
        guard image.data.count == fileSize else {
            throw SwanSongMCPError(message: "The ROM changed while SwanSong was reading it.")
        }
        let planData = try JSONSerialization.data(withJSONObject: planValue)
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        let capture = try SwanSongPlaytester.run(
            image: image,
            plan: plan,
            captureSDKTrace: captureSDKTrace
        )
        let (_, baseReportObject) = try encodedReport(capture.report)
        var reportObject = baseReportObject
        if let sdkTrace = capture.sdkTrace {
            reportObject["deterministicTraceBase64"] = sdkTrace.base64EncodedString()
        }
        let reportData = try JSONSerialization.data(
            withJSONObject: reportObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let reportText = String(decoding: reportData, as: UTF8.self)
        return [
            "content": [
                ["type": "text", "text": reportText],
                [
                    "type": "image",
                    "data": capture.png.base64EncodedString(),
                    "mimeType": "image/png",
                ],
                [
                    "type": "audio",
                    "data": capture.audioWAV.base64EncodedString(),
                    "mimeType": "audio/wav",
                ],
            ],
            "structuredContent": reportObject,
            "isError": false,
        ]
    }

    private static func observedPlayStart(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        guard arguments["confirmProjectWrites"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmProjectWrites to true after confirming the selected project may receive a private observed-play session."
            )
        }
        guard let projectPath = arguments["projectPath"] as? String,
              let roleValue = arguments["role"] as? String,
              let role = TranslationROMRole(rawValue: roleValue) else {
            throw SwanSongMCPError(message: "projectPath and role are required")
        }
        let project = try TranslationProject(
            projectDirectory: URL(fileURLWithPath: projectPath, isDirectory: true)
        )
        return try reportResult(observedPlay.start(project: project, role: role))
    }

    private static func observedPlayStep(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        guard arguments["confirmShareCapture"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmShareCapture to true after confirming that the observed frame and audio window may be shared with this MCP client."
            )
        }
        guard let sessionID = arguments["sessionID"] as? String,
              let inputs = arguments["inputs"] as? [String],
              let frameNumber = arguments["frames"] as? NSNumber,
              frameNumber.int64Value >= 1 else {
            throw SwanSongMCPError(message: "sessionID, inputs, and frames are required")
        }
        let capture = try observedPlay.step(
            sessionID: sessionID,
            inputs: inputs,
            frames: UInt64(frameNumber.int64Value)
        )
        let (reportText, reportObject) = try encodedReport(capture.report)
        return [
            "content": [
                ["type": "text", "text": reportText],
                [
                    "type": "image",
                    "data": capture.png.base64EncodedString(),
                    "mimeType": "image/png",
                ],
                [
                    "type": "audio",
                    "data": capture.audioWAV.base64EncodedString(),
                    "mimeType": "audio/wav",
                ],
            ],
            "structuredContent": reportObject,
            "isError": false,
        ]
    }

    private static func observedPlaySequence(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        guard arguments["confirmShareCapture"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmShareCapture to true after confirming that the selected checkpoint frames and audio window may be shared with this MCP client."
            )
        }
        guard let sessionID = arguments["sessionID"] as? String,
              let segmentObjects = arguments["segments"] as? [JSONDictionary],
              !segmentObjects.isEmpty else {
            throw SwanSongMCPError(message: "sessionID and segments are required")
        }
        let segments = try segmentObjects.map { object in
            guard let inputs = object["inputs"] as? [String],
                  let frameNumber = object["frames"] as? NSNumber,
                  frameNumber.int64Value >= 1 else {
                throw SwanSongMCPError(
                    message: "Every observed-play sequence segment requires inputs and frames."
                )
            }
            return TranslationObservedPlaySequenceSegment(
                inputs: inputs,
                frames: UInt64(frameNumber.int64Value),
                checkpointID: object["checkpointID"] as? String
            )
        }
        let capture = try observedPlay.sequence(
            sessionID: sessionID,
            segments: segments
        )
        let (reportText, reportObject) = try encodedReport(capture.report)
        var content: [JSONDictionary] = [
            ["type": "text", "text": reportText],
            [
                "type": "image",
                "data": capture.finalPNG.base64EncodedString(),
                "mimeType": "image/png",
            ],
        ]
        for checkpoint in capture.checkpointPNGs {
            content.append([
                "type": "text",
                "text": "Checkpoint \(checkpoint.checkpointID)",
            ])
            content.append([
                "type": "image",
                "data": checkpoint.png.base64EncodedString(),
                "mimeType": "image/png",
            ])
        }
        content.append([
            "type": "audio",
            "data": capture.audioWAV.base64EncodedString(),
            "mimeType": "audio/wav",
        ])
        return [
            "content": content,
            "structuredContent": reportObject,
            "isError": false,
        ]
    }

    private static func observedPlayBranch(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        guard arguments["confirmProjectWrites"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmProjectWrites to true before creating a clean-boot branch and closing the source session."
            )
        }
        guard let sessionID = arguments["sessionID"] as? String,
              let frameNumber = arguments["throughFrame"] as? NSNumber,
              frameNumber.int64Value >= 3 else {
            throw SwanSongMCPError(
                message: "sessionID and a throughFrame of at least 3 are required"
            )
        }
        return try reportResult(
            observedPlay.branch(
                sessionID: sessionID,
                throughFrame: UInt64(frameNumber.int64Value)
            )
        )
    }

    private static func observedPlayResume(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        guard arguments["confirmProjectWrites"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmProjectWrites to true before recovering and updating the private session."
            )
        }
        guard let projectPath = arguments["projectPath"] as? String,
              let sessionID = arguments["sessionID"] as? String else {
            throw SwanSongMCPError(message: "projectPath and sessionID are required")
        }
        let project = try TranslationProject(
            projectDirectory: URL(fileURLWithPath: projectPath, isDirectory: true)
        )
        return try reportResult(
            observedPlay.resume(project: project, sessionID: sessionID)
        )
    }

    private static func observedPlayFinish(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        guard arguments["confirmProjectWrites"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmProjectWrites to true before creating final paired evidence."
            )
        }
        guard let sessionID = arguments["sessionID"] as? String else {
            throw SwanSongMCPError(message: "sessionID is required")
        }
        return try reportResult(observedPlay.finish(sessionID: sessionID))
    }

    private static func observedPlayCancel(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        guard arguments["confirmProjectWrites"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmProjectWrites to true before closing the private session."
            )
        }
        guard let sessionID = arguments["sessionID"] as? String else {
            throw SwanSongMCPError(message: "sessionID is required")
        }
        return try reportResult(observedPlay.cancel(sessionID: sessionID))
    }

    private static func verifyPair(arguments: JSONDictionary) throws -> JSONDictionary {
        let (project, fileURL) = try projectWriteArguments(
            arguments,
            fileKey: "routePath"
        )
        let routeData = try readProjectFile(fileURL, project: project, maximumBytes: 4_194_304)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let route = try decoder.decode(TranslationRoute.self, from: routeData)
        return try reportResult(
            TranslationLabAutomation.verifyPair(
                project: project,
                route: route,
                routeURL: fileURL
            )
        )
    }

    private static func projectWriteArguments(
        _ arguments: JSONDictionary,
        fileKey: String
    ) throws -> (TranslationProject, URL) {
        guard arguments["confirmProjectWrites"] as? Bool == true else {
            throw SwanSongMCPError(
                message: "Set confirmProjectWrites to true after confirming the selected project may receive new immutable artifacts."
            )
        }
        guard let projectPath = arguments["projectPath"] as? String,
              let filePath = arguments[fileKey] as? String else {
            throw SwanSongMCPError(message: "projectPath and \(fileKey) are required")
        }
        let project = try TranslationProject(
            projectDirectory: URL(fileURLWithPath: projectPath, isDirectory: true)
        )
        let fileURL = URL(fileURLWithPath: filePath).standardizedFileURL
        guard project.contains(fileURL) else {
            throw TranslationLabError.unsafePath(fileURL.path)
        }
        return (project, fileURL)
    }

    private static func readProjectFile(
        _ url: URL,
        project: TranslationProject,
        maximumBytes: Int
    ) throws -> Data {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard resolved == url,
              project.contains(url),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= maximumBytes else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count == byteCount else {
            throw SwanSongMCPError(message: "The project file changed while it was being read.")
        }
        return data
    }

    private static func reportResult<T: Codable>(_ report: T) throws -> JSONDictionary {
        let (text, object) = try encodedReport(report)
        return [
            "content": [["type": "text", "text": text]],
            "structuredContent": object,
            "isError": false,
        ]
    }

    private static func errorReportResult<T: Codable>(_ report: T) throws -> JSONDictionary {
        let (text, object) = try encodedReport(report)
        return [
            "content": [["type": "text", "text": text]],
            "structuredContent": object,
            "isError": true,
        ]
    }

    private static func encodedReport<T: Codable>(
        _ report: T
    ) throws -> (String, JSONDictionary) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSONDictionary else {
            throw SwanSongMCPError(message: "SwanSong produced a non-object report.")
        }
        return (String(decoding: data, as: UTF8.self), object)
    }

    private static func objectSchema(
        properties: JSONDictionary = [:],
        required: [String] = []
    ) -> JSONDictionary {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": properties,
            "required": required,
        ]
    }

    private static func enumSchema(
        _ values: [String],
        description: String
    ) -> JSONDictionary {
        [
            "type": "string",
            "description": description,
            "enum": values,
        ]
    }

    private static func projectWriteSchema(fileKey: String) -> JSONDictionary {
        return objectSchema(
            properties: [
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to a WonderSwan translation project.",
                ],
                fileKey: [
                    "type": "string",
                    "description": "Absolute path to the existing project-contained input file.",
                ],
                "confirmProjectWrites": [
                    "type": "boolean",
                    "description": "Must be true to permit new immutable artifacts inside this project.",
                ],
            ],
            required: ["projectPath", fileKey, "confirmProjectWrites"]
        )
    }

    private static func displayOwnerProbeSchema(
        includeComponents: Bool = false,
        requireAuthorizedSourceEnvelope: Bool = false
    ) -> JSONDictionary {
        var properties: JSONDictionary = [
            "projectPath": [
                "type": "string",
                "description": "Absolute path to a WonderSwan translation project.",
            ],
            "planPath": [
                "type": "string",
                "description": "Absolute path to an exact project-contained frame/input plan.",
            ],
            "role": enumSchema(
                TranslationROMRole.allCases.map(\.rawValue),
                description: "Project ROM role to replay privately."
            ),
            "frameIndex": [
                "type": "integer",
                "minimum": 0,
                "maximum": Int(TranslationFrameInputPlan.maximumFrames - 1),
                "description": "Zero-based plan frame to probe after it is presented.",
            ],
            "rectangle": [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "x": ["type": "integer", "minimum": 0, "maximum": 223],
                    "y": ["type": "integer", "minimum": 0, "maximum": 223],
                    "width": ["type": "integer", "minimum": 1, "maximum": 224],
                    "height": ["type": "integer", "minimum": 1, "maximum": 224],
                ],
                "required": ["x", "y", "width", "height"],
            ],
            "confirmProjectWrites": [
                "type": "boolean",
                "description": "Must be true to permit private provenance artifacts inside this project.",
            ],
        ]
        if includeComponents {
            properties["components"] = [
                "type": "array",
                "minItems": 1,
                "maxItems": EngineDisplaySourceComponent.allCases.count,
                "uniqueItems": true,
                "items": enumSchema(
                    EngineDisplaySourceComponent.allCases.map(\.rawValue),
                    description: "Selected in-rectangle display component."
                ),
                "description": "Components that seed source discovery. Defaults to all; outside consumers remain component-complete.",
            ]
        }
        if requireAuthorizedSourceEnvelope {
            for (key, description) in [
                ("authorizationPath", "Absolute path to the nonce-bound commercial A2 authorization."),
                ("capabilityReceiptPath", "Absolute path to the exact engine capability receipt C."),
                ("methodCapabilityReceiptPath", "Absolute path to the source-probe method receipt M."),
                ("qualifiedMethodCapabilityReceiptPath", "Absolute path to the qualified source-probe receipt M2."),
                ("methodNativeMarkerPath", "Absolute path to the method-native marker."),
                ("captureFrameSealPath", "Absolute path to the authenticated Original capture-frame seal."),
                ("runDirectoryPath", "Absolute path to the fresh, private authorized run directory."),
                ("reportPath", "Absolute A2-authorized destination for the public report."),
            ] {
                properties[key] = ["type": "string", "description": description]
            }
        }
        var required = [
            "projectPath",
            "planPath",
            "role",
            "frameIndex",
            "rectangle",
            "confirmProjectWrites",
        ]
        if requireAuthorizedSourceEnvelope {
            required.append(contentsOf: [
                "authorizationPath",
                "capabilityReceiptPath",
                "methodCapabilityReceiptPath",
                "qualifiedMethodCapabilityReceiptPath",
                "methodNativeMarkerPath",
                "captureFrameSealPath",
                "runDirectoryPath",
                "reportPath",
            ])
        }
        return objectSchema(
            properties: properties,
            required: required
        )
    }

    private static func observedPlayStartSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to a WonderSwan translation project.",
                ],
                "role": enumSchema(
                    TranslationROMRole.allCases.map(\.rawValue),
                    description: "Project ROM role visible during the retained session."
                ),
                "confirmProjectWrites": [
                    "type": "boolean",
                    "description": "Must be true to create and continuously update the private session plan.",
                ],
            ],
            required: ["projectPath", "role", "confirmProjectWrites"]
        )
    }

    private static func observedPlayStepSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "sessionID": [
                    "type": "string",
                    "description": "Identifier returned by observed-play start.",
                ],
                "inputs": [
                    "type": "array",
                    "uniqueItems": true,
                    "items": enumSchema(
                        TranslationFrameInputPlan.acceptedInputNames,
                        description: "Native input held for this visible step."
                    ),
                ],
                "frames": [
                    "type": "integer",
                    "minimum": 1,
                    "maximum": Int(TranslationObservedPlaySession.maximumStepFrames),
                    "description": "Frames to advance while holding this input combination.",
                ],
                "confirmShareCapture": [
                    "type": "boolean",
                    "description": "Must be true to return the resulting rendered frame and audio window.",
                ],
            ],
            required: ["sessionID", "inputs", "frames", "confirmShareCapture"]
        )
    }

    private static func observedPlaySequenceSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "sessionID": [
                    "type": "string",
                    "description": "Identifier returned by observed-play start, resume, or branch.",
                ],
                "segments": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": TranslationObservedPlaySession.maximumSequenceSegments,
                    "items": objectSchema(
                        properties: [
                            "inputs": [
                                "type": "array",
                                "uniqueItems": true,
                                "items": enumSchema(
                                    TranslationFrameInputPlan.acceptedInputNames,
                                    description: "Native input held for this segment."
                                ),
                            ],
                            "frames": [
                                "type": "integer",
                                "minimum": 1,
                                "maximum": Int(TranslationObservedPlaySession.maximumStepFrames),
                                "description": "Frames to hold this segment's input combination.",
                            ],
                            "checkpointID": [
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 96,
                                "description": "Optional stable lowercase ID for a frame captured after this segment.",
                            ],
                        ],
                        required: ["inputs", "frames"]
                    ),
                    "description": "A sequence of input holds totaling no more than \(TranslationObservedPlaySession.maximumSequenceFrames) frames.",
                ],
                "confirmShareCapture": [
                    "type": "boolean",
                    "description": "Must be true to return selected checkpoint frames, the final frame, and final audio window.",
                ],
            ],
            required: ["sessionID", "segments", "confirmShareCapture"]
        )
    }

    private static func observedPlayBranchSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "sessionID": [
                    "type": "string",
                    "description": "Identifier of the active observed-play source session.",
                ],
                "throughFrame": [
                    "type": "integer",
                    "minimum": 3,
                    "maximum": Int(TranslationFrameInputPlan.maximumFrames),
                    "description": "Exact cumulative prefix length replayed from clean boot into the new active branch.",
                ],
                "confirmProjectWrites": [
                    "type": "boolean",
                    "description": "Must be true to create the new private branch and close the source session.",
                ],
            ],
            required: ["sessionID", "throughFrame", "confirmProjectWrites"]
        )
    }

    private static func observedPlayResumeSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the WonderSwan translation project containing the interrupted session.",
                ],
                "sessionID": [
                    "type": "string",
                    "description": "Identifier of a project-contained interrupted observed-play session.",
                ],
                "confirmProjectWrites": [
                    "type": "boolean",
                    "description": "Must be true to mark abandonment, replay the saved plan, and reactivate the private session.",
                ],
            ],
            required: ["projectPath", "sessionID", "confirmProjectWrites"]
        )
    }

    private static func observedPlayCloseSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "sessionID": [
                    "type": "string",
                    "description": "Identifier returned by observed-play start.",
                ],
                "confirmProjectWrites": [
                    "type": "boolean",
                    "description": "Must be true to update the private session and, when finishing, emit paired evidence.",
                ],
            ],
            required: ["sessionID", "confirmProjectWrites"]
        )
    }

    private static func playtestSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "romPath": [
                    "type": "string",
                    "description": "Absolute path to an authorized local .ws or .wsc ROM.",
                ],
                "plan": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "schema": [
                            "type": "string",
                            "const": TranslationFrameInputPlan.currentSchema,
                        ],
                        "totalFrames": [
                            "type": "integer",
                            "minimum": 3,
                            "maximum": Int(SwanSongPlaytester.maximumMCPFrames),
                        ],
                        "events": [
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1_000,
                            "items": [
                                "type": "object",
                                "additionalProperties": false,
                                "properties": [
                                    "frameIndex": [
                                        "type": "integer",
                                        "minimum": 0,
                                    ],
                                    "inputs": [
                                        "type": "array",
                                        "uniqueItems": true,
                                        "items": enumSchema(
                                            TranslationFrameInputPlan.acceptedInputNames,
                                            description: "Native SwanSong input held from this event until the next event."
                                        ),
                                    ],
                                ],
                                "required": ["frameIndex", "inputs"],
                            ],
                        ],
                    ],
                    "required": ["schema", "totalFrames", "events"],
                ],
                "confirmShareCapture": [
                    "type": "boolean",
                    "description": "Must be true to return the rendered game frame and final audio window to the MCP client.",
                ],
                "captureSDKTrace": [
                    "type": "boolean",
                    "description": "Request the SwanSong SDK's bounded semantic deterministic trace when the ROM contains one.",
                ],
                "confirmShareSDKTrace": [
                    "type": "boolean",
                    "description": "Must be true when captureSDKTrace is true; never authorizes raw memory disclosure.",
                ],
            ],
            required: ["romPath", "plan", "confirmShareCapture"]
        )
    }
}
