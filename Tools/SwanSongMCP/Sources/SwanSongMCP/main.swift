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
    private static let instructions = "Controls a running SwanSong app through its opt-in local bridge, runs guarded Translation Lab evidence workflows, and can execute bounded deterministic homebrew playtest plans through SwanSong's own engine. The trusted local MCP has persistent access to write inside the selected translation project without a per-call project-write confirmation. Studio tools expose only one already-open project slot without its name or path, and invoke only a fixed SDK 0.5 allowlist: doctor, assets, build, test, play, play-all, profile, optimize preview, fuzz, lab, one-shot dev, migration preview, and hardware capacity. Playtest and observed-step tools return a rendered game frame and audio window only when confirmShareCapture=true. A single playtest may also return the SDK's bounded, structurally validated semantic trace when captureSDKTrace=true and confirmShareSDKTrace=true. The server must never expose ROM, save, state, persistence, raw RAM, tile, palette, map-cell, sprite/OAM attribute, CPU-writer, conservative-origin, cartridge-range, address, or mapper values. Translation tools only accept project-contained files. Persisted translation captures privately retain both native frames, the exact plan, deterministic context hashes, and pixel-diff evidence inside the selected project. Display-owner probes and static-analysis seeds retain detailed source evidence privately and return only hashes and aggregate counts. Observed play holds a private ownership lease, atomically saves its cumulative from-boot plan after every step, marks crash-abandoned sessions interrupted, recovers only by clean-boot plan replay, and creates final evidence only by another clean-boot replay. A successful execution is observation evidence, not proof that a game mechanic passed; inspect the frame, listen to relevant audio, and exercise the declared game contract."

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
        if Array(CommandLine.arguments.dropFirst()) == [
            "--original-frame-stage-categories-kat"
        ] {
            do {
                let result = try TranslationOriginalFrameAuthenticationStage
                    .signedReleaseSourceFreeStageKAT()
                FileHandle.standardOutput.write(Data("\(result)\n".utf8))
            } catch {
                FileHandle.standardError.write(
                    Data(
                        "SwanSongMCP: Original-frame stage control failed\n".utf8
                    )
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
                    ],
                    required: ["action"]
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
                description: "Run one project-contained frame/input plan from Original, replay it against Patched, run Capture Intake for both roles, then privately persist both native frames, each role's final 30-frame audio window from those same replays, the exact plan, deterministic ROM/engine/RTC/persistence bindings, and the pixel-diff report as one immutable project pair.",
                inputSchema: projectWriteSchema(fileKey: "planPath"),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_seal_persistence_handoff",
                title: "Seal Persistence Handoff",
                description: "Validate one exact project-contained Patched capture chain and its digest-bound request, restore the existing ABI-10 state without another replay, then atomically publish two private byte-identical complete-cartridge-persistence clones. Returns only source-safe hashes, counts, booleans, and opaque clone identities.",
                inputSchema: projectWriteSchema(fileKey: "requestPath"),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_capture_persistence_consumer",
                title: "Capture Persistence Consumer",
                description: "Validate one sealed LOAD or CONTINUE clone and a digest-bound project plan, stage the clone before Patched ROM load, then run that consumer independently from clean power. Privately retains the exact plan, final native frame, and final 30-frame audio window while returning only source-safe identities, counts, and digests.",
                inputSchema: projectWriteSchema(fileKey: "requestPath"),
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
                name: "swansong_translation_seal_original_frame",
                title: "Seal Read-Only Original Frame",
                description: "Replay one authority-bound Original frame from deterministic clean boot without provenance queries or project/ROM writes, then privately write only its immutable source-probe frame seal and closure. Patched, comparison, mutation, and release modes are rejected.",
                inputSchema: originalFrameSealSchema(),
                readOnly: true,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_probe_rectangle_source",
                title: "Trace Display Rectangle to Cartridge Sources",
                description: "Ask SwanSong's signed, capture-authorized runner to replay an authenticated Original frame from clean power-on, privately retain exact cartridge lineage and every outside display consumer, and return only the authorized source-free public report.",
                inputSchema: displayOwnerProbeSchema(
                    includeComponents: true,
                    requireAuthorizedSourceEnvelope: true,
                    allowAtomicRegions: true
                ),
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                name: "swansong_translation_trace_original_data_producer",
                title: "Trace Original Data Producer",
                description: "Replay one nonce-authorized Original plan from clean power-on, watch only one 1-64 byte cartridge-SRAM descriptor, privately retain its final CPU writer and cartridge lineage without returning RAM bytes, and fail closed unless the expected source has one exact producer.",
                inputSchema: originalDataProducerProbeSchema(),
                readOnly: true,
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
                guard let action = arguments["action"] as? String else {
                    throw SwanSongMCPError(message: "action is required")
                }
                return try liveResult(
                    method: "studio-action",
                    arguments: ["action": action]
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
            case "swansong_translation_seal_persistence_handoff":
                return try sealPersistenceHandoff(arguments: arguments)
            case "swansong_translation_capture_persistence_consumer":
                return try capturePersistenceConsumer(arguments: arguments)
            case "swansong_translation_probe_rectangle":
                return try probeRectangle(arguments: arguments)
            case "swansong_translation_seal_original_frame":
                return try sealOriginalFrame(arguments: arguments)
            case "swansong_translation_probe_rectangle_source":
                return try probeRectangleSource(arguments: arguments)
            case "swansong_translation_trace_original_data_producer":
                return try traceOriginalDataProducer(arguments: arguments)
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

    private static func sealPersistenceHandoff(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        let (project, requestURL) = try projectWriteArguments(
            arguments,
            fileKey: "requestPath"
        )
        let requestData = try readProjectFile(
            requestURL,
            project: project,
            maximumBytes: 1_048_576
        )
        let request = try JSONDecoder().decode(
            TranslationPersistenceHandoffRequest.self,
            from: requestData
        )
        return try reportResult(TranslationPersistenceHandoffStore.seal(
            project: project,
            request: request
        ))
    }

    private static func capturePersistenceConsumer(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        let (project, requestURL) = try projectWriteArguments(
            arguments,
            fileKey: "requestPath"
        )
        let requestData = try readProjectFile(
            requestURL,
            project: project,
            maximumBytes: 1_048_576
        )
        let request = try JSONDecoder().decode(
            TranslationPersistenceHandoffConsumerRequest.self,
            from: requestData
        )
        return try reportResult(TranslationPersistenceHandoffStore.captureConsumer(
            project: project,
            request: request
        ))
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
        let input = try rectangleProbeArguments(
            arguments,
            allowAtomicRegions: true
        )
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
        var processArguments = [
            "probe-rectangle-source",
            "--enable-debug-tools",
            "--allow-project-writes",
            "--project", input.project.rootURL.path,
            "--plan", input.planURL.path,
            "--role", input.role.rawValue,
            "--frame", String(input.frameIndex),
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
        let serializedRegions = input.rectangles.map { rectangle in
            [
                rectangle.x,
                rectangle.y,
                rectangle.width,
                rectangle.height,
            ].map(String.init).joined(separator: ",")
        }
        if serializedRegions.count == 1 {
            processArguments.append(contentsOf: ["--rect", serializedRegions[0]])
        } else {
            processArguments.append(contentsOf: [
                "--source-regions",
                serializedRegions.joined(separator: ";"),
            ])
        }
        process.arguments = processArguments
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

    private static func sealOriginalFrame(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        let input = try rectangleProbeArguments(
            arguments,
            allowAtomicRegions: true
        )
        guard input.role == .original else {
            throw SwanSongMCPError(
                message: "The read-only frame seal accepts only the Original role."
            )
        }
        let componentValues = arguments["components"] as? [String]
            ?? ["raster"]
        let components = componentValues.compactMap(
            EngineDisplaySourceComponent.init(rawValue:)
        )
        guard !componentValues.isEmpty,
              components.count == componentValues.count,
              Set(components).count == components.count else {
            throw SwanSongMCPError(
                message: "components must be a nonempty unique source-component array"
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
        let runDirectoryPath = try requiredAbsolutePath(
            arguments,
            key: "runDirectoryPath"
        )
        let sealPath = try requiredAbsolutePath(arguments, key: "sealPath")
        let runner = try bundledRouteRunnerURL()
        var processArguments = [
            "probe-rectangle-source",
            "--enable-debug-tools",
            "--allow-project-writes",
            "--project", input.project.rootURL.path,
            "--plan", input.planURL.path,
            "--role", "original",
            "--frame", String(input.frameIndex),
            "--components",
            components.sorted { $0.rawValue < $1.rawValue }
                .map(\.rawValue).joined(separator: ","),
            "--output", sealPath,
            "--commercial-authorized-original-frame-seal",
            "--authorization", authorizationPath,
            "--capability-receipt", capabilityReceiptPath,
            "--method-capability-receipt", methodCapabilityReceiptPath,
            "--qualified-method-capability-receipt",
            qualifiedMethodCapabilityReceiptPath,
            "--method-native-marker", methodNativeMarkerPath,
            "--run-directory", runDirectoryPath,
        ]
        let serializedRegions = input.rectangles.map { rectangle in
            [
                rectangle.x, rectangle.y,
                rectangle.width, rectangle.height,
            ].map(String.init).joined(separator: ",")
        }
        if serializedRegions.count == 1 {
            processArguments.append(contentsOf: ["--rect", serializedRegions[0]])
        } else {
            processArguments.append(contentsOf: [
                "--source-regions",
                serializedRegions.joined(separator: ";"),
            ])
        }
        let process = Process()
        process.executableURL = runner
        process.arguments = processArguments
        process.currentDirectoryURL = runner.deletingLastPathComponent()
        process.environment = [
            "LANG": "C", "LC_ALL": "C",
            "PATH": "/usr/bin:/bin", "TZ": "UTC",
        ]
        let retainedOutput = Pipe()
        process.standardOutput = retainedOutput.fileHandleForWriting
        process.standardError = retainedOutput.fileHandleForWriting
        try process.run()
        try retainedOutput.fileHandleForWriting.close()
        let output = retainedOutput.fileHandleForReading.readDataToEndOfFile()
        try retainedOutput.fileHandleForReading.close()
        process.waitUntilExit()
        guard process.terminationReason == .exit,
              process.terminationStatus == 0 else {
            let runnerOutput = String(decoding: output, as: UTF8.self)
            let category = TranslationOriginalFrameAuthenticationStage
                .sourceFreeCategory(in: runnerOutput)?.rawValue
                ?? "unclassified"
            throw SwanSongMCPError(
                message: "The signed SwanSong runner refused the read-only "
                    + "Original-frame seal. Source-free stage: \(category)."
            )
        }
        return try authorizedOriginalFrameSealResult(
            output,
            sealURL: URL(fileURLWithPath: sealPath),
            runDirectory: URL(
                fileURLWithPath: runDirectoryPath,
                isDirectory: true
            )
        )
    }

    private static func traceOriginalDataProducer(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
        let method = "trace-original-data-producer"
        guard Set(arguments.keys) == Set([
            "projectPath", "authorizationPath", "authorizationSHA256",
        ]),
        let projectPath = arguments["projectPath"] as? String,
        let authorizationPath = arguments["authorizationPath"] as? String,
        let expectedAuthorizationSHA256 =
            arguments["authorizationSHA256"] as? String,
        isLowercaseSHA256(expectedAuthorizationSHA256) else {
            throw SwanSongMCPError(
                message: "The Original data-producer request must contain only its exact project and authorization binding."
            )
        }
        let project = try TranslationProject(
            projectDirectory: URL(
                fileURLWithPath: projectPath, isDirectory: true
            )
        )
        let authorizationURL = URL(fileURLWithPath: authorizationPath)
            .standardizedFileURL
        let authorizationData = try privateRegularFileData(
            at: authorizationURL,
            project: project,
            maximumBytes: 128 * 1_024
        )
        guard sha256(authorizationData) == expectedAuthorizationSHA256,
              let authorization = try JSONSerialization.jsonObject(
                with: authorizationData
              ) as? JSONDictionary else {
            throw SwanSongMCPError(
                message: "The Original data-producer authorization is unavailable or drifted."
            )
        }
        let exactKeys = Set([
            "schema", "method", "nonce", "invocationOrdinal", "retryCount",
            "invocationMaximum", "projectPath", "planPath",
            "runDirectoryPath", "planSHA256", "originalSHA256",
            "planFrameIndex", "expectedNativeFrameNumber",
            "expectedNativeFrameSHA256", "targetAddress", "targetByteCount",
            "expectedCartridgeSourceOffset",
            "expectedCartridgeSourceByteCount", "appExecutableSHA256",
            "mcpHelperSHA256", "routeRunnerSHA256", "engineDylibSHA256",
            "projectWritesAllowedOnlyForTraceArtifacts", "romWritesAllowed",
            "patchedRoleAllowed", "comparisonAllowed", "patchAuthorityAllowed",
        ])
        guard Set(authorization.keys) == exactKeys,
              authorization["schema"] as? String
                == "swan-song-original-data-producer-probe-authorization-v1",
              authorization["method"] as? String == method,
              let nonce = authorization["nonce"] as? String,
              isLowercaseSHA256(nonce),
              exactPositiveInteger(authorization["invocationOrdinal"]) == 1,
              exactNonnegativeInteger(authorization["retryCount"]) == 0,
              exactPositiveInteger(authorization["invocationMaximum"]) == 1,
              authorization["projectPath"] as? String
                == project.rootURL.standardizedFileURL.path,
              authorization["projectPath"] as? String == projectPath,
              let planPath = authorization["planPath"] as? String,
              let runDirectoryPath = authorization["runDirectoryPath"] as? String,
              let planSHA256 = authorization["planSHA256"] as? String,
              let originalSHA256 = authorization["originalSHA256"] as? String,
              let expectedNativeFrameSHA256 =
                authorization["expectedNativeFrameSHA256"] as? String,
              let appExecutableSHA256 =
                authorization["appExecutableSHA256"] as? String,
              let mcpHelperSHA256 = authorization["mcpHelperSHA256"] as? String,
              let routeRunnerSHA256 =
                authorization["routeRunnerSHA256"] as? String,
              let engineDylibSHA256 =
                authorization["engineDylibSHA256"] as? String,
              [planSHA256, originalSHA256, expectedNativeFrameSHA256,
               appExecutableSHA256, mcpHelperSHA256, routeRunnerSHA256,
               engineDylibSHA256].allSatisfy(isLowercaseSHA256),
              authorization["projectWritesAllowedOnlyForTraceArtifacts"]
                as? Bool == true,
              authorization["romWritesAllowed"] as? Bool == false,
              authorization["patchedRoleAllowed"] as? Bool == false,
              authorization["comparisonAllowed"] as? Bool == false,
              authorization["patchAuthorityAllowed"] as? Bool == false else {
            throw SwanSongMCPError(
                message: "The Original data-producer authorization is malformed or overbroad."
            )
        }
        let planFrameIndex = try exactUInt64(
            authorization["planFrameIndex"], label: "planFrameIndex"
        )
        let expectedNativeFrameNumber = try exactUInt64(
            authorization["expectedNativeFrameNumber"],
            label: "expectedNativeFrameNumber"
        )
        let targetAddress = try exactUInt32(
            authorization["targetAddress"], label: "targetAddress"
        )
        let targetByteCount = try exactUInt32(
            authorization["targetByteCount"], label: "targetByteCount"
        )
        let expectedSourceOffset = try exactUInt32(
            authorization["expectedCartridgeSourceOffset"],
            label: "expectedCartridgeSourceOffset"
        )
        let expectedSourceByteCount = try exactUInt32(
            authorization["expectedCartridgeSourceByteCount"],
            label: "expectedCartridgeSourceByteCount"
        )
        let planURL = URL(fileURLWithPath: planPath).standardizedFileURL
        let runDirectory = URL(
            fileURLWithPath: runDirectoryPath, isDirectory: true
        ).standardizedFileURL
        guard authorizationURL
                == runDirectory.appendingPathComponent("authorization.json"),
              project.contains(planURL), project.contains(runDirectory),
              runDirectory.resolvingSymlinksInPath().standardizedFileURL
                == runDirectory,
              try privateDirectoryIsExact(runDirectory),
              try FileManager.default.contentsOfDirectory(
                atPath: runDirectory.path
              ).sorted() == ["authorization.json"] else {
            throw SwanSongMCPError(
                message: "The authorized producer-trace run graph is not fresh and private."
            )
        }
        let planData = try privateRegularFileData(
            at: planURL, project: project, maximumBytes: 1_048_576
        )
        let originalURL = try project.romURL(for: .original)
        let originalData = try privateRegularFileData(
            at: originalURL, project: project,
            maximumBytes: 16 * 1_024 * 1_024
        )
        guard sha256(planData) == planSHA256,
              sha256(originalData) == originalSHA256 else {
            throw SwanSongMCPError(
                message: "The exact Original or plan changed after authorization."
            )
        }
        let toolchain = try installedToolchainFiles()
        guard sha256(toolchain.app.data) == appExecutableSHA256,
              sha256(toolchain.helper.data) == mcpHelperSHA256,
              sha256(toolchain.runner.data) == routeRunnerSHA256,
              sha256(toolchain.engine.data) == engineDylibSHA256 else {
            throw SwanSongMCPError(
                message: "The installed SwanSong toolchain changed after authorization."
            )
        }
        let claim: JSONDictionary = [
            "schema": "swan-song-original-data-producer-probe-nonce-claim-v1",
            "method": method,
            "nonce": nonce,
            "authorizationSHA256": expectedAuthorizationSHA256,
            "runDirectoryPathSHA256": sha256(Data(runDirectory.path.utf8)),
        ]
        let claimData = try canonicalJSONData(claim)
        let claimURL = runDirectory.appendingPathComponent("nonce-claim.json")
        do {
            try claimData.write(to: claimURL, options: [.withoutOverwriting])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: claimURL.path
            )
        } catch {
            throw SwanSongMCPError(
                message: "The Original producer-trace nonce was already used or could not be claimed."
            )
        }
        let plan = try JSONDecoder().decode(
            TranslationFrameInputPlan.self, from: planData
        )
        let request = TranslationDataProducerProbeRequest(
            planFrameIndex: planFrameIndex,
            expectedNativeFrameNumber: expectedNativeFrameNumber,
            expectedNativeFrameSHA256: expectedNativeFrameSHA256,
            targetAddress: targetAddress,
            targetByteCount: targetByteCount,
            expectedCartridgeSourceOffset: expectedSourceOffset,
            expectedCartridgeSourceByteCount: expectedSourceByteCount
        )
        let result = try TranslationDataProducerProbe.runOriginal(
            project: project,
            plan: plan,
            request: request,
            authorizationData: authorizationData,
            runDirectory: runDirectory
        )
        let reportData = try privateRegularFileData(
            at: result.reportURL, project: project,
            maximumBytes: 4 * 1_024 * 1_024
        )
        let detailsData = try privateRegularFileData(
            at: result.detailsURL, project: project,
            maximumBytes: 4 * 1_024 * 1_024
        )
        let privatePlanData = try privateRegularFileData(
            at: result.planURL, project: project,
            maximumBytes: 1_048_576
        )
        guard sha256(reportData) == sha256(try encodedData(result.report)),
              sha256(detailsData) == result.report.privateDetailsSHA256,
              sha256(privatePlanData) == planSHA256,
              result.report.authorizationSHA256
                == expectedAuthorizationSHA256,
              result.report.rawMemoryBytesReturned == 0,
              result.report.projectROMWrites == false,
              result.report.patchedRoleAccepted == false,
              result.report.comparisonPerformed == false,
              result.report.patchAuthorityGranted == false else {
            throw SwanSongMCPError(
                message: "The private producer trace failed its source-free output checks."
            )
        }
        let closure: JSONDictionary = [
            "schema": "swan-song-original-data-producer-probe-closure-v1",
            "method": method,
            "status": result.report.status,
            "sourceFree": true,
            "role": "original",
            "nonce": nonce,
            "authorizationSHA256": expectedAuthorizationSHA256,
            "reportSHA256": sha256(reportData),
            "privateDetailsSHA256": sha256(detailsData),
            "privatePlanSHA256": sha256(privatePlanData),
            "mcpHelperSHA256": sha256(toolchain.helper.data),
            "engineDylibSHA256": sha256(toolchain.engine.data),
            "rawMemoryBytesReturned": 0,
            "romWritesPerformed": false,
            "patchedRoleAccepted": false,
            "comparisonPerformed": false,
            "patchAuthorityGranted": false,
            "writtenLast": true,
        ]
        let closureData = try canonicalJSONData(closure)
        let closureURL = runDirectory.appendingPathComponent("closure.json")
        try closureData.write(to: closureURL, options: [.withoutOverwriting])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: closureURL.path
        )
        guard var summary = try JSONSerialization.jsonObject(
            with: reportData
        ) as? JSONDictionary else {
            throw SwanSongMCPError(
                message: "The producer-trace public report was not a JSON object."
            )
        }
        summary["closureSHA256"] = sha256(closureData)
        summary["nonceClaimSHA256"] = sha256(claimData)
        let summaryData = try canonicalJSONData(summary)
        return [
            "content": [[
                "type": "text",
                "text": String(decoding: summaryData, as: UTF8.self),
            ]],
            "structuredContent": summary,
            "isError": result.report.status != "complete",
        ]
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

    private static func authorizedOriginalFrameSealResult(
        _ summaryData: Data,
        sealURL: URL,
        runDirectory: URL
    ) throws -> JSONDictionary {
        guard summaryData.count > 0,
              summaryData.count <= 64 * 1_024,
              let summary = try JSONSerialization.jsonObject(
                with: summaryData
              ) as? JSONDictionary,
              summary["schema"] as? String
                == "swan-song-authorized-original-read-only-frame-seal-summary-v1",
              summary["status"] as? String == "complete",
              summary["sourceFree"] as? Bool == true,
              summary["role"] as? String == "original",
              summary["readOnlyMethodAuthorization"] as? Bool == true,
              summary["projectWritesPerformed"] as? Bool == false,
              summary["romWritesPerformed"] as? Bool == false,
              summary["provenanceQueriesPerformed"] as? NSNumber == 0,
              summary["patchedRoleAccepted"] as? Bool == false,
              summary["comparisonPerformed"] as? Bool == false,
              summary["releaseWorkflowAuthorized"] as? Bool == false,
              summary["promotionEligible"] as? Bool == false,
              let sealIdentity = summary["captureFrameSeal"]
                as? JSONDictionary,
              let closureIdentity = summary["closure"] as? JSONDictionary else {
            throw SwanSongMCPError(
                message: "The signed runner returned an invalid read-only frame-seal summary."
            )
        }
        let canonicalRun = runDirectory.standardizedFileURL
            .resolvingSymlinksInPath().standardizedFileURL
        guard canonicalRun == runDirectory.standardizedFileURL,
              sealURL.standardizedFileURL
                == canonicalRun.appendingPathComponent(
                    "capture-frame-seal.json"
                ) else {
            throw SwanSongMCPError(
                message: "The read-only frame-seal output graph drifted."
            )
        }
        let sealData = try boundedRegularFileData(
            at: sealURL,
            maximumBytes: 4 * 1_024 * 1_024
        )
        let closureURL = canonicalRun.appendingPathComponent("closure.json")
        let closureData = try boundedRegularFileData(
            at: closureURL,
            maximumBytes: 4 * 1_024 * 1_024
        )
        guard identityMatches(sealIdentity, data: sealData),
              identityMatches(closureIdentity, data: closureData),
              let seal = try JSONSerialization.jsonObject(with: sealData)
                as? JSONDictionary,
              let closure = try JSONSerialization.jsonObject(with: closureData)
                as? JSONDictionary,
              seal["schema"] as? String
                == "wstrans-swansong-original-read-only-frame-seal-v1",
              seal["role"] as? String == "original",
              seal["sourceFree"] as? Bool == true,
              seal["readOnlyMethodAuthorization"] as? Bool == true,
              seal["projectWritesPerformed"] as? Bool == false,
              seal["romWritesPerformed"] as? Bool == false,
              seal["provenanceQueriesPerformed"] as? NSNumber == 0,
              seal["patchedRoleAccepted"] as? Bool == false,
              seal["comparisonPerformed"] as? Bool == false,
              seal["releaseWorkflowAuthorized"] as? Bool == false,
              seal["promotionEligible"] as? Bool == false,
              closure["schema"] as? String
                == "swan-song-authorized-original-read-only-frame-seal-closure-v1",
              closure["status"] as? String == "complete",
              closure["writtenLast"] as? Bool == true,
              closure["captureFrameSeal"] as? NSDictionary
                == sealIdentity as NSDictionary,
              closure["mcpHelper"] as? NSDictionary
                == artifactIdentity(
                    try boundedRegularFileData(
                        at: Bundle.main.executableURL!,
                        maximumBytes: 128 * 1_024 * 1_024
                    )
                ) as NSDictionary,
              closure["projectTreeBeforeSHA256"] as? String
                == closure["projectTreeAfterSHA256"] as? String else {
            throw SwanSongMCPError(
                message: "The read-only Original-frame seal or closure is unsafe."
            )
        }
        return [
            "content": [[
                "type": "text",
                "text": String(decoding: summaryData, as: UTF8.self),
            ]],
            "structuredContent": summary,
            "isError": false,
        ]
    }

    private static func identityMatches(
        _ value: JSONDictionary,
        data: Data
    ) -> Bool {
        guard let byteCount = exactPositiveInteger(value["byteCount"]),
              let digest = value["sha256"] as? String,
              Set(value.keys) == Set(["byteCount", "sha256"]) else {
            return false
        }
        return byteCount == data.count && digest == sha256(data)
    }

    private static func artifactIdentity(_ data: Data) -> JSONDictionary {
        ["byteCount": data.count, "sha256": sha256(data)]
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

    private static func exactNonnegativeInteger(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              String(cString: number.objCType) != "c" else { return nil }
        let value = number.int64Value
        guard value >= 0,
              value <= Int64(Int.max),
              number.doubleValue == Double(value) else { return nil }
        return Int(value)
    }

    private static func exactUInt64(
        _ raw: Any?, label: String
    ) throws -> UInt64 {
        guard let number = raw as? NSNumber,
              String(cString: number.objCType) != "c",
              let value = UInt64(number.stringValue) else {
            throw SwanSongMCPError(message: "\(label) must be an exact nonnegative integer.")
        }
        return value
    }

    private static func exactUInt32(
        _ raw: Any?, label: String
    ) throws -> UInt32 {
        let value = try exactUInt64(raw, label: label)
        guard value <= UInt64(UInt32.max) else {
            throw SwanSongMCPError(message: "\(label) is outside its fixed bound.")
        }
        return UInt32(value)
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func canonicalJSONData(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
        ]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func privateDirectoryIsExact(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return values.isDirectory == true
            && values.isSymbolicLink != true
            && (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
    }

    private static func privateRegularFileData(
        at url: URL,
        project: TranslationProject,
        maximumBytes: Int
    ) throws -> Data {
        let canonical = url.standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(
            atPath: canonical.path
        )
        guard project.contains(canonical),
              canonical.resolvingSymlinksInPath().standardizedFileURL
                == canonical,
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else {
            throw SwanSongMCPError(
                message: "A producer-trace private input is unsafe."
            )
        }
        return try boundedRegularFileData(
            at: canonical, maximumBytes: maximumBytes
        )
    }

    private struct InstalledToolchainFile {
        let data: Data
    }

    private struct InstalledToolchainFiles {
        let app: InstalledToolchainFile
        let helper: InstalledToolchainFile
        let runner: InstalledToolchainFile
        let engine: InstalledToolchainFile
    }

    private static func installedToolchainFiles() throws
        -> InstalledToolchainFiles {
        guard let helperURL = Bundle.main.executableURL?.standardizedFileURL,
              helperURL.deletingLastPathComponent().lastPathComponent
                == "Helpers" else {
            throw SwanSongMCPError(
                message: "The producer trace is available only from the installed SwanSong helper."
            )
        }
        let contents = helperURL.deletingLastPathComponent()
            .deletingLastPathComponent()
        let urls = [
            contents.appendingPathComponent("MacOS/SwanSong"),
            helperURL,
            contents.appendingPathComponent("Helpers/SwanSongRouteRunner"),
            contents.appendingPathComponent("Frameworks/libSwanAresEngine.dylib"),
        ]
        let files = try urls.map { url -> InstalledToolchainFile in
            let data = try boundedRegularFileData(
                at: url.standardizedFileURL,
                maximumBytes: 512 * 1_024 * 1_024
            )
            return InstalledToolchainFile(data: data)
        }
        return InstalledToolchainFiles(
            app: files[0], helper: files[1],
            runner: files[2], engine: files[3]
        )
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
        let rectangles: [EngineDisplayRectangle]
    }

    private static func rectangleProbeArguments(
        _ arguments: JSONDictionary,
        allowAtomicRegions: Bool = false
    ) throws -> RectangleProbeInput {
        let (project, fileURL) = try projectWriteArguments(
            arguments,
            fileKey: "planPath"
        )
        guard let roleValue = arguments["role"] as? String,
              let role = TranslationROMRole(rawValue: roleValue),
              let frameNumber = arguments["frameIndex"] as? NSNumber else {
            throw SwanSongMCPError(
                message: "role and frameIndex are required"
            )
        }
        let rawRectangle = arguments["rectangle"] as? JSONDictionary
        let rawRectangles = allowAtomicRegions
            ? arguments["rectangles"] as? [JSONDictionary] : nil
        guard (rawRectangle == nil) != (rawRectangles == nil) else {
            throw SwanSongMCPError(
                message: "Provide exactly one rectangle or one bounded rectangles array."
            )
        }
        let rawSelection = rawRectangles ?? rawRectangle.map { [$0] } ?? []
        let rectangles = try rawSelection.map { rectangle in
            guard let x = rectangle["x"] as? NSNumber,
                  let y = rectangle["y"] as? NSNumber,
                  let width = rectangle["width"] as? NSNumber,
                  let height = rectangle["height"] as? NSNumber else {
                throw SwanSongMCPError(
                    message: "Every source-context rectangle must be complete."
                )
            }
            let integers = [x, y, width, height].map(\.int64Value)
            guard integers.allSatisfy({ $0 >= 0 && $0 <= Int64(UInt16.max) }) else {
                throw SwanSongMCPError(
                    message: "Probe coordinates are out of range."
                )
            }
            return EngineDisplayRectangle(
                x: UInt16(integers[0]),
                y: UInt16(integers[1]),
                width: UInt16(integers[2]),
                height: UInt16(integers[3])
            )
        }
        guard frameNumber.int64Value >= 0 else {
            throw SwanSongMCPError(message: "frameIndex is out of range.")
        }
        let rectangle: EngineDisplayRectangle
        if allowAtomicRegions {
            do {
                rectangle = try TranslationDisplaySourceProbe
                    .atomicBoundingRectangle(rectangles: rectangles)
            } catch {
                throw SwanSongMCPError(message: error.localizedDescription)
            }
        } else {
            guard let single = rectangles.first else {
                throw SwanSongMCPError(message: "A complete rectangle is required.")
            }
            rectangle = single
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
            frameIndex: UInt64(frameNumber.int64Value),
            rectangle: rectangle,
            rectangles: rectangles
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
        guard let sessionID = arguments["sessionID"] as? String else {
            throw SwanSongMCPError(message: "sessionID is required")
        }
        return try reportResult(observedPlay.finish(sessionID: sessionID))
    }

    private static func observedPlayCancel(
        arguments: JSONDictionary
    ) throws -> JSONDictionary {
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
            ],
            required: ["projectPath", fileKey]
        )
    }

    private static func displayOwnerProbeSchema(
        includeComponents: Bool = false,
        requireAuthorizedSourceEnvelope: Bool = false,
        allowAtomicRegions: Bool = false
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
                "description": allowAtomicRegions
                    ? "One upstream source region; each region is capped at \(TranslationDisplaySourceProbe.maximumRectanglePixels) pixels."
                    : "One display-owner region capped at \(TranslationDisplayOwnerProbe.maximumRectanglePixels) native pixels.",
                "properties": [
                    "x": ["type": "integer", "minimum": 0, "maximum": 223],
                    "y": ["type": "integer", "minimum": 0, "maximum": 223],
                    "width": ["type": "integer", "minimum": 1, "maximum": 224],
                    "height": ["type": "integer", "minimum": 1, "maximum": 224],
                ],
                "required": ["x", "y", "width", "height"],
            ],
        ]
        if allowAtomicRegions {
            properties["rectangles"] = [
                "type": "array",
                "minItems": 1,
                "maxItems": TranslationDisplaySourceProbe.maximumAtomicRegionCount,
                "items": properties["rectangle"]!,
                "description": "Non-overlapping regions that exactly tile one source context; each is capped at 4096 pixels and the atomic total at 8192.",
            ]
        }
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
        ]
        if !allowAtomicRegions {
            required.append("rectangle")
        }
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
        var schema = objectSchema(
            properties: properties,
            required: required
        )
        if allowAtomicRegions {
            schema["oneOf"] = [
                ["required": ["rectangle"]],
                ["required": ["rectangles"]],
            ]
        }
        return schema
    }

    private static func originalFrameSealSchema() -> JSONDictionary {
        var schema = displayOwnerProbeSchema(
            includeComponents: true,
            requireAuthorizedSourceEnvelope: false,
            allowAtomicRegions: true
        )
        guard var properties = schema["properties"] as? JSONDictionary,
              var required = schema["required"] as? [String] else {
            return schema
        }
        for (name, description) in [
            ("authorizationPath", "Absolute path to the fresh Original-frame seal authorization."),
            ("capabilityReceiptPath", "Absolute path to source capability C."),
            ("methodCapabilityReceiptPath", "Absolute path to source method M."),
            ("qualifiedMethodCapabilityReceiptPath", "Absolute path to qualified source method M2."),
            ("methodNativeMarkerPath", "Absolute path to the source method-native marker."),
            ("runDirectoryPath", "Absolute path to the fresh private seal run directory."),
            ("sealPath", "Absolute path to RUN/capture-frame-seal.json."),
        ] {
            properties[name] = [
                "type": "string",
                "description": description,
            ]
            required.append(name)
        }
        schema["properties"] = properties
        schema["required"] = required
        return schema
    }

    private static func originalDataProducerProbeSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the exact private Translation Lab project.",
                ],
                "authorizationPath": [
                    "type": "string",
                    "description": "Absolute path to the fresh project-contained Original-only producer-trace authorization.",
                ],
                "authorizationSHA256": [
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$",
                    "description": "Exact SHA-256 of the one-use authorization file.",
                ],
            ],
            required: [
                "projectPath", "authorizationPath", "authorizationSHA256",
            ]
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
            ],
            required: ["projectPath", "role"]
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
            ],
            required: ["sessionID", "throughFrame"]
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
            ],
            required: ["projectPath", "sessionID"]
        )
    }

    private static func observedPlayCloseSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "sessionID": [
                    "type": "string",
                    "description": "Identifier returned by observed-play start.",
                ],
            ],
            required: ["sessionID"]
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
