import Dispatch
import Foundation
import MCP
import SwanSongKit

private struct SwanSongMCPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class BridgeResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<String, Error>?

    func store(_ value: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard self.value == nil else { return }
        self.value = value
    }

    func load() -> Result<String, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class LiveAppClient: @unchecked Sendable {
    func request(method: String, arguments: [String: Any] = [:]) throws -> (String, Value) {
        guard let token = try SwanSongLocalMCPAccess.readToken() else {
            throw SwanSongMCPError(
                message: "Local MCP control is off. Open SwanSong Settings and enable Allow local MCP control."
            )
        }
        let requestID = UUID().uuidString
        let argumentData = try JSONSerialization.data(
            withJSONObject: arguments,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let argumentJSON = String(decoding: argumentData, as: UTF8.self)
        let box = BridgeResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: SwanSongLocalMCPAccess.responseNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let values = notification.userInfo as? [String: String],
                  values["requestID"] == requestID,
                  values["token"] == token else { return }
            if let error = values["error"] {
                box.store(.failure(SwanSongMCPError(message: error)))
            } else if let json = values["json"] {
                box.store(.success(json))
            } else {
                box.store(.failure(SwanSongMCPError(message: "SwanSong returned an empty response.")))
            }
            semaphore.signal()
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        DistributedNotificationCenter.default().postNotificationName(
            SwanSongLocalMCPAccess.requestNotification,
            object: nil,
            userInfo: [
                "requestID": requestID,
                "token": token,
                "method": method,
                "arguments": argumentJSON,
            ],
            deliverImmediately: true
        )
        guard semaphore.wait(timeout: .now() + 5) == .success,
              let response = box.load() else {
            throw SwanSongMCPError(
                message: "SwanSong did not answer. Make sure the app is open and local MCP control is enabled."
            )
        }
        let json = try response.get()
        let value = try JSONDecoder().decode(Value.self, from: Data(json.utf8))
        return (json, value)
    }
}

@main
private struct SwanSongMCPServer {
    private static let liveApp = LiveAppClient()

    static func main() async throws {
        let server = Server(
            name: "swansong",
            version: "1.0.0",
            title: "SwanSong",
            instructions: "Controls a running SwanSong app through its opt-in local bridge, runs guarded Translation Lab evidence workflows, and can execute bounded deterministic homebrew playtest plans through SwanSong's own engine. The playtest tool returns one rendered game frame and its final audio window only when confirmShareCapture=true. The server must never expose ROM, save, state, persistence, or RAM bytes. Translation tools only accept project-contained files and require confirmProjectWrites=true. A successful execution is observation evidence, not proof that a game mechanic passed; inspect the frame, listen to relevant audio, and exercise the declared game contract.",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { request in
            await call(request)
        }
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    private static var tools: [Tool] {
        [
            Tool(
                name: "swansong_status",
                title: "Read SwanSong Status",
                description: "Read limited state from the running SwanSong app. Returns the current section, library count, and playback readiness without game titles, paths, ROMs, saves, memory, or screenshots.",
                inputSchema: objectSchema(),
                annotations: .init(
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: false
                )
            ),
            Tool(
                name: "swansong_navigate",
                title: "Navigate SwanSong",
                description: "Change the visible SwanSong section while no game is running.",
                inputSchema: objectSchema(
                    properties: [
                        "section": enumSchema(
                            ["library", "favorites", "recent", "homebrew", "pocket", "translation"],
                            description: "The destination section."
                        ),
                    ],
                    required: ["section"]
                ),
                annotations: .init(
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: false
                )
            ),
            Tool(
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
                annotations: .init(
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: false,
                    openWorldHint: false
                )
            ),
            Tool(
                name: "swansong_playtest_plan",
                title: "Run SwanSong Playtest Plan",
                description: "Boot an authorized local WonderSwan ROM in SwanSong's own deterministic engine, apply a bounded exact-frame input plan, and return the final rendered game frame plus its complete replay trace. Requires explicit confirmation that the frame may be shared with the MCP client.",
                inputSchema: playtestSchema(),
                annotations: .init(
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: false
                )
            ),
            Tool(
                name: "swansong_translation_record_route",
                title: "Record Translation Route",
                description: "Create an immutable route-v3 proof from a project-contained frame/input plan using Original, clean power-on, empty persistence, and SwanSong's fixed proof RTC. Writes a new route inside the project.",
                inputSchema: projectWriteSchema(fileKey: "planPath"),
                annotations: .init(
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: false,
                    openWorldHint: false
                )
            ),
            Tool(
                name: "swansong_translation_verify_pair",
                title: "Verify Translation Pair",
                description: "Replay one project route against Original and Patched, capture both native endpoints, run Capture Intake twice, re-index both immutable manifests, and return the paired evidence identities. Writes new evidence inside the project.",
                inputSchema: projectWriteSchema(fileKey: "routePath"),
                annotations: .init(
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: false,
                    openWorldHint: false
                )
            ),
        ]
    }

    private static func call(_ request: CallTool.Parameters) async -> CallTool.Result {
        do {
            switch request.name {
            case "swansong_status":
                return try liveResult(method: "status")
            case "swansong_navigate":
                guard let section = request.arguments?["section"]?.stringValue else {
                    throw SwanSongMCPError(message: "section is required")
                }
                return try liveResult(method: "navigate", arguments: ["section": section])
            case "swansong_player":
                guard let action = request.arguments?["action"]?.stringValue else {
                    throw SwanSongMCPError(message: "action is required")
                }
                return try liveResult(method: "player", arguments: ["action": action])
            case "swansong_playtest_plan":
                return try playtest(arguments: request.arguments)
            case "swansong_translation_record_route":
                return try recordRoute(arguments: request.arguments)
            case "swansong_translation_verify_pair":
                return try verifyPair(arguments: request.arguments)
            default:
                throw SwanSongMCPError(message: "Unknown SwanSong tool \(request.name)")
            }
        } catch {
            return .init(
                content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func liveResult(
        method: String,
        arguments: [String: Any] = [:]
    ) throws -> CallTool.Result {
        let (json, structured) = try liveApp.request(method: method, arguments: arguments)
        return try .init(
            content: [.text(text: json, annotations: nil, _meta: nil)],
            structuredContent: structured,
            isError: false
        )
    }

    private static func recordRoute(
        arguments: [String: Value]?
    ) throws -> CallTool.Result {
        let (project, fileURL) = try projectWriteArguments(
            arguments,
            fileKey: "planPath"
        )
        let planData = try readProjectFile(fileURL, project: project, maximumBytes: 1_048_576)
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        let report = try TranslationLabAutomation.recordRoute(project: project, plan: plan)
        return try reportResult(report)
    }

    private static func playtest(
        arguments: [String: Value]?
    ) throws -> CallTool.Result {
        guard arguments?["confirmShareCapture"]?.boolValue == true else {
            throw SwanSongMCPError(
                message: "Set confirmShareCapture to true after confirming that the rendered game frame may be shared with this MCP client."
            )
        }
        guard let romPath = arguments?["romPath"]?.stringValue,
              let planValue = arguments?["plan"] else {
            throw SwanSongMCPError(message: "romPath and plan are required")
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
        let planData = try JSONEncoder().encode(planValue)
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        let capture = try SwanSongPlaytester.run(image: image, plan: plan)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reportData = try encoder.encode(capture.report)
        return try .init(
            content: [
                .text(
                    text: String(decoding: reportData, as: UTF8.self),
                    annotations: nil,
                    _meta: nil
                ),
                .image(
                    data: capture.png.base64EncodedString(),
                    mimeType: "image/png",
                    annotations: nil,
                    _meta: nil
                ),
                .audio(
                    data: capture.audioWAV.base64EncodedString(),
                    mimeType: "audio/wav",
                    annotations: nil,
                    _meta: nil
                ),
            ],
            structuredContent: try Value(capture.report),
            isError: false
        )
    }

    private static func verifyPair(
        arguments: [String: Value]?
    ) throws -> CallTool.Result {
        let (project, fileURL) = try projectWriteArguments(
            arguments,
            fileKey: "routePath"
        )
        let routeData = try readProjectFile(fileURL, project: project, maximumBytes: 4_194_304)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let route = try decoder.decode(TranslationRoute.self, from: routeData)
        let report = try TranslationLabAutomation.verifyPair(
            project: project,
            route: route,
            routeURL: fileURL
        )
        return try reportResult(report)
    }

    private static func projectWriteArguments(
        _ arguments: [String: Value]?,
        fileKey: String
    ) throws -> (TranslationProject, URL) {
        guard arguments?["confirmProjectWrites"]?.boolValue == true else {
            throw SwanSongMCPError(
                message: "Set confirmProjectWrites to true after confirming the selected project may receive new immutable artifacts."
            )
        }
        guard let projectPath = arguments?["projectPath"]?.stringValue,
              let filePath = arguments?[fileKey]?.stringValue else {
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

    private static func reportResult<T: Codable>(_ report: T) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        return try .init(
            content: [
                .text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil),
            ],
            structuredContent: try Value(report),
            isError: false
        )
    }

    private static func objectSchema(
        properties: [String: Value] = [:],
        required: [String] = []
    ) -> Value {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object(properties),
            "required": .array(required.map(Value.string)),
        ])
    }

    private static func enumSchema(_ values: [String], description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "enum": .array(values.map(Value.string)),
        ])
    }

    private static func projectWriteSchema(fileKey: String) -> Value {
        objectSchema(
            properties: [
                "projectPath": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to a WonderSwan translation project."),
                ]),
                fileKey: .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the existing project-contained input file."),
                ]),
                "confirmProjectWrites": .object([
                    "type": .string("boolean"),
                    "description": .string("Must be true to permit new immutable artifacts inside this project."),
                ]),
            ],
            required: ["projectPath", fileKey, "confirmProjectWrites"]
        )
    }

    private static func playtestSchema() -> Value {
        objectSchema(
            properties: [
                "romPath": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to an authorized local .ws or .wsc ROM."),
                ]),
                "plan": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "schema": .object([
                            "type": .string("string"),
                            "const": .string(TranslationFrameInputPlan.currentSchema),
                        ]),
                        "totalFrames": .object([
                            "type": .string("integer"),
                            "minimum": .int(3),
                            "maximum": .int(Int(SwanSongPlaytester.maximumMCPFrames)),
                        ]),
                        "events": .object([
                            "type": .string("array"),
                            "minItems": .int(1),
                            "maxItems": .int(1_000),
                            "items": .object([
                                "type": .string("object"),
                                "additionalProperties": .bool(false),
                                "properties": .object([
                                    "frameIndex": .object([
                                        "type": .string("integer"),
                                        "minimum": .int(0),
                                    ]),
                                    "inputs": .object([
                                        "type": .string("array"),
                                        "uniqueItems": .bool(true),
                                        "items": enumSchema(
                                            TranslationFrameInputPlan.acceptedInputNames,
                                            description: "Native SwanSong input held from this event until the next event."
                                        ),
                                    ]),
                                ]),
                                "required": .array([.string("frameIndex"), .string("inputs")]),
                            ]),
                        ]),
                    ]),
                    "required": .array([
                        .string("schema"), .string("totalFrames"), .string("events"),
                    ]),
                ]),
                "confirmShareCapture": .object([
                    "type": .string("boolean"),
                    "description": .string("Must be true to return the rendered game frame and final audio window to the MCP client."),
                ]),
            ],
            required: ["romPath", "plan", "confirmShareCapture"]
        )
    }
}
