import Foundation
import SwanSongKit

/// The authorized runner keeps emulation and artifact publication separate.
/// This value contains every byte needed by the predeclared output graph, but
/// constructing it performs no filesystem write.
struct AuthorizedCapturePlanExecution {
    struct Endpoint {
        let role: TranslationROMRole
        let romURL: URL
        let rom: Data
        let romFooterChecksum: UInt16
        let backend: String
        let frameNumber: UInt64
        let nativeFrameSHA256: String
        let framePNG: Data
        let state: Data
        let internalRAM: Data
    }

    let plan: TranslationFrameInputPlan
    let route: TranslationRoute
    let routeData: Data
    let original: Endpoint
    let patched: Endpoint
    let pixelDiff: TranslationPersistedCapturePixelDiff
    let pixelDiffData: Data
}

enum AuthorizedCapturePlanExecutor {
    enum ComparisonPolicy: Equatable {
        case publicSameROMNoDelta
        case authorizedCommercialPair
    }

    private static let deterministicCreatedAt = Date(
        timeIntervalSince1970: TimeInterval(TranslationRouteRTCContext.proofSeedUnixSeconds)
    )

    static func run(
        project: TranslationProject,
        plan: TranslationFrameInputPlan,
        originalROM: Data,
        patchedROM: Data,
        expectedEngineABI: UInt32,
        comparisonPolicy: ComparisonPolicy
    ) throws -> AuthorizedCapturePlanExecution {
        let hardware = try project.routeHardwareModel
        let routeEvents = try plan.routeEvents(for: hardware)
        let originalDigest = TranslationArtifactDigest(
            byteCount: originalROM.count,
            sha256: TranslationEvidenceStore.sha256(originalROM)
        )

        let route: TranslationRoute
        do {
            let recordingEngine = try proofEngine(hardware: hardware)
            _ = try recordingEngine.load(rom: originalROM)
            defer { try? recordingEngine.unload() }
            try validate(
                engine: recordingEngine,
                hardware: hardware,
                expectedEngineABI: expectedEngineABI
            )
            let start = TranslationRouteStartContext(
                hardwareModel: hardware,
                firmware: TranslationRouteFirmware(
                    source: .openIPL,
                    identifier: WonderSwanOpenIPL.identifier
                ),
                engine: TranslationRouteEngineIdentity(
                    backend: recordingEngine.backendName,
                    buildID: recordingEngine.buildID
                ),
                rtc: .proof
            )
            var finalRecordingFrame: EngineVideoFrame?
            for frameIndex in 0..<plan.totalFrames {
                try recordingEngine.setInput(plan.input(at: frameIndex))
                try recordingEngine.runFrame()
                finalRecordingFrame = try recordingEngine.videoFrame()
            }
            guard let finalRecordingFrame else {
                throw TranslationLabError.noRecordedFrames
            }
            route = try TranslationRoute(
                createdAt: deterministicCreatedAt,
                recordedFrom: .original,
                sourceROM: originalDigest,
                start: start,
                totalFrames: plan.totalFrames,
                events: routeEvents,
                checkpoint: TranslationRouteCheckpoint(
                    frameIndex: plan.totalFrames - 1,
                    frame: finalRecordingFrame
                )
            )
        }
        let routeData = try encoded(route)
        let original = try replay(
            role: .original,
            project: project,
            rom: originalROM,
            route: route,
            hardware: hardware,
            expectedEngineABI: expectedEngineABI
        )
        let patched = try replay(
            role: .patched,
            project: project,
            rom: patchedROM,
            route: route,
            hardware: hardware,
            expectedEngineABI: expectedEngineABI
        )
        guard original.frameNumber == patched.frameNumber else {
            throw TranslationLabError.invalidRoute(
                "Original and Patched did not reach the same native frame number"
            )
        }
        let originalFrame = try EngineFramePNGCodec.decode(
            original.framePNG,
            frameNumber: original.frameNumber
        )
        let patchedFrame = try EngineFramePNGCodec.decode(
            patched.framePNG,
            frameNumber: patched.frameNumber
        )
        let originalRaster = try TranslationRouteCheckpoint.canonicalGameRaster(originalFrame)
        let patchedRaster = try TranslationRouteCheckpoint.canonicalGameRaster(patchedFrame)
        guard originalRaster.descriptor == patchedRaster.descriptor else {
            throw TranslationLabError.invalidRoute(
                "Original and Patched native raster geometry differs"
            )
        }
        let descriptor = originalRaster.descriptor
        let visualization = try FrameDifferential.visualizeRGB888(
            expected: originalRaster.rgb888(),
            actual: patchedRaster.rgb888(),
            width: descriptor.width,
            height: descriptor.height
        )
        let pixelDiff = TranslationPersistedCapturePixelDiff(
            width: descriptor.width,
            height: descriptor.height,
            orientation: descriptor.orientation,
            difference: visualization.difference,
            changedBounds: visualization.changedBounds
        )
        if comparisonPolicy == .publicSameROMNoDelta {
            guard originalROM == patchedROM,
                  original.framePNG == patched.framePNG,
                  original.nativeFrameSHA256 == patched.nativeFrameSHA256,
                  visualization.difference.differentPixelCount == 0,
                  visualization.difference.differentPixelFraction == 0,
                  visualization.changedBounds == nil else {
                throw TranslationLabError.invalidRoute(
                    "the pinned same-ROM public capture control produced a native frame delta"
                )
            }
        }
        return AuthorizedCapturePlanExecution(
            plan: plan,
            route: route,
            routeData: routeData,
            original: original,
            patched: patched,
            pixelDiff: pixelDiff,
            pixelDiffData: try encoded(pixelDiff)
        )
    }

    private static func replay(
        role: TranslationROMRole,
        project: TranslationProject,
        rom: Data,
        route: TranslationRoute,
        hardware: TranslationRouteHardwareModel,
        expectedEngineABI: UInt32
    ) throws -> AuthorizedCapturePlanExecution.Endpoint {
        let romURL = try project.romURL(for: role)
        if role == .original {
            guard route.sourceROM == TranslationArtifactDigest(
                byteCount: rom.count,
                sha256: TranslationEvidenceStore.sha256(rom)
            ) else {
                throw TranslationLabError.invalidRoute(
                    "the Original ROM changed after the authorized recording pass"
                )
            }
        }
        let metadata = try EngineSession.inspect(rom: rom)
        let engine = try proofEngine(hardware: hardware)
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        try validate(
            engine: engine,
            hardware: hardware,
            expectedEngineABI: expectedEngineABI
        )
        guard let start = route.start,
              engine.backendName == start.engine.backend,
              engine.buildID == start.engine.buildID else {
            throw TranslationLabError.invalidRoute(
                "the engine identity changed during the authorized capture"
            )
        }
        var finalFrame: EngineVideoFrame?
        for frameIndex in 0..<route.totalFrames {
            try engine.setInput(route.input(at: frameIndex))
            try engine.runFrame()
            finalFrame = try engine.videoFrame()
        }
        guard let frame = finalFrame else {
            throw TranslationLabError.noRecordedFrames
        }
        if role == .original, route.checkpoint?.matches(frame) != true {
            throw TranslationLabError.invalidRoute(
                "Original did not reproduce the authorized route checkpoint"
            )
        }
        return AuthorizedCapturePlanExecution.Endpoint(
            role: role,
            romURL: romURL,
            rom: rom,
            romFooterChecksum: metadata.computedChecksum,
            backend: engine.backendName,
            frameNumber: frame.number,
            nativeFrameSHA256: try TranslationRouteCheckpoint.fingerprint(frame),
            framePNG: try EngineFramePNGCodec.encode(frame),
            state: try engine.captureState(),
            internalRAM: try engine.captureMemory(.internalRAM)
        )
    }

    private static func proofEngine(
        hardware: TranslationRouteHardwareModel
    ) throws -> EngineSession {
        try EngineSession(
            rtcMode: .deterministic(
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            hardwareModel: hardware.engineHardwareModel
        )
    }

    private static func validate(
        engine: EngineSession,
        hardware: TranslationRouteHardwareModel,
        expectedEngineABI: UInt32
    ) throws {
        guard engine.capabilities.contains(.execution),
              engine.capabilities.contains(.saveStates),
              engine.capabilities.contains(.debugger),
              engine.backendName == "ares",
              engine.abiVersion == expectedEngineABI,
              engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw TranslationLabError.invalidRoute(
                "the loaded engine does not satisfy the authorized capture contract"
            )
        }
    }

    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }
}
