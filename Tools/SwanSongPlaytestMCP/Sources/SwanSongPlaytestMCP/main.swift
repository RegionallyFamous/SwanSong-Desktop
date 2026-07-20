import Foundation
import SwanSongKit

private typealias JSONDictionary = [String: Any]

private struct PlaytestMCPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct ROMPhysicalIdentity: Equatable {
    let fileSystemNumber: UInt64
    let fileSystemFileNumber: UInt64
}

private struct ROMFileSnapshot: Equatable {
    let byteCount: Int
    let modificationDate: Date?
    let physicalIdentity: ROMPhysicalIdentity
}

private struct PlaytestComparisonDelta: Codable {
    let classification: String
    let visualChanged: Bool
    let gameRasterChanged: Bool
    let capturePNGChanged: Bool
    let wholeFramePixelMetricsAvailable: Bool
    let wholeFramePixelCount: Int?
    let wholeFrameDifferentPixelCount: Int?
    let wholeFrameDifferentPixelFraction: Double?
    let wholeFrameMeanAbsoluteChannelError: Double?
    let wholeFrameMaximumChannelError: UInt8?
    let wholeFrameChangedBounds: RGBFrameBounds?
    let audioChanged: Bool
    let fullAudioPCMChanged: Bool
    let finalWindowAudioPCMChanged: Bool
    let finalWindowWAVChanged: Bool
    let captureGeometryChanged: Bool
    let audioFormatChanged: Bool
    let audioSampleFrameCountChanged: Bool
}

private struct PlaytestComparisonReport: Codable {
    static let currentSchema = "swan-song-playtest-comparison-report-v1"

    let schema: String
    let planSHA256: String
    let deterministicContextMatched: Bool
    let original: SwanSongPlaytestReport
    let patched: SwanSongPlaytestReport
    let delta: PlaytestComparisonDelta
}

@main
private enum SwanSongPlaytestMCPServer {
    private static let protocolVersion = "2025-11-25"
    private static let instructions = "Executes authorized local WonderSwan software through SwanSong's own deterministic engine. The tools return one rendered game frame and final audio window, or a paired Original/Patched A/B capture, only when confirmShareCapture=true. A single playtest may also return the SDK's bounded, structurally validated semantic trace when captureSDKTrace=true and confirmShareSDKTrace=true. They must never expose paths, ROM, save, state, persistence, or raw RAM bytes. Successful execution is observation evidence, not proof that a mechanic passed; inspect every returned frame, listen to relevant audio, and exercise the declared game contract."

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
                    "serverInfo": ["name": "swansong-playtester", "version": "1.2.0"],
                    "instructions": instructions,
                ]
            )
        case "ping":
            return rpcResult(id: id, result: [:])
        case "tools/list":
            return rpcResult(
                id: id,
                result: ["tools": [playtestTool, comparePlaytestTool]]
            )
        case "tools/call":
            let arguments = parameters["arguments"] as? JSONDictionary ?? [:]
            switch parameters["name"] as? String {
            case "swansong_playtest_plan":
                return rpcResult(
                    id: id,
                    result: callPlaytest(arguments: arguments)
                )
            case "swansong_compare_playtest_plan":
                return rpcResult(
                    id: id,
                    result: callComparePlaytest(arguments: arguments)
                )
            default:
                return rpcResult(
                    id: id,
                    result: toolError("Unknown SwanSong playtest tool")
                )
            }
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

    private static var comparePlaytestTool: JSONDictionary {
        [
            "name": "swansong_compare_playtest_plan",
            "description": "Boot two different authorized local .ws or .wsc ROMs as Original and Patched under identical deterministic conditions, apply the same bounded exact-frame input plan independently, and return both native captures plus a source-free A/B delta report. Media order is Original image, Original audio, Patched image, Patched audio.",
            "inputSchema": comparePlaytestSchema(),
            "annotations": [
                "title": "Compare SwanSong Playtest Plan",
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
        } catch let error as PlaytestMCPError {
            return toolError(error.message)
        } catch {
            return toolError(safeToolErrorMessage(for: error))
        }
    }

    private static func callComparePlaytest(arguments: JSONDictionary) -> JSONDictionary {
        do {
            return try comparePlaytest(arguments: arguments)
        } catch let error as PlaytestMCPError {
            return toolError(error.message)
        } catch {
            return toolError(safeToolErrorMessage(for: error))
        }
    }

    private static func safeToolErrorMessage(for error: Error) -> String {
        if let importError = error as? LibraryGameImportError {
            switch importError {
            case .unsafeSource:
                return "The supplied ROM must be a regular local file."
            case .sourceTooLarge:
                return "The supplied ROM is outside the supported size range."
            case .invalidGame:
                return "The supplied file is not a structurally valid WonderSwan ROM."
            default:
                return "The supplied file is not a supported WonderSwan ROM."
            }
        }
        if let translationError = error as? TranslationLabError {
            switch translationError {
            case let .invalidRoute(detail):
                return "The frame/input plan is invalid: \(detail)"
            default:
                return "The deterministic playtest request was rejected."
            }
        }
        if error is DecodingError {
            return "The frame/input plan does not match the supported schema."
        }
        if error is SwanEngineError {
            return "SwanSong's deterministic engine could not complete the bounded playtest."
        }
        if error is EngineFramePNGCodecError || error is FrameDifferentialError {
            return "SwanSong could not compare the captured native frames."
        }
        return "SwanSong could not safely read or play the supplied ROM."
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
        let captureSDKTrace = arguments["captureSDKTrace"] as? Bool == true
        if captureSDKTrace && arguments["confirmShareSDKTrace"] as? Bool != true {
            throw PlaytestMCPError(
                message: "Set confirmShareSDKTrace to true after confirming that the SDK's bounded semantic gameplay trace may be shared with this MCP client."
            )
        }
        let romURL = try validatedROMURL(path: romPath, argumentName: "romPath")
        let initialSnapshot = try preflightROM(at: romURL)
        let image = try readStableROM(
            from: romURL,
            initialSnapshot: initialSnapshot
        )
        let plan = try decodePlan(planValue)
        let capture = try SwanSongPlaytester.run(
            image: image,
            plan: plan,
            captureSDKTrace: captureSDKTrace
        )
        let encoder = reportEncoder()
        let reportData = try encoder.encode(capture.report)
        guard var report = try JSONSerialization.jsonObject(with: reportData) as? JSONDictionary else {
            throw PlaytestMCPError(message: "SwanSong produced a non-object playtest report")
        }
        if let sdkTrace = capture.sdkTrace {
            report["deterministicTraceBase64"] = sdkTrace.base64EncodedString()
        }
        let structuredData = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return [
            "content": [
                ["type": "text", "text": String(decoding: structuredData, as: UTF8.self)],
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

    private static func comparePlaytest(arguments: JSONDictionary) throws -> JSONDictionary {
        guard arguments["confirmShareCapture"] as? Bool == true else {
            throw PlaytestMCPError(
                message: "Set confirmShareCapture to true after confirming that both rendered game frames and both audio windows may be shared with this MCP client."
            )
        }
        guard let originalROMPath = arguments["originalROMPath"] as? String,
              let patchedROMPath = arguments["patchedROMPath"] as? String,
              let planValue = arguments["plan"] else {
            throw PlaytestMCPError(
                message: "originalROMPath, patchedROMPath, and plan are required"
            )
        }

        let originalROMURL = try validatedROMURL(
            path: originalROMPath,
            argumentName: "originalROMPath"
        )
        let patchedROMURL = try validatedROMURL(
            path: patchedROMPath,
            argumentName: "patchedROMPath"
        )
        guard originalROMURL != patchedROMURL else {
            throw PlaytestMCPError(
                message: "Original and Patched must resolve to two different nonsymlink files"
            )
        }

        let originalInitialSnapshot = try preflightROM(at: originalROMURL)
        let patchedInitialSnapshot = try preflightROM(at: patchedROMURL)
        guard originalInitialSnapshot.physicalIdentity
            != patchedInitialSnapshot.physicalIdentity else {
            throw PlaytestMCPError(
                message: "Original and Patched refer to the same physical ROM file"
            )
        }

        let plan = try decodePlan(planValue)
        let originalImage = try readStableROM(
            from: originalROMURL,
            initialSnapshot: originalInitialSnapshot
        )
        let patchedImage = try readStableROM(
            from: patchedROMURL,
            initialSnapshot: patchedInitialSnapshot
        )
        guard originalImage.sha256 != patchedImage.sha256 else {
            throw PlaytestMCPError(
                message: "Original and Patched have the same ROM digest; an A/B comparison requires different inputs"
            )
        }
        guard originalImage.hardwareModel == patchedImage.hardwareModel else {
            throw PlaytestMCPError(
                message: "Original and Patched require different WonderSwan hardware models"
            )
        }

        let originalCapture = try SwanSongPlaytester.run(
            image: originalImage,
            plan: plan
        )
        let patchedCapture = try SwanSongPlaytester.run(
            image: patchedImage,
            plan: plan
        )
        try requireMatchingDeterministicContext(
            original: originalCapture.report,
            patched: patchedCapture.report,
            plan: plan
        )

        let encoder = reportEncoder()
        let planData = try encoder.encode(plan)
        let report = PlaytestComparisonReport(
            schema: PlaytestComparisonReport.currentSchema,
            planSHA256: sha256(planData),
            deterministicContextMatched: true,
            original: originalCapture.report,
            patched: patchedCapture.report,
            delta: try comparisonDelta(
                original: originalCapture,
                patched: patchedCapture
            )
        )
        let reportData = try encoder.encode(report)
        guard let structuredReport = try JSONSerialization.jsonObject(
            with: reportData
        ) as? JSONDictionary else {
            throw PlaytestMCPError(
                message: "SwanSong produced a non-object playtest comparison report"
            )
        }
        return [
            "content": [
                ["type": "text", "text": String(decoding: reportData, as: UTF8.self)],
                ["type": "text", "text": "Original capture and final audio window follow."],
                [
                    "type": "image",
                    "data": originalCapture.png.base64EncodedString(),
                    "mimeType": "image/png",
                    "_meta": ["swansongRole": "original"],
                ],
                [
                    "type": "audio",
                    "data": originalCapture.audioWAV.base64EncodedString(),
                    "mimeType": "audio/wav",
                    "_meta": ["swansongRole": "original"],
                ],
                ["type": "text", "text": "Patched capture and final audio window follow."],
                [
                    "type": "image",
                    "data": patchedCapture.png.base64EncodedString(),
                    "mimeType": "image/png",
                    "_meta": ["swansongRole": "patched"],
                ],
                [
                    "type": "audio",
                    "data": patchedCapture.audioWAV.base64EncodedString(),
                    "mimeType": "audio/wav",
                    "_meta": ["swansongRole": "patched"],
                ],
            ],
            "structuredContent": structuredReport,
            "isError": false,
        ]
    }

    private static func validatedROMURL(
        path: String,
        argumentName: String
    ) throws -> URL {
        guard (path as NSString).isAbsolutePath else {
            throw PlaytestMCPError(message: "\(argumentName) must be an absolute path")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard ["ws", "wsc"].contains(url.pathExtension.lowercased()) else {
            throw PlaytestMCPError(
                message: "The playtest tools accept only .ws and .wsc ROM files"
            )
        }
        return url
    }

    private static func preflightROM(at romURL: URL) throws -> ROMFileSnapshot {
        let resolvedROMURL = romURL.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedROMURL == romURL else {
            throw PlaytestMCPError(
                message: "The ROM must be a bounded, nonsymlink regular file"
            )
        }
        let before = try romFileSnapshot(at: romURL)
        guard before.byteCount >= GameROMValidationPolicy.minimumByteCount,
              before.byteCount <= SwanSongPlaytester.maximumROMBytes else {
            throw PlaytestMCPError(
                message: "The ROM must be a bounded, nonsymlink regular file"
            )
        }
        return before
    }

    private static func readStableROM(
        from romURL: URL,
        initialSnapshot: ROMFileSnapshot
    ) throws -> LibraryGameImportImage {
        let image = try LibraryGameImageImporter.image(from: romURL)
        let corroboratingData = try Data(contentsOf: romURL)
        let after = try romFileSnapshot(at: romURL)
        guard initialSnapshot == after,
              image.data.count == initialSnapshot.byteCount,
              corroboratingData.count == initialSnapshot.byteCount,
              ManagedGameStore.sha256(corroboratingData) == image.sha256 else {
            throw PlaytestMCPError(
                message: "The ROM changed while SwanSong was reading it"
            )
        }
        return image
    }

    private static func romFileSnapshot(at romURL: URL) throws -> ROMFileSnapshot {
        let values = try romURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize else {
            throw PlaytestMCPError(
                message: "The ROM must be a bounded, nonsymlink regular file"
            )
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: romURL.path
        )
        guard let fileSystemNumber = (
            attributes[.systemNumber] as? NSNumber
        )?.uint64Value,
            let fileSystemFileNumber = (
                attributes[.systemFileNumber] as? NSNumber
            )?.uint64Value else {
            throw PlaytestMCPError(
                message: "SwanSong could not establish a stable physical ROM identity"
            )
        }
        return ROMFileSnapshot(
            byteCount: byteCount,
            modificationDate: values.contentModificationDate,
            physicalIdentity: ROMPhysicalIdentity(
                fileSystemNumber: fileSystemNumber,
                fileSystemFileNumber: fileSystemFileNumber
            )
        )
    }

    private static func decodePlan(_ value: Any) throws -> TranslationFrameInputPlan {
        let planData = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
    }

    private static func requireMatchingDeterministicContext(
        original: SwanSongPlaytestReport,
        patched: SwanSongPlaytestReport,
        plan: TranslationFrameInputPlan
    ) throws {
        guard original.plan == plan,
              patched.plan == plan,
              original.engineBackend == patched.engineBackend,
              original.engineBuildID == patched.engineBuildID,
              original.hardwareModel == patched.hardwareModel,
              original.openIPLIdentifier == patched.openIPLIdentifier,
              original.persistencePolicy == patched.persistencePolicy,
              original.rtcSeedUnixSeconds == patched.rtcSeedUnixSeconds,
              original.totalFrames == patched.totalFrames,
              original.scheduledInputTransitions == patched.scheduledInputTransitions,
              original.scheduledInputFrames == patched.scheduledInputFrames,
              original.finalFrameNumber == patched.finalFrameNumber else {
            throw PlaytestMCPError(
                message: "SwanSong could not establish matching deterministic A/B execution contexts"
            )
        }
    }

    private static func comparisonDelta(
        original: SwanSongPlaytestCapture,
        patched: SwanSongPlaytestCapture
    ) throws -> PlaytestComparisonDelta {
        let originalReport = original.report
        let patchedReport = patched.report
        let gameRasterChanged = originalReport.finalGameRasterSHA256
            != patchedReport.finalGameRasterSHA256
        let capturePNGChanged = originalReport.capturePNG_SHA256
            != patchedReport.capturePNG_SHA256
        let fullAudioPCMChanged = originalReport.audio.pcmFloatSHA256
            != patchedReport.audio.pcmFloatSHA256
        let finalWindowAudioPCMChanged = originalReport.audio.finalWindowPCMFloatSHA256
            != patchedReport.audio.finalWindowPCMFloatSHA256
        let finalWindowWAVChanged = originalReport.audio.finalWindowWAVSHA256
            != patchedReport.audio.finalWindowWAVSHA256
        let captureGeometryChanged = originalReport.captureWidth
            != patchedReport.captureWidth
            || originalReport.captureHeight != patchedReport.captureHeight
        var wholeFrameDifference: RGBFrameDifference?
        var wholeFrameChangedBounds: RGBFrameBounds?
        if !captureGeometryChanged {
            let originalFrame = try EngineFramePNGCodec.decode(
                original.png,
                frameNumber: originalReport.finalFrameNumber
            )
            let patchedFrame = try EngineFramePNGCodec.decode(
                patched.png,
                frameNumber: patchedReport.finalFrameNumber
            )
            let originalRGB = try FrameDifferential.rgb888FromBGRA(
                originalFrame.pixels,
                frameWidth: originalFrame.width,
                frameHeight: originalFrame.height,
                strideBytes: originalFrame.strideBytes,
                contentWidth: originalFrame.width,
                contentHeight: originalFrame.height
            )
            let patchedRGB = try FrameDifferential.rgb888FromBGRA(
                patchedFrame.pixels,
                frameWidth: patchedFrame.width,
                frameHeight: patchedFrame.height,
                strideBytes: patchedFrame.strideBytes,
                contentWidth: patchedFrame.width,
                contentHeight: patchedFrame.height
            )
            let visualization = try FrameDifferential.visualizeRGB888(
                expected: originalRGB,
                actual: patchedRGB,
                width: originalFrame.width,
                height: originalFrame.height
            )
            wholeFrameDifference = visualization.difference
            wholeFrameChangedBounds = visualization.changedBounds
        }
        let visualChanged = wholeFrameDifference.map {
            $0.differentPixelCount > 0
        } ?? (gameRasterChanged || capturePNGChanged)
        let audioChanged = fullAudioPCMChanged
            || finalWindowAudioPCMChanged
            || finalWindowWAVChanged
        let classification: String
        switch (visualChanged, audioChanged) {
        case (false, false): classification = "no-observable-delta"
        case (true, false): classification = "visual-only"
        case (false, true): classification = "audio-only"
        case (true, true): classification = "visual-and-audio"
        }
        return PlaytestComparisonDelta(
            classification: classification,
            visualChanged: visualChanged,
            gameRasterChanged: gameRasterChanged,
            capturePNGChanged: capturePNGChanged,
            wholeFramePixelMetricsAvailable: wholeFrameDifference != nil,
            wholeFramePixelCount: wholeFrameDifference?.pixelCount,
            wholeFrameDifferentPixelCount: wholeFrameDifference?.differentPixelCount,
            wholeFrameDifferentPixelFraction: wholeFrameDifference?.differentPixelFraction,
            wholeFrameMeanAbsoluteChannelError: wholeFrameDifference?.meanAbsoluteChannelError,
            wholeFrameMaximumChannelError: wholeFrameDifference?.maximumChannelError,
            wholeFrameChangedBounds: wholeFrameChangedBounds,
            audioChanged: audioChanged,
            fullAudioPCMChanged: fullAudioPCMChanged,
            finalWindowAudioPCMChanged: finalWindowAudioPCMChanged,
            finalWindowWAVChanged: finalWindowWAVChanged,
            captureGeometryChanged: captureGeometryChanged,
            audioFormatChanged: originalReport.audio.channels != patchedReport.audio.channels
                || originalReport.audio.sampleRate != patchedReport.audio.sampleRate,
            audioSampleFrameCountChanged: originalReport.audio.sampleFrames
                != patchedReport.audio.sampleFrames
        )
    }

    private static func reportEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func sha256(_ data: Data) -> String {
        ManagedGameStore.sha256(data)
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
                "plan": frameInputPlanSchema(),
                "confirmShareCapture": [
                    "type": "boolean",
                    "description": "Must be true to return rendered game image and audio media.",
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

    private static func comparePlaytestSchema() -> JSONDictionary {
        objectSchema(
            properties: [
                "originalROMPath": [
                    "type": "string",
                    "description": "Absolute path to the authorized local Original .ws or .wsc ROM.",
                ],
                "patchedROMPath": [
                    "type": "string",
                    "description": "Absolute path to the authorized local Patched .ws or .wsc ROM.",
                ],
                "plan": frameInputPlanSchema(),
                "confirmShareCapture": [
                    "type": "boolean",
                    "description": "Must be true to return both rendered game images and both audio windows.",
                ],
            ],
            required: [
                "originalROMPath",
                "patchedROMPath",
                "plan",
                "confirmShareCapture",
            ]
        )
    }

    private static func frameInputPlanSchema() -> JSONDictionary {
        [
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
        ]
    }
}
