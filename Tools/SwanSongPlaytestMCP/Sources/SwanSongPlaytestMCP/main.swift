import Foundation
import MCP
import SwanSongKit

private struct PlaytestMCPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
private struct SwanSongPlaytestMCPServer {
    static func main() async throws {
        let server = Server(
            name: "swansong-playtester",
            version: "1.0.0",
            title: "SwanSong Playtester",
            instructions: "Executes authorized local WonderSwan homebrew through SwanSong's own deterministic engine. The tool returns one rendered game frame and its final audio window only when confirmShareCapture=true. It must never expose ROM, save, state, persistence, or RAM bytes. Successful execution is observation evidence, not proof that a mechanic passed; inspect the frame, listen to relevant audio, and exercise the declared game contract.",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [playtestTool])
        }
        await server.withMethodHandler(CallTool.self) { request in
            await call(request)
        }
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    private static let playtestTool = Tool(
        name: "swansong_playtest_plan",
        title: "Run SwanSong Playtest Plan",
        description: "Boot an authorized local .ws or .wsc ROM in SwanSong's own deterministic engine, apply a bounded exact-frame input plan, and return the final native game frame, final audio window, and complete replay evidence.",
        inputSchema: playtestSchema(),
        annotations: .init(
            readOnlyHint: false,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    private static func call(_ request: CallTool.Parameters) async -> CallTool.Result {
        do {
            guard request.name == playtestTool.name else {
                throw PlaytestMCPError(message: "Unknown SwanSong playtest tool \(request.name)")
            }
            return try playtest(arguments: request.arguments)
        } catch {
            return .init(
                content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func playtest(
        arguments: [String: Value]?
    ) throws -> CallTool.Result {
        guard arguments?["confirmShareCapture"]?.boolValue == true else {
            throw PlaytestMCPError(
                message: "Set confirmShareCapture to true after confirming that the rendered game frame and audio may be shared with this MCP client."
            )
        }
        guard let romPath = arguments?["romPath"]?.stringValue,
              let planValue = arguments?["plan"] else {
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
                                            description: "Native SwanSong controls held until the next event."
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
                    "description": .string("Must be true to return rendered game image and audio media."),
                ]),
            ],
            required: ["romPath", "plan", "confirmShareCapture"]
        )
    }
}
