import Foundation

public struct TranslationPersistedCapturePixelDiff: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-pixel-diff-v1"

    public let schema: String
    public let width: Int
    public let height: Int
    public let orientation: TranslationRouteFrameOrientation
    public let pixelEncoding: String
    public let difference: RGBFrameDifference
    public let differentPixelFraction: Double
    public let changedBounds: RGBFrameBounds?

    public init(
        width: Int,
        height: Int,
        orientation: TranslationRouteFrameOrientation,
        difference: RGBFrameDifference,
        changedBounds: RGBFrameBounds?
    ) {
        self.schema = Self.currentSchema
        self.width = width
        self.height = height
        self.orientation = orientation
        self.pixelEncoding = TranslationRouteCheckpoint.pixelEncoding
        self.difference = difference
        self.differentPixelFraction = difference.differentPixelFraction
        self.changedBounds = changedBounds
    }
}

public struct TranslationPersistedCaptureAudioFormat: Codable, Equatable, Sendable {
    public static let container = "wav"
    public static let encoding = "pcm-s16le"
    public static let bitsPerSample = 16

    public let container: String
    public let encoding: String
    public let channels: Int
    public let sampleRate: Int
    public let bitsPerSample: Int
    public let sampleFrames: Int

    public init(channels: Int, sampleRate: Int, sampleFrames: Int) {
        self.container = Self.container
        self.encoding = Self.encoding
        self.channels = channels
        self.sampleRate = sampleRate
        self.bitsPerSample = Self.bitsPerSample
        self.sampleFrames = sampleFrames
    }
}

public struct TranslationPersistedCaptureAudioRange: Codable, Equatable, Sendable {
    public let startFrameIndex: UInt64
    public let endFrameIndexExclusive: UInt64
    public let emulatedFrameCount: Int

    public init(
        startFrameIndex: UInt64,
        endFrameIndexExclusive: UInt64,
        emulatedFrameCount: Int
    ) {
        self.startFrameIndex = startFrameIndex
        self.endFrameIndexExclusive = endFrameIndexExclusive
        self.emulatedFrameCount = emulatedFrameCount
    }
}

/// Source-safe metadata for one private, role-specific final audio window.
/// The WAV bytes never appear in the serialized command report.
public struct TranslationPersistedCaptureAudio: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-persisted-capture-audio-v1"

    public let schema: String
    public let wav: TranslationArtifactDigest
    public let format: TranslationPersistedCaptureAudioFormat
    public let range: TranslationPersistedCaptureAudioRange
    public let nonzeroSamples: Int
    public let peakAbsoluteSample: Float
    public let pcmFloatSHA256: String
    public let bindingSHA256: String
}

public struct TranslationPersistedCaptureLane: Codable, Equatable, Sendable {
    public let role: TranslationROMRole
    public let rom: TranslationArtifactDigest
    public let romFooterChecksum: UInt16
    public let frameNumber: UInt64
    public let nativeFrameSHA256: String
    public let framePNG: TranslationArtifactDigest
    public let evidenceName: String
    public let evidenceManifest: TranslationArtifactDigest
    public let audio: TranslationPersistedCaptureAudio?
}

public struct TranslationPersistedCaptureManifest: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-persisted-translation-capture-v2"
    public static let legacySchema = "swan-song-persisted-translation-capture-v1"

    public let schema: String
    public let createdAt: Date
    public let projectTitle: String
    public let plan: TranslationArtifactDigest
    public let route: TranslationArtifactDigest
    public let engine: TranslationRouteEngineIdentity
    public let engineSHA256: String
    public let rtc: TranslationRouteRTCContext
    public let rtcSHA256: String
    public let persistencePolicy: String
    public let persistenceSHA256: String
    public let original: TranslationPersistedCaptureLane
    public let patched: TranslationPersistedCaptureLane
    public let pixelDiff: TranslationArtifactDigest
}

public struct TranslationPersistedCaptureArtifact: Sendable {
    public let name: String
    public let directoryURL: URL
    public let manifestURL: URL
    public let planURL: URL
    public let originalFrameURL: URL
    public let patchedFrameURL: URL
    public let pixelDiffURL: URL
    public let originalAudioURL: URL
    public let patchedAudioURL: URL
}

public struct TranslationPersistedCaptureReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-persisted-translation-capture-report-v2"

    public let schema: String
    public let projectTitle: String
    public let captureName: String
    public let manifestPath: String
    public let manifestSHA256: String
    public let planSHA256: String
    public let routeSHA256: String
    public let originalROMSHA256: String
    public let patchedROMSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let originalNativeFrameSHA256: String
    public let patchedNativeFrameSHA256: String
    public let originalAudio: TranslationPersistedCaptureAudio
    public let patchedAudio: TranslationPersistedCaptureAudio
    public let pixelDiffSHA256: String
    public let pixelCount: Int
    public let differentPixelCount: Int
    public let differentPixelFraction: Double
    public let changedBounds: RGBFrameBounds?
}

enum TranslationPersistedCaptureStore {
    private static let maximumPlanBytes = 1 * 1_024 * 1_024
    private static let maximumFrameBytes = 8 * 1_024 * 1_024
    static let maximumAudioBytes = 8 * 1_024 * 1_024

    static func save(
        project: TranslationProject,
        plan: TranslationFrameInputPlan,
        route: TranslationRoute,
        routeData: Data,
        original: TranslationEvidenceSummary,
        patched: TranslationEvidenceSummary,
        originalAudio: TranslationCapturePlanAudioCapture,
        patchedAudio: TranslationCapturePlanAudioCapture
    ) throws -> TranslationPersistedCaptureReport {
        try route.validateForProof()
        let hardware = try project.routeHardwareModel
        try plan.validate(for: hardware)
        guard plan.totalFrames == route.totalFrames,
              try plan.routeEvents(for: hardware) == route.events else {
            throw TranslationLabError.invalidProject(
                "the exact frame/input plan does not match the recorded immutable route"
            )
        }
        guard let start = route.start, let rtc = start.rtc else {
            throw TranslationLabError.invalidProject(
                "the route is missing its deterministic engine or RTC context"
            )
        }
        let routeDigest = digest(routeData)
        let originalInput = try laneInput(
            original,
            expectedRole: .original,
            expectedRoute: routeDigest,
            project: project
        )
        let patchedInput = try laneInput(
            patched,
            expectedRole: .patched,
            expectedRoute: routeDigest,
            project: project
        )
        guard originalInput.manifest.frameNumber == patchedInput.manifest.frameNumber else {
            throw TranslationLabError.invalidProject(
                "the persisted Original and Patched frames do not share one route endpoint"
            )
        }

        let originalFrame = try EngineFramePNGCodec.decode(
            originalInput.framePNG,
            frameNumber: originalInput.manifest.frameNumber
        )
        let patchedFrame = try EngineFramePNGCodec.decode(
            patchedInput.framePNG,
            frameNumber: patchedInput.manifest.frameNumber
        )
        let originalRaster = try TranslationRouteCheckpoint.canonicalGameRaster(originalFrame)
        let patchedRaster = try TranslationRouteCheckpoint.canonicalGameRaster(patchedFrame)
        guard originalRaster.descriptor == patchedRaster.descriptor else {
            throw TranslationLabError.invalidProject(
                "the persisted Original and Patched native raster geometry differs"
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

        let planData = try encoded(plan)
        guard planData.count <= maximumPlanBytes else {
            throw TranslationLabError.invalidProject(
                "the exact persisted frame/input plan exceeds its private artifact limit"
            )
        }
        let pixelDiffData = try encoded(pixelDiff)
        let engineData = try encoded(start.engine)
        let rtcData = try encoded(rtc)
        let persistenceData = Data(start.persistencePolicy.utf8)
        let originalAudioEvidence = try audioEvidence(
            originalAudio,
            role: .original,
            rom: originalInput.manifest.rom,
            plan: digest(planData),
            route: routeDigest,
            engineSHA256: sha256(engineData),
            rtcSHA256: sha256(rtcData),
            persistenceSHA256: sha256(persistenceData),
            totalFrames: plan.totalFrames
        )
        let patchedAudioEvidence = try audioEvidence(
            patchedAudio,
            role: .patched,
            rom: patchedInput.manifest.rom,
            plan: digest(planData),
            route: routeDigest,
            engineSHA256: sha256(engineData),
            rtcSHA256: sha256(rtcData),
            persistenceSHA256: sha256(persistenceData),
            totalFrames: plan.totalFrames
        )
        let originalLane = TranslationPersistedCaptureLane(
            role: .original,
            rom: originalInput.manifest.rom,
            romFooterChecksum: originalInput.manifest.romFooterChecksum,
            frameNumber: originalInput.manifest.frameNumber,
            nativeFrameSHA256: try nativeFrameSHA256(originalInput.manifest),
            framePNG: digest(originalInput.framePNG),
            evidenceName: original.artifact.name,
            evidenceManifest: digest(originalInput.manifestData),
            audio: originalAudioEvidence
        )
        let patchedLane = TranslationPersistedCaptureLane(
            role: .patched,
            rom: patchedInput.manifest.rom,
            romFooterChecksum: patchedInput.manifest.romFooterChecksum,
            frameNumber: patchedInput.manifest.frameNumber,
            nativeFrameSHA256: try nativeFrameSHA256(patchedInput.manifest),
            framePNG: digest(patchedInput.framePNG),
            evidenceName: patched.artifact.name,
            evidenceManifest: digest(patchedInput.manifestData),
            audio: patchedAudioEvidence
        )
        let createdAt = Date()
        let manifest = TranslationPersistedCaptureManifest(
            schema: TranslationPersistedCaptureManifest.currentSchema,
            createdAt: createdAt,
            projectTitle: project.title,
            plan: digest(planData),
            route: routeDigest,
            engine: start.engine,
            engineSHA256: sha256(engineData),
            rtc: rtc,
            rtcSHA256: sha256(rtcData),
            persistencePolicy: start.persistencePolicy,
            persistenceSHA256: sha256(persistenceData),
            original: originalLane,
            patched: patchedLane,
            pixelDiff: digest(pixelDiffData)
        )
        let manifestData = try encoded(manifest)
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: Int64(
                manifestData.count
                    + planData.count
                    + originalInput.framePNG.count
                    + patchedInput.framePNG.count
                    + originalAudio.wav.count
                    + patchedAudio.wav.count
                    + pixelDiffData.count
            )
        )
        let artifact = try publish(
            project: project,
            createdAt: createdAt,
            manifestData: manifestData,
            planData: planData,
            originalFramePNG: originalInput.framePNG,
            patchedFramePNG: patchedInput.framePNG,
            originalAudioWAV: originalAudio.wav,
            patchedAudioWAV: patchedAudio.wav,
            pixelDiffData: pixelDiffData
        )
        return TranslationPersistedCaptureReport(
            schema: TranslationPersistedCaptureReport.currentSchema,
            projectTitle: project.title,
            captureName: artifact.name,
            manifestPath: artifact.manifestURL.path,
            manifestSHA256: sha256(manifestData),
            planSHA256: manifest.plan.sha256,
            routeSHA256: manifest.route.sha256,
            originalROMSHA256: originalLane.rom.sha256,
            patchedROMSHA256: patchedLane.rom.sha256,
            engineSHA256: manifest.engineSHA256,
            rtcSHA256: manifest.rtcSHA256,
            persistenceSHA256: manifest.persistenceSHA256,
            originalNativeFrameSHA256: originalLane.nativeFrameSHA256,
            patchedNativeFrameSHA256: patchedLane.nativeFrameSHA256,
            originalAudio: originalAudioEvidence,
            patchedAudio: patchedAudioEvidence,
            pixelDiffSHA256: manifest.pixelDiff.sha256,
            pixelCount: visualization.difference.pixelCount,
            differentPixelCount: visualization.difference.differentPixelCount,
            differentPixelFraction: visualization.difference.differentPixelFraction,
            changedBounds: visualization.changedBounds
        )
    }

    static func validateAudio(
        _ audio: TranslationPersistedCaptureAudio,
        wav: Data,
        role: TranslationROMRole,
        rom: TranslationArtifactDigest,
        plan: TranslationArtifactDigest,
        route: TranslationArtifactDigest,
        engineSHA256: String,
        rtcSHA256: String,
        persistenceSHA256: String,
        totalFrames: UInt64
    ) throws {
        let sampleValueCount = audio.format.sampleFrames.multipliedReportingOverflow(
            by: audio.format.channels
        )
        guard audio.schema == TranslationPersistedCaptureAudio.currentSchema,
              totalFrames >= 3,
              totalFrames <= TranslationFrameInputPlan.maximumFrames,
              isValidArtifactDigest(rom),
              isValidArtifactDigest(plan),
              isValidArtifactDigest(route),
              isLowercaseSHA256(engineSHA256),
              isLowercaseSHA256(rtcSHA256),
              isLowercaseSHA256(persistenceSHA256),
              audio.wav == digest(wav),
              isLowercaseSHA256(audio.pcmFloatSHA256),
              isLowercaseSHA256(audio.bindingSHA256),
              audio.format.container == TranslationPersistedCaptureAudioFormat.container,
              audio.format.encoding == TranslationPersistedCaptureAudioFormat.encoding,
              audio.format.bitsPerSample
                == TranslationPersistedCaptureAudioFormat.bitsPerSample,
              audio.format.channels > 0,
              audio.format.channels
                <= TranslationCapturePlanAudioCollector.maximumChannels,
              audio.format.sampleRate
                >= TranslationCapturePlanAudioCollector.minimumSampleRate,
              audio.format.sampleRate
                <= TranslationCapturePlanAudioCollector.maximumSampleRate,
              audio.format.sampleFrames > 0,
              audio.format.sampleFrames
                <= TranslationCapturePlanAudioCollector.finalWindowEmulatedFrames
                    * TranslationCapturePlanAudioCollector
                        .maximumSampleFramesPerEmulatedFrame,
              !sampleValueCount.overflow,
              audio.range.endFrameIndexExclusive == totalFrames,
              audio.range.emulatedFrameCount == min(
                  TranslationCapturePlanAudioCollector.finalWindowEmulatedFrames,
                  Int(totalFrames)
              ),
              audio.range.startFrameIndex
                == totalFrames - UInt64(audio.range.emulatedFrameCount),
              audio.nonzeroSamples >= 0,
              audio.nonzeroSamples <= sampleValueCount.partialValue,
              audio.peakAbsoluteSample.isFinite,
              audio.peakAbsoluteSample >= 0 else {
            throw TranslationLabError.invalidProject(
                "the role-bound final audio metadata is absent or malformed"
            )
        }
        try validateWAV(wav, expected: audio.format)
        let binding = try audioBindingSHA256(
            audio: audio,
            role: role,
            rom: rom,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256
        )
        guard binding == audio.bindingSHA256 else {
            throw TranslationLabError.invalidProject(
                "the private final audio no longer matches its role and proof identity"
            )
        }
    }

    static func audioEvidence(
        _ capture: TranslationCapturePlanAudioCapture,
        role: TranslationROMRole,
        rom: TranslationArtifactDigest,
        plan: TranslationArtifactDigest,
        route: TranslationArtifactDigest,
        engineSHA256: String,
        rtcSHA256: String,
        persistenceSHA256: String,
        totalFrames: UInt64
    ) throws -> TranslationPersistedCaptureAudio {
        guard capture.wav.count <= maximumAudioBytes else {
            throw TranslationLabError.invalidProject(
                "the private final audio window exceeds its artifact limit"
            )
        }
        let unbound = TranslationPersistedCaptureAudio(
            schema: TranslationPersistedCaptureAudio.currentSchema,
            wav: digest(capture.wav),
            format: capture.format,
            range: capture.range,
            nonzeroSamples: capture.nonzeroSamples,
            peakAbsoluteSample: capture.peakAbsoluteSample,
            pcmFloatSHA256: capture.pcmFloatSHA256,
            bindingSHA256: String(repeating: "0", count: 64)
        )
        let binding = try audioBindingSHA256(
            audio: unbound,
            role: role,
            rom: rom,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256
        )
        let bound = TranslationPersistedCaptureAudio(
            schema: unbound.schema,
            wav: unbound.wav,
            format: unbound.format,
            range: unbound.range,
            nonzeroSamples: unbound.nonzeroSamples,
            peakAbsoluteSample: unbound.peakAbsoluteSample,
            pcmFloatSHA256: unbound.pcmFloatSHA256,
            bindingSHA256: binding
        )
        try validateAudio(
            bound,
            wav: capture.wav,
            role: role,
            rom: rom,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            totalFrames: totalFrames
        )
        return bound
    }

    private struct AudioBinding: Codable {
        static let currentSchema = "swan-song-persisted-capture-audio-binding-v1"

        let schema: String
        let role: TranslationROMRole
        let rom: TranslationArtifactDigest
        let plan: TranslationArtifactDigest
        let route: TranslationArtifactDigest
        let engineSHA256: String
        let rtcSHA256: String
        let persistenceSHA256: String
        let wav: TranslationArtifactDigest
        let format: TranslationPersistedCaptureAudioFormat
        let range: TranslationPersistedCaptureAudioRange
        let nonzeroSamples: Int
        let peakAbsoluteSample: Float
        let pcmFloatSHA256: String
    }

    private static func audioBindingSHA256(
        audio: TranslationPersistedCaptureAudio,
        role: TranslationROMRole,
        rom: TranslationArtifactDigest,
        plan: TranslationArtifactDigest,
        route: TranslationArtifactDigest,
        engineSHA256: String,
        rtcSHA256: String,
        persistenceSHA256: String
    ) throws -> String {
        sha256(try encoded(AudioBinding(
            schema: AudioBinding.currentSchema,
            role: role,
            rom: rom,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            wav: audio.wav,
            format: audio.format,
            range: audio.range,
            nonzeroSamples: audio.nonzeroSamples,
            peakAbsoluteSample: audio.peakAbsoluteSample,
            pcmFloatSHA256: audio.pcmFloatSHA256
        )))
    }

    private static func validateWAV(
        _ wav: Data,
        expected: TranslationPersistedCaptureAudioFormat
    ) throws {
        guard wav.count >= 44,
              wav.count <= maximumAudioBytes,
              String(decoding: wav[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ",
              littleEndianUInt32(wav, at: 4) == UInt32(wav.count - 8),
              littleEndianUInt32(wav, at: 16) == 16,
              littleEndianUInt16(wav, at: 20) == 1,
              Int(littleEndianUInt16(wav, at: 22)) == expected.channels,
              Int(littleEndianUInt32(wav, at: 24)) == expected.sampleRate,
              Int(littleEndianUInt32(wav, at: 28))
                == expected.sampleRate * expected.channels * 2,
              Int(littleEndianUInt16(wav, at: 32)) == expected.channels * 2,
              Int(littleEndianUInt16(wav, at: 34)) == expected.bitsPerSample,
              String(decoding: wav[36..<40], as: UTF8.self) == "data",
              Int(littleEndianUInt32(wav, at: 40)) == wav.count - 44,
              wav.count - 44 == expected.sampleFrames * expected.channels * 2 else {
            throw TranslationLabError.invalidProject(
                "the private final audio artifact is not its declared PCM WAV"
            )
        }
    }

    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64
            && value == value.lowercased()
            && value.allSatisfy(\.isHexDigit)
    }

    private static func isValidArtifactDigest(
        _ digest: TranslationArtifactDigest
    ) -> Bool {
        digest.byteCount > 0 && isLowercaseSHA256(digest.sha256)
    }

    private struct LaneInput {
        let manifest: TranslationEvidenceManifest
        let manifestData: Data
        let framePNG: Data
    }

    private static func laneInput(
        _ evidence: TranslationEvidenceSummary,
        expectedRole: TranslationROMRole,
        expectedRoute: TranslationArtifactDigest,
        project: TranslationProject
    ) throws -> LaneInput {
        guard evidence.isIntact,
              let manifest = evidence.manifest,
              manifest.romRole == expectedRole,
              manifest.route == expectedRoute,
              manifest.isolatedPersistence,
              project.contains(evidence.artifact.directoryURL),
              project.contains(evidence.artifact.manifestURL),
              project.contains(evidence.artifact.frameURL) else {
            throw TranslationLabError.invalidProject(
                "the (expectedRole.title) evidence is not an intact route-bound private capture"
            )
        }
        let manifestData = try boundedRegularFile(
            evidence.artifact.manifestURL,
            maximumBytes: 1 * 1_024 * 1_024,
            project: project
        )
        let framePNG = try boundedRegularFile(
            evidence.artifact.frameURL,
            maximumBytes: maximumFrameBytes,
            project: project
        )
        guard digest(framePNG) == manifest.frame else {
            throw TranslationLabError.invalidProject(
                "the (expectedRole.title) native frame changed before pair publication"
            )
        }
        return LaneInput(
            manifest: manifest,
            manifestData: manifestData,
            framePNG: framePNG
        )
    }

    private static func nativeFrameSHA256(
        _ manifest: TranslationEvidenceManifest
    ) throws -> String {
        guard let digest = manifest.gameFrameSHA256,
              digest.count == 64,
              digest == digest.lowercased(),
              digest.allSatisfy(\.isHexDigit) else {
            throw TranslationLabError.invalidProject(
                "the route-bound evidence is missing its native game-frame fingerprint"
            )
        }
        return digest
    }

    static func publish(
        project: TranslationProject,
        createdAt: Date,
        manifestData: Data,
        planData: Data,
        originalFramePNG: Data,
        patchedFramePNG: Data,
        originalAudioWAV: Data,
        patchedAudioWAV: Data,
        pixelDiffData: Data,
        failureAfterWritingFileCount: Int? = nil
    ) throws -> TranslationPersistedCaptureArtifact {
        let lab = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
        let pairs = lab.appendingPathComponent("pairs", isDirectory: true)
        try preparePrivateDirectory(pairs, project: project)
        let timestamp = ISO8601DateFormatter().string(from: createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let name = "pair-\(timestamp)-\(UUID().uuidString.prefix(8))"
        let staging = pairs.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let final = pairs.appendingPathComponent(name, isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var committed = false
        defer {
            if !committed { try? fileManager.removeItem(at: staging) }
        }
        let files: [(String, Data)] = [
            ("plan.json", planData),
            ("original.png", originalFramePNG),
            ("patched.png", patchedFramePNG),
            ("original.wav", originalAudioWAV),
            ("patched.wav", patchedAudioWAV),
            ("pixel-diff.json", pixelDiffData),
            ("manifest.json", manifestData),
        ]
        var writtenFileCount = 0
        for (filename, data) in files {
            let url = staging.appendingPathComponent(filename, isDirectory: false)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            writtenFileCount += 1
            if failureAfterWritingFileCount == writtenFileCount {
                throw TranslationLabError.invalidProject(
                    "injected private pair publication failure"
                )
            }
        }
        try fileManager.moveItem(at: staging, to: final)
        committed = true
        return TranslationPersistedCaptureArtifact(
            name: name,
            directoryURL: final,
            manifestURL: final.appendingPathComponent("manifest.json"),
            planURL: final.appendingPathComponent("plan.json"),
            originalFrameURL: final.appendingPathComponent("original.png"),
            patchedFrameURL: final.appendingPathComponent("patched.png"),
            pixelDiffURL: final.appendingPathComponent("pixel-diff.json"),
            originalAudioURL: final.appendingPathComponent("original.wav"),
            patchedAudioURL: final.appendingPathComponent("patched.wav")
        )
    }

    private static func preparePrivateDirectory(
        _ target: URL,
        project: TranslationProject
    ) throws {
        let standardized = target.standardizedFileURL
        guard project.contains(standardized) else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        let relative = try project.relativePath(for: standardized)
        var current = project.rootURL
        for component in relative.split(separator: "/").map(String.init) {
            guard component != ".", component != "..", !component.isEmpty else {
                throw TranslationLabError.unsafePath(standardized.path)
            }
            current.appendPathComponent(component, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: current.path,
                isDirectory: &isDirectory
            ) {
                let values = try current.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ])
                guard isDirectory.boolValue,
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      current.resolvingSymlinksInPath().standardizedFileURL == current
                else {
                    throw TranslationLabError.unsafePath(current.path)
                }
            } else {
                try FileManager.default.createDirectory(
                    at: current,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        }
    }

    private static func boundedRegularFile(
        _ url: URL,
        maximumBytes: Int,
        project: TranslationProject
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
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= maximumBytes else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        let data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
        guard data.count == byteCount else {
            throw TranslationLabError.invalidProject(
                "a private capture artifact changed while SwanSong was reading it"
            )
        }
        return data
    }

    private static func digest(_ data: Data) -> TranslationArtifactDigest {
        TranslationArtifactDigest(byteCount: data.count, sha256: sha256(data))
    }

    private static func sha256(_ data: Data) -> String {
        TranslationEvidenceStore.sha256(data)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
