import Foundation
import SwanSongKit

private typealias JSONDictionary = [String: Any]

private struct PlaytestMCPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
private enum SwanSongPlaytestMCPServer {
    private static let protocolVersion = "2025-11-25"
    private static let instructions = "Executes authorized local WonderSwan homebrew through SwanSong's own deterministic engine. The tool returns one rendered game frame and its final audio window only when confirmShareCapture=true. It must never expose ROM, save, state, persistence, or RAM bytes. Successful execution is observation evidence, not proof that a mechanic passed; inspect the frame, listen to relevant audio, and exercise the declared game contract."

    static func main() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            do {
                if let response = try response(to: Data(line.utf8)) {
                    try write(response)
                }
            } catch {
                try? write(
                    rpcError(
                        id: NSNull(),
                        code: -32603,
                        message: error.localizedDescription
                    )
                )
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
        guard let id = request["id"] else { return nil }
        let parameters = request["params"] as? JSONDictionary ?? [:]
        switch method {
        case "initialize":
            return rpcResult(
                id: id,
                result: [
                    "protocolVersion": protocolVersion,
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "swansong-playtester", "version": "1.0.0"],
                    "instructions": instructions,
                ]
            )
        case "ping":
            return rpcResult(id: id, result: [:])
        case "tools/list":
            return rpcResult(id: id, result: ["tools": [playtestTool]])
        case "tools/call":
            guard parameters["name"] as? String == "swansong_playtest_plan" else {
                return rpcResult(
                    id: id,
                    result: toolError("Unknown SwanSong playtest tool")
                )
            }
            return rpcResult(
                id: id,
                result: callPlaytest(
                    arguments: parameters["arguments"] as? JSONDictionary ?? [:]
                )
            )
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

    private static var playtestTool: JSONDictionary {
        [
            "name": "swansong_playtest_plan",
            "description": "Boot an authorized local .ws or .wsc ROM in SwanSong's own deterministic engine, apply a bounded exact-frame input plan, and return the final native game frame, final audio window, and complete replay evidence.",
            "inputSchema": playtestSchema(),
            "annotations": [
                "title": "Run SwanSong Playtest Plan",
                "readOnlyHint": false,
                "destructiveHint": false,
                "idempotentHint": true,
                "openWorldHint": false,
            ],
        ]
    }

    private static func callPlaytest(arguments: JSONDictionary) -> JSONDictionary {
        do {
            return try playtest(arguments: arguments)
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private static func toolError(_ message: String) -> JSONDictionary {
        [
            "content": [["type": "text", "text": message]],
            "isError": true,
        ]
    }

    private static func playtest(arguments: JSONDictionary) throws -> JSONDictionary {
        guard arguments["confirmShareCapture"] as? Bool == true else {
            throw PlaytestMCPError(
                message: "Set confirmShareCapture to true after confirming that the rendered game frame and audio may be shared with this MCP client."
            )
        }
        guard let romPath = arguments["romPath"] as? String,
              let planValue = arguments["plan"] else {
            throw PlaytestMCPError(message: "romPath and plan are required")
        }
        guard (romPath as NSString).isAbsolutePath else {
            throw PlaytestMCPError(message: "romPath must be an absolute path")
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
              fileSize >= GameROMValidationPolicy.minimumByteCount,
              fileSize <= SwanSongPlaytester.maximumROMBytes else {
            throw PlaytestMCPError(message: "The ROM must be a bounded, nonsymlink regular file")
        }
        guard ["ws", "wsc"].contains(romURL.pathExtension.lowercased()) else {
            throw PlaytestMCPError(message: "The playtest tool accepts only .ws and .wsc ROM files")
        }

        let image = try LibraryGameImageImporter.image(from: romURL)
        guard image.data.count == fileSize else {
            throw PlaytestMCPError(message: "The ROM changed while SwanSong was reading it")
        }
        let planData = try JSONSerialization.data(withJSONObject: planValue)
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        let capture = try SwanSongPlaytester.run(image: image, plan: plan)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reportData = try encoder.encode(capture.report)
        guard let report = try JSONSerialization.jsonObject(with: reportData) as? JSONDictionary else {
            throw PlaytestMCPError(message: "SwanSong produced a non-object playtest report")
        }
        return [
            "content": [
                ["type": "text", "text": String(decoding: reportData, as: UTF8.self)],
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
            "structuredContent": report,
            "isError": false,
        ]
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
                                            description: "Native SwanSong controls held until the next event."
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
                    "description": "Must be true to return rendered game image and audio media.",
                ],
            ],
            required: ["romPath", "plan", "confirmShareCapture"]
        )
    }
}
