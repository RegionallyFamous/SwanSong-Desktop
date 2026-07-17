import Dispatch
import Foundation
import SwanSongKit

private typealias JSONDictionary = [String: Any]

private struct SwanSongMCPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class BridgeResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<(String, JSONDictionary), Error>?

    func store(_ value: Result<(String, JSONDictionary), Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard self.value == nil else { return }
        self.value = value
    }

    func load() -> Result<(String, JSONDictionary), Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class LiveAppClient: @unchecked Sendable {
    func request(
        method: String,
        arguments: JSONDictionary = [:]
    ) throws -> (String, JSONDictionary) {
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
                do {
                    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
                    guard let dictionary = object as? JSONDictionary else {
                        throw SwanSongMCPError(message: "SwanSong returned a non-object response.")
                    }
                    box.store(.success((json, dictionary)))
                } catch {
                    box.store(.failure(error))
                }
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
        return try response.get()
    }
}

@main
private enum SwanSongMCPServer {
    private static let protocolVersion = "2025-11-25"
    private static let liveApp = LiveAppClient()
    private static let instructions = "Controls a running SwanSong app through its opt-in local bridge, runs guarded Translation Lab evidence workflows, and can execute bounded deterministic homebrew playtest plans through SwanSong's own engine. The playtest tool returns one rendered game frame and its final audio window only when confirmShareCapture=true. The server must never expose ROM, save, state, persistence, or RAM bytes. Translation tools only accept project-contained files and require confirmProjectWrites=true. A successful execution is observation evidence, not proof that a game mechanic passed; inspect the frame, listen to relevant audio, and exercise the declared game contract."

    static func main() {
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
                            ["library", "favorites", "recent", "homebrew", "pocket", "translation"],
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
                name: "swansong_playtest_plan",
                title: "Run SwanSong Playtest Plan",
                description: "Boot an authorized local WonderSwan ROM in SwanSong's own deterministic engine, apply a bounded exact-frame input plan, and return the final rendered game frame and final audio window plus its complete replay trace. Requires explicit confirmation that the captures may be shared with the MCP client.",
                inputSchema: playtestSchema(),
                readOnly: false,
                destructive: false,
                idempotent: true
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
            case "swansong_playtest_plan":
                return try playtest(arguments: arguments)
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
        let capture = try SwanSongPlaytester.run(image: image, plan: plan)
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
        objectSchema(
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
            ],
            required: ["romPath", "plan", "confirmShareCapture"]
        )
    }
}
