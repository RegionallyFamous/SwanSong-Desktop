import CryptoKit
import Foundation

public struct SwanSongPlaytestAudioReport: Codable, Equatable, Sendable {
    public let channels: Int
    public let sampleRate: Int
    public let sampleFrames: Int
    public let nonzeroSamples: Int
    public let peakAbsoluteSample: Float
    public let pcmFloatSHA256: String
    public let finalWindowEmulatedFrames: Int
    public let finalWindowSampleFrames: Int
    public let finalWindowNonzeroSamples: Int
    public let finalWindowPeakAbsoluteSample: Float
    public let finalWindowPCMFloatSHA256: String
    public let finalWindowWAVByteCount: Int
    public let finalWindowWAVSHA256: String
}

public struct SwanSongPlaytestReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-playtest-report-v1"

    public let schema: String
    public let engineBackend: String
    public let engineBuildID: String
    public let hardwareModel: String
    public let openIPLIdentifier: String
    public let persistencePolicy: String
    public let rtcSeedUnixSeconds: UInt64
    public let romByteCount: Int
    public let romSHA256: String
    public let romChecksum: UInt16
    public let totalFrames: UInt64
    public let scheduledInputTransitions: Int
    public let scheduledInputFrames: UInt64
    public let finalFrameNumber: UInt64
    public let finalGameRasterSHA256: String
    public let captureWidth: Int
    public let captureHeight: Int
    public let capturePNG_SHA256: String
    public let audio: SwanSongPlaytestAudioReport
    public let plan: TranslationFrameInputPlan
}

public struct SwanSongPlaytestCapture: Sendable {
    public let report: SwanSongPlaytestReport
    public let png: Data
    public let audioWAV: Data

    public init(report: SwanSongPlaytestReport, png: Data, audioWAV: Data) {
        self.report = report
        self.png = png
        self.audioWAV = audioWAV
    }
}

struct PlaytestAudioAccumulator {
    static let finalWindowEmulatedFrames = 30

    var channels = 0
    var sampleRate = 0
    var sampleFrames = 0
    var nonzeroSamples = 0
    var peak: Float = 0
    var hasher = SHA256()
    var finalWindowBatches: [EngineAudioBatch] = []

    mutating func append(_ batch: EngineAudioBatch) {
        if batch.channels > 0 { channels = batch.channels }
        if batch.sampleRate > 0 { sampleRate = batch.sampleRate }
        sampleFrames += batch.frameCount
        for sample in batch.interleavedSamples {
            if sample != 0 { nonzeroSamples += 1 }
            peak = max(peak, abs(sample))
        }
        batch.interleavedSamples.withUnsafeBytes {
            hasher.update(bufferPointer: $0)
        }
        finalWindowBatches.append(batch)
        if finalWindowBatches.count > Self.finalWindowEmulatedFrames {
            finalWindowBatches.removeFirst()
        }
    }

    mutating func finish(finalWindowWAV: Data) -> SwanSongPlaytestAudioReport {
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        var tailHasher = SHA256()
        var tailFrames = 0
        var tailNonzero = 0
        var tailPeak: Float = 0
        for batch in finalWindowBatches {
            tailFrames += batch.frameCount
            for sample in batch.interleavedSamples {
                if sample != 0 { tailNonzero += 1 }
                tailPeak = max(tailPeak, abs(sample))
            }
            batch.interleavedSamples.withUnsafeBytes {
                tailHasher.update(bufferPointer: $0)
            }
        }
        let tailDigest = tailHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        return SwanSongPlaytestAudioReport(
            channels: channels,
            sampleRate: sampleRate,
            sampleFrames: sampleFrames,
            nonzeroSamples: nonzeroSamples,
            peakAbsoluteSample: peak,
            pcmFloatSHA256: digest,
            finalWindowEmulatedFrames: finalWindowBatches.count,
            finalWindowSampleFrames: tailFrames,
            finalWindowNonzeroSamples: tailNonzero,
            finalWindowPeakAbsoluteSample: tailPeak,
            finalWindowPCMFloatSHA256: tailDigest,
            finalWindowWAVByteCount: finalWindowWAV.count,
            finalWindowWAVSHA256: Self.sha256(finalWindowWAV)
        )
    }

    func encodeFinalWindowWAV() -> Data {
        let resolvedChannels = max(1, channels)
        let resolvedSampleRate = max(1, sampleRate)
        let samples = finalWindowBatches.flatMap(\.interleavedSamples)
        let dataByteCount = samples.count * MemoryLayout<Int16>.size
        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        Self.append(UInt32(36 + dataByteCount), to: &wav)
        wav.append(contentsOf: "WAVEfmt ".utf8)
        Self.append(UInt32(16), to: &wav)
        Self.append(UInt16(1), to: &wav)
        Self.append(UInt16(resolvedChannels), to: &wav)
        Self.append(UInt32(resolvedSampleRate), to: &wav)
        let byteRate = resolvedSampleRate * resolvedChannels * MemoryLayout<Int16>.size
        Self.append(UInt32(byteRate), to: &wav)
        Self.append(UInt16(resolvedChannels * MemoryLayout<Int16>.size), to: &wav)
        Self.append(UInt16(16), to: &wav)
        wav.append(contentsOf: "data".utf8)
        Self.append(UInt32(dataByteCount), to: &wav)
        for sample in samples {
            let scaled = max(-1, min(1, sample)) * Float(Int16.max)
            Self.append(UInt16(bitPattern: Int16(scaled.rounded())), to: &wav)
        }
        return wav
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Executes a bounded, deterministic input plan through SwanSong's own engine.
///
/// This is the sole black-box gameplay path used by the local MCP playtest
/// surface. It returns a rendered frame and evidence metadata, never ROM bytes,
/// save data, state data, persistence, or memory.
public enum SwanSongPlaytester {
    public static let maximumROMBytes = GameROMValidationPolicy.maximumByteCount
    public static let maximumMCPFrames: UInt64 = 12_000

    public static func run(
        image: LibraryGameImportImage,
        plan: TranslationFrameInputPlan
    ) throws -> SwanSongPlaytestCapture {
        guard plan.totalFrames <= maximumMCPFrames else {
            throw SwanEngineError(
                code: -1,
                detail: "An MCP playtest is limited to \(maximumMCPFrames) frames per observation."
            )
        }
        let hardware = try TranslationRouteHardwareModel(
            engineHardwareModel: image.hardwareModel
        )
        try plan.validate(for: hardware)

        let engine = try EngineSession(
            rtcMode: .deterministic(
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            hardwareModel: image.hardwareModel
        )
        guard engine.capabilities.contains(.execution) else {
            throw SwanEngineError(
                code: -1,
                detail: "This SwanSong build does not include the live execution engine."
            )
        }
        _ = try engine.load(rom: image.data)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == image.hardwareModel else {
            throw SwanEngineError(
                code: -1,
                detail: "SwanSong selected a different hardware model than the ROM requires."
            )
        }

        let scheduledEvents = try plan.routeEvents(for: hardware)
        var scheduledEventIndex = 0
        var input: EngineInput = []
        var inputFrames: UInt64 = 0
        var audio = PlaytestAudioAccumulator()
        for frameIndex in 0..<plan.totalFrames {
            if scheduledEventIndex < scheduledEvents.count,
               scheduledEvents[scheduledEventIndex].frameIndex == frameIndex {
                input = EngineInput(
                    rawValue: scheduledEvents[scheduledEventIndex].inputMask
                )
                scheduledEventIndex += 1
            }
            if !input.isEmpty { inputFrames += 1 }
            try engine.setInput(input)
            try engine.runFrame()
            audio.append(try engine.audioBatch())
        }
        let finalFrame = try engine.videoFrame()
        let png = try EngineFramePNGCodec.encode(finalFrame)
        let audioWAV = audio.encodeFinalWindowWAV()
        let report = SwanSongPlaytestReport(
            schema: SwanSongPlaytestReport.currentSchema,
            engineBackend: engine.backendName,
            engineBuildID: engine.buildID,
            hardwareModel: hardware.rawValue,
            openIPLIdentifier: WonderSwanOpenIPL.identifier,
            persistencePolicy: TranslationRouteStartContext.isolatedPersistencePolicy,
            rtcSeedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds,
            romByteCount: image.data.count,
            romSHA256: image.sha256,
            romChecksum: image.metadata.computedChecksum,
            totalFrames: plan.totalFrames,
            scheduledInputTransitions: plan.events.count,
            scheduledInputFrames: inputFrames,
            finalFrameNumber: finalFrame.number,
            finalGameRasterSHA256: try TranslationRouteCheckpoint.fingerprint(finalFrame),
            captureWidth: finalFrame.width,
            captureHeight: finalFrame.height,
            capturePNG_SHA256: sha256(png),
            audio: audio.finish(finalWindowWAV: audioWAV),
            plan: plan
        )
        return SwanSongPlaytestCapture(report: report, png: png, audioWAV: audioWAV)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
