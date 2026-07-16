import Darwin
import Foundation
import SwanSongKit

private struct Options {
    var rom: URL?
    var frameCount = 600
    var warmupFrameCount: Int?
    var report: URL?
    var capture: URL?
    var hardwareModel: EngineHardwareModel = .automatic
    var requireVideoActivity = false
    var requireStateReplayExact = false
    var requireSettledStateReplayExact = false
    var requirePocketChallengeV2FixtureContract = false
    var exerciseInputs = false
}

private struct InputExerciseReport: Codable {
    let plan: String
    let comparedFrames: Int
    let settleFramesIgnored: Int
    let framesWithInput: Int
    let firstVideoDivergenceOffset: Int?
    let firstAudioDivergenceOffset: Int?
    let videoDiverged: Bool
    let audioDiverged: Bool
}

private struct ProbeReport: Codable {
    let schema: String
    let romName: String
    let system: String
    let openIPLIdentifier: String
    let rtcMode: String
    let rtcSeedUnixSeconds: UInt64
    let footerChecksumValid: Bool
    let footerValid: Bool
    let compactLayout: Bool
    let backend: String
    let configuredHardwareModel: String
    let activeHardwareModel: String?
    let activeHardwareModelClearedAfterUnload: Bool?
    let pocketChallengeV2CapabilityAdvertised: Bool
    let framesRun: Int
    let startupWarmupFrames: Int
    let postStartupObservationFrames: Int
    let finalFrame: UInt64
    let contentWidth: Int
    let contentHeight: Int
    let firstNonUniformFrame: UInt64?
    let distinctContentFrames: Int
    let longestUniformRun: Int
    let finalContentFNV1A64: String
    let videoActivityDetected: Bool
    let startupFirstNonUniformFrame: UInt64?
    let startupDistinctContentFrames: Int
    let startupVideoActivityDetected: Bool
    let startupAudioFramesProduced: Int
    let startupNonzeroAudioSamples: Int
    let postStartupFirstNonUniformFrame: UInt64?
    let postStartupDistinctContentFrames: Int
    let postStartupVideoActivityDetected: Bool
    let postStartupAudioFramesProduced: Int
    let postStartupNonzeroAudioSamples: Int
    let audioFramesProduced: Int
    let nonzeroAudioSamples: Int
    let audioChannels: Int
    let audioSampleRate: Int
    let stateByteCount: Int
    let stateReplayFrame: UInt64
    let stateReplayVideoFNV1A64: String
    let stateReplayAudioFrames: Int
    let firstReplayFrameExact: Bool
    let settledStateReplayFrame: UInt64
    let settledStateReplayVideoFNV1A64: String
    let settledStateReplayAudioFrames: Int
    let settledReplayFrameExact: Bool
    let persistenceKinds: [String]
    let cartridgeFlashByteCount: Int?
    let cartridgeFlashMatchesROM: Bool?
    let cartridgeFlashRoundTripExact: Bool?
    let consoleEEPROMAbsent: Bool
    let pocketChallengeV2InternalRAMByteCount: Int?
    let pocketChallengeV2KARNAKResult: UInt8?
    let pocketChallengeV2KARNAKExact: Bool?
    let pocketChallengeV2InputRowsAll: [UInt8]?
    let pocketChallengeV2InputRowsLeft: [UInt8]?
    let pocketChallengeV2InputContractExact: Bool?
    let freshBootFirstVideoExact: Bool?
    let freshBootFirstAudioExact: Bool?
    let inputExercise: InputExerciseReport?
}

private struct ProbeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
private struct SwanSongProbe {
    private static let deterministicRTCSeed: UInt64 = 1

    static func main() {
        do {
            try run()
        } catch {
            let message = "SwanSongProbe: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }

    private static func run() throws {
        let options = try parseOptions()
        guard let romURL = options.rom else {
            throw ProbeError(message: usage)
        }
        let warmupFrameCount = options.warmupFrameCount
            ?? min(120, max(0, options.frameCount - 1))
        guard warmupFrameCount < options.frameCount else {
            throw ProbeError(
                message: "--warmup-frames must be smaller than --frames so the post-startup observation window is not empty."
            )
        }

        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let metadata = try EngineSession.inspect(rom: rom)
        let configuredSystem: EngineHardwareModel
        switch options.hardwareModel {
        case .automatic:
            configuredSystem = metadata.isColor ? .wonderSwanColor : .wonderSwan
        case .wonderSwan:
            configuredSystem = .wonderSwan
        case .wonderSwanColor:
            configuredSystem = .wonderSwanColor
        case .swanCrystal:
            configuredSystem = .swanCrystal
        case .pocketChallengeV2:
            configuredSystem = .pocketChallengeV2
        }

        if options.requirePocketChallengeV2FixtureContract {
            guard options.hardwareModel == .pocketChallengeV2 else {
                throw ProbeError(
                    message: "--require-pcv2-fixture-contract requires --hardware-model pocket-challenge-v2."
                )
            }
            guard ["pc2", "pcv2"].contains(romURL.pathExtension.lowercased()) else {
                throw ProbeError(
                    message: "The Pocket Challenge V2 fixture contract requires a .pc2 or .pcv2 cartridge."
                )
            }
        }

        let engine = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: deterministicRTCSeed),
            hardwareModel: options.hardwareModel
        )
        guard engine.capabilities.contains(.execution) else {
            throw ProbeError(message: "SwanSongProbe requires the live ares engine.")
        }
        if options.hardwareModel == .pocketChallengeV2,
           !engine.capabilities.contains(.pocketChallengeV2) {
            throw ProbeError(message: "The live engine does not advertise Pocket Challenge V2 support.")
        }
        _ = try engine.load(rom: rom)
        let activeHardwareModel = engine.activeHardwareModel
        guard options.hardwareModel == .automatic || activeHardwareModel == options.hardwareModel else {
            throw ProbeError(
                message: "The live engine selected \(activeHardwareModel?.rawValue ?? "no hardware") instead of \(options.hardwareModel.rawValue)."
            )
        }

        var monitor = FrameActivityMonitor(attentionThreshold: options.frameCount + 1)
        var distinctHashes = Set<String>()
        var startupMonitor = FrameActivityMonitor(
            attentionThreshold: options.frameCount + 1
        )
        var startupDistinctHashes = Set<String>()
        var postStartupMonitor = FrameActivityMonitor(
            attentionThreshold: options.frameCount + 1
        )
        var postStartupDistinctHashes = Set<String>()
        var firstNonUniformFrame: UInt64?
        var startupFirstNonUniformFrame: UInt64?
        var postStartupFirstNonUniformFrame: UInt64?
        var longestUniformRun = 0
        var finalFrame: EngineVideoFrame?
        var finalRGB = Data()
        var audioFramesProduced = 0
        var nonzeroAudioSamples = 0
        var startupAudioFramesProduced = 0
        var startupNonzeroAudioSamples = 0
        var postStartupAudioFramesProduced = 0
        var postStartupNonzeroAudioSamples = 0
        var audioChannels = 0
        var audioSampleRate = 0
        var firstFrame: EngineVideoFrame?
        var firstRGB = Data()
        var firstAudio: EngineAudioBatch?

        for frameIndex in 0..<options.frameCount {
            try engine.setInput([])
            try engine.runFrame()
            let frame = try engine.videoFrame()
            let audio = try engine.audioBatch()
            let rgb = try contentRGB(frame)
            let activity = monitor.observe(frame)
            if activity.consecutiveUniformFrames == 0, firstNonUniformFrame == nil {
                firstNonUniformFrame = frame.number
            }
            longestUniformRun = max(longestUniformRun, activity.consecutiveUniformFrames)
            let frameHash = FrameDifferential.fnv1a64(rgb)
            distinctHashes.insert(frameHash)
            let frameNonzeroAudioSamples = audio.interleavedSamples.count { $0 != 0 }
            if frameIndex < warmupFrameCount {
                let startupActivity = startupMonitor.observe(frame)
                if startupActivity.consecutiveUniformFrames == 0,
                   startupFirstNonUniformFrame == nil {
                    startupFirstNonUniformFrame = frame.number
                }
                startupDistinctHashes.insert(frameHash)
                startupAudioFramesProduced += audio.frameCount
                startupNonzeroAudioSamples += frameNonzeroAudioSamples
            } else {
                let postStartupActivity = postStartupMonitor.observe(frame)
                if postStartupActivity.consecutiveUniformFrames == 0,
                   postStartupFirstNonUniformFrame == nil {
                    postStartupFirstNonUniformFrame = frame.number
                }
                postStartupDistinctHashes.insert(frameHash)
                postStartupAudioFramesProduced += audio.frameCount
                postStartupNonzeroAudioSamples += frameNonzeroAudioSamples
            }
            if firstFrame == nil {
                firstFrame = frame
                firstRGB = rgb
                firstAudio = audio
            }
            finalFrame = frame
            finalRGB = rgb
            audioFramesProduced += audio.frameCount
            nonzeroAudioSamples += frameNonzeroAudioSamples
            audioChannels = audio.channels
            audioSampleRate = audio.sampleRate
        }

        guard let finalFrame else {
            throw ProbeError(message: "The engine produced no video frames.")
        }
        let dimensions = contentDimensions(finalFrame)
        let activityDetected = firstNonUniformFrame != nil && distinctHashes.count > 1
        let startupActivityDetected = startupFirstNonUniformFrame != nil
            && startupDistinctHashes.count > 1
        let postStartupActivityDetected = postStartupFirstNonUniformFrame != nil
            && postStartupDistinctHashes.count > 1
        let state = try engine.captureState()
        try engine.setInput([])
        try engine.runFrame()
        let expectedReplayFrame = try engine.videoFrame()
        let expectedReplayRGB = try contentRGB(expectedReplayFrame)
        let expectedReplayAudio = try engine.audioBatch()
        try engine.setInput([])
        try engine.runFrame()
        let expectedSettledReplayFrame = try engine.videoFrame()
        let expectedSettledReplayRGB = try contentRGB(expectedSettledReplayFrame)
        let expectedSettledReplayAudio = try engine.audioBatch()
        try engine.restoreState(state)
        try engine.setInput([])
        try engine.runFrame()
        let actualReplayFrame = try engine.videoFrame()
        let actualReplayRGB = try contentRGB(actualReplayFrame)
        let actualReplayAudio = try engine.audioBatch()
        let firstReplayFrameExact = expectedReplayFrame.number == actualReplayFrame.number
            && expectedReplayRGB == actualReplayRGB
            && expectedReplayAudio.channels == actualReplayAudio.channels
            && expectedReplayAudio.sampleRate == actualReplayAudio.sampleRate
            && expectedReplayAudio.interleavedSamples == actualReplayAudio.interleavedSamples
        try engine.setInput([])
        try engine.runFrame()
        let actualSettledReplayFrame = try engine.videoFrame()
        let actualSettledReplayRGB = try contentRGB(actualSettledReplayFrame)
        let actualSettledReplayAudio = try engine.audioBatch()
        let settledReplayFrameExact = expectedSettledReplayRGB == actualSettledReplayRGB
            && expectedSettledReplayAudio.channels == actualSettledReplayAudio.channels
            && expectedSettledReplayAudio.sampleRate == actualSettledReplayAudio.sampleRate
            && expectedSettledReplayAudio.interleavedSamples
                == actualSettledReplayAudio.interleavedSamples

        let inputExercise = options.exerciseInputs
            ? try runInputExercise(engine: engine, hardwareModel: activeHardwareModel)
            : nil

        var persistence = try engine.capturePersistence()
        let persistenceKinds = persistence.regions.keys.map(\.rawValue).sorted()
        let consoleEEPROMAbsent = persistence.regions[.consoleEEPROM] == nil
        var cartridgeFlashByteCount: Int?
        var cartridgeFlashMatchesROM: Bool?
        var cartridgeFlashRoundTripExact: Bool?
        var pcv2InternalRAMByteCount: Int?
        var pcv2KARNAKResult: UInt8?
        var pcv2KARNAKExact: Bool?
        var pcv2InputRowsAll: [UInt8]?
        var pcv2InputRowsLeft: [UInt8]?
        var pcv2InputContractExact: Bool?
        var activeHardwareModelClearedAfterUnload: Bool?
        var freshBootFirstVideoExact: Bool?
        var freshBootFirstAudioExact: Bool?

        if options.requirePocketChallengeV2FixtureContract {
            guard let flash = persistence.regions[.cartridgeFlash] else {
                throw ProbeError(message: "The PCV2 cartridge did not expose program flash persistence.")
            }
            cartridgeFlashByteCount = flash.count
            cartridgeFlashMatchesROM = flash == rom

            let initialMemory = try engine.captureMemory(.internalRAM)
            pcv2InternalRAMByteCount = initialMemory.count
            guard initialMemory.indices.contains(0x3FFE) else {
                throw ProbeError(message: "The PCV2 engine exposed less than 16 KiB of internal RAM.")
            }
            pcv2KARNAKResult = initialMemory[0x3FFE]
            pcv2KARNAKExact = pcv2KARNAKResult == 0xBF

            let allSemanticInputs: EngineInput = [
                .pocketChallengeUp,
                .pocketChallengeRight,
                .pocketChallengeDown,
                .pocketChallengePass,
                .pocketChallengeCircle,
                .pocketChallengeClear,
                .pocketChallengeView,
                .pocketChallengeEscape,
            ]
            try engine.setInput(allSemanticInputs)
            try engine.runFrame()
            try engine.runFrame()
            let allInputMemory = try engine.captureMemory(.internalRAM)
            pcv2InputRowsAll = Array(allInputMemory[0x3FF0...0x3FF2])

            try engine.setInput(.pocketChallengeLeft)
            try engine.runFrame()
            try engine.runFrame()
            let leftInputMemory = try engine.captureMemory(.internalRAM)
            pcv2InputRowsLeft = Array(leftInputMemory[0x3FF0...0x3FF2])
            pcv2InputContractExact = pcv2InputRowsAll == [0x0F, 0x0F, 0x0E]
                && pcv2InputRowsLeft == [0x02, 0x02, 0x03]

            guard flash.indices.contains(0x10480) else {
                throw ProbeError(message: "The PCV2 fixture is missing its flash round-trip sentinel.")
            }
            var stagedFlash = flash
            stagedFlash[0x10480] &= 0xFE
            guard stagedFlash[0x10480] != flash[0x10480] else {
                throw ProbeError(message: "The PCV2 fixture flash sentinel cannot record a 1-to-0 change.")
            }

            try engine.setInput([])
            try engine.unload()
            activeHardwareModelClearedAfterUnload = engine.activeHardwareModel == nil
            try engine.stagePersistence(
                EnginePersistence(regions: [.cartridgeFlash: stagedFlash])
            )
            _ = try engine.load(rom: rom)
            guard engine.activeHardwareModel == .pocketChallengeV2 else {
                throw ProbeError(message: "The staged-flash reload did not select Pocket Challenge V2.")
            }
            try engine.setInput([])
            try engine.runFrame()
            let freshFrame = try engine.videoFrame()
            let freshRGB = try contentRGB(freshFrame)
            let freshAudio = try engine.audioBatch()
            freshBootFirstVideoExact = firstFrame.map {
                $0.number == freshFrame.number && firstRGB == freshRGB
            } ?? false
            freshBootFirstAudioExact = firstAudio.map {
                $0.channels == freshAudio.channels
                    && $0.sampleRate == freshAudio.sampleRate
                    && $0.interleavedSamples == freshAudio.interleavedSamples
            } ?? false
            persistence = try engine.capturePersistence()
            cartridgeFlashRoundTripExact = persistence.regions[.cartridgeFlash] == stagedFlash
        }

        let report = ProbeReport(
            schema: "swan-song-video-probe-v7",
            romName: romURL.lastPathComponent,
            system: systemTitle(activeHardwareModel ?? configuredSystem),
            openIPLIdentifier: WonderSwanOpenIPL.identifier,
            rtcMode: "deterministic",
            rtcSeedUnixSeconds: deterministicRTCSeed,
            footerChecksumValid: metadata.checksumIsValid,
            footerValid: metadata.footerIsValid,
            compactLayout: metadata.usesCompactLayout,
            backend: engine.backendName,
            configuredHardwareModel: options.hardwareModel.rawValue,
            activeHardwareModel: activeHardwareModel?.rawValue,
            activeHardwareModelClearedAfterUnload: activeHardwareModelClearedAfterUnload,
            pocketChallengeV2CapabilityAdvertised: engine.capabilities.contains(.pocketChallengeV2),
            framesRun: options.frameCount,
            startupWarmupFrames: warmupFrameCount,
            postStartupObservationFrames: options.frameCount - warmupFrameCount,
            finalFrame: finalFrame.number,
            contentWidth: dimensions.width,
            contentHeight: dimensions.height,
            firstNonUniformFrame: firstNonUniformFrame,
            distinctContentFrames: distinctHashes.count,
            longestUniformRun: longestUniformRun,
            finalContentFNV1A64: FrameDifferential.fnv1a64(finalRGB),
            videoActivityDetected: activityDetected,
            startupFirstNonUniformFrame: startupFirstNonUniformFrame,
            startupDistinctContentFrames: startupDistinctHashes.count,
            startupVideoActivityDetected: startupActivityDetected,
            startupAudioFramesProduced: startupAudioFramesProduced,
            startupNonzeroAudioSamples: startupNonzeroAudioSamples,
            postStartupFirstNonUniformFrame: postStartupFirstNonUniformFrame,
            postStartupDistinctContentFrames: postStartupDistinctHashes.count,
            postStartupVideoActivityDetected: postStartupActivityDetected,
            postStartupAudioFramesProduced: postStartupAudioFramesProduced,
            postStartupNonzeroAudioSamples: postStartupNonzeroAudioSamples,
            audioFramesProduced: audioFramesProduced,
            nonzeroAudioSamples: nonzeroAudioSamples,
            audioChannels: audioChannels,
            audioSampleRate: audioSampleRate,
            stateByteCount: state.count,
            stateReplayFrame: actualReplayFrame.number,
            stateReplayVideoFNV1A64: FrameDifferential.fnv1a64(actualReplayRGB),
            stateReplayAudioFrames: actualReplayAudio.frameCount,
            firstReplayFrameExact: firstReplayFrameExact,
            settledStateReplayFrame: actualSettledReplayFrame.number,
            settledStateReplayVideoFNV1A64: FrameDifferential.fnv1a64(
                actualSettledReplayRGB
            ),
            settledStateReplayAudioFrames: actualSettledReplayAudio.frameCount,
            settledReplayFrameExact: settledReplayFrameExact,
            persistenceKinds: persistenceKinds,
            cartridgeFlashByteCount: cartridgeFlashByteCount,
            cartridgeFlashMatchesROM: cartridgeFlashMatchesROM,
            cartridgeFlashRoundTripExact: cartridgeFlashRoundTripExact,
            consoleEEPROMAbsent: consoleEEPROMAbsent,
            pocketChallengeV2InternalRAMByteCount: pcv2InternalRAMByteCount,
            pocketChallengeV2KARNAKResult: pcv2KARNAKResult,
            pocketChallengeV2KARNAKExact: pcv2KARNAKExact,
            pocketChallengeV2InputRowsAll: pcv2InputRowsAll,
            pocketChallengeV2InputRowsLeft: pcv2InputRowsLeft,
            pocketChallengeV2InputContractExact: pcv2InputContractExact,
            freshBootFirstVideoExact: freshBootFirstVideoExact,
            freshBootFirstAudioExact: freshBootFirstAudioExact,
            inputExercise: inputExercise
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reportData = try encoder.encode(report)
        if let reportURL = options.report {
            try reportData.write(to: reportURL, options: .atomic)
        }
        if let captureURL = options.capture {
            try ppmData(
                rgb: finalRGB,
                width: dimensions.width,
                height: dimensions.height
            ).write(to: captureURL, options: .atomic)
        }
        FileHandle.standardOutput.write(reportData)
        FileHandle.standardOutput.write(Data("\n".utf8))

        if options.requireVideoActivity, !postStartupActivityDetected {
            throw ProbeError(
                message: "The engine ran \(options.frameCount) frames, but the raster did not show meaningful video activity during the \(options.frameCount - warmupFrameCount)-frame post-startup observation window."
            )
        }
        if options.requireStateReplayExact, !firstReplayFrameExact {
            throw ProbeError(
                message: "The first video/audio batch after state restore was not bit-exact. See the probe report for the replay frame and hashes."
            )
        }
        if options.requireSettledStateReplayExact, !settledReplayFrameExact {
            throw ProbeError(
                message: "The second video/audio batch after the established one-frame restore settle was not bit-exact. See the probe report for hashes."
            )
        }
        if options.requirePocketChallengeV2FixtureContract {
            let karnakCheckName = pcv2KARNAKResult.map {
                String(format: "KARNAK(actual=0x%02X,expected=0xBF)", $0)
            } ?? "KARNAK(actual=missing,expected=0xBF)"
            let contractChecks: [(name: String, passed: Bool)] = [
                ("hardwareModel", activeHardwareModel == .pocketChallengeV2),
                ("hardwareModelClearedAfterUnload", activeHardwareModelClearedAfterUnload == true),
                ("persistenceKinds", persistenceKinds == ["cartridgeFlash"]),
                ("cartridgeFlashByteCount", cartridgeFlashByteCount == rom.count),
                ("cartridgeFlashMatchesROM", cartridgeFlashMatchesROM == true),
                ("cartridgeFlashRoundTrip", cartridgeFlashRoundTripExact == true),
                ("consoleEEPROMAbsent", consoleEEPROMAbsent),
                ("internalRAMByteCount", pcv2InternalRAMByteCount == 16 * 1024),
                (karnakCheckName, pcv2KARNAKExact == true),
                ("inputRows", pcv2InputContractExact == true),
                ("settledReplay", settledReplayFrameExact),
                ("postStartupVideoActivity", postStartupActivityDetected),
                ("postStartupNonzeroAudio", postStartupNonzeroAudioSamples > 0),
                ("freshBootFirstVideo", freshBootFirstVideoExact == true),
                ("freshBootFirstAudio", freshBootFirstAudioExact == true),
            ]
            let mismatches = contractChecks.compactMap { check in
                check.passed ? nil : check.name
            }
            if !mismatches.isEmpty {
                throw ProbeError(
                    message: "The Pocket Challenge V2 fixture contract was not exact: \(mismatches.joined(separator: ", ")). See the probe report for bounded model, input, KARNAK, determinism, and flash evidence."
                )
            }
        }
    }

    private static func contentDimensions(_ frame: EngineVideoFrame) -> (width: Int, height: Int) {
        if frame.isVertical {
            return (min(frame.width, 144), min(frame.height, 224))
        }
        return (min(frame.width, 224), min(frame.height, 144))
    }

    /// Runs a no-input control branch and an input branch from the exact same
    /// captured state. The first restored frame is ignored because the pinned
    /// ares frontend has a documented one-frame presentation settle. Comparing
    /// the remaining branches distinguishes a real input response from an
    /// attract-mode animation without exposing ROM, state, audio, or pixels.
    private static func runInputExercise(
        engine: EngineSession,
        hardwareModel: EngineHardwareModel?
    ) throws -> InputExerciseReport {
        let comparedFrames = 240
        let origin = try engine.captureState()
        var controlVideo: [String] = []
        var controlAudio: [EngineAudioBatch] = []
        controlVideo.reserveCapacity(comparedFrames + 1)
        controlAudio.reserveCapacity(comparedFrames + 1)

        for _ in 0...comparedFrames {
            try engine.setInput([])
            try engine.runFrame()
            controlVideo.append(
                FrameDifferential.fnv1a64(try contentRGB(engine.videoFrame()))
            )
            controlAudio.append(try engine.audioBatch())
        }

        try engine.restoreState(origin)
        try engine.setInput([])
        try engine.runFrame()
        _ = try engine.videoFrame()
        _ = try engine.audioBatch()

        var framesWithInput = 0
        var firstVideoDivergenceOffset: Int?
        var firstAudioDivergenceOffset: Int?
        for offset in 0..<comparedFrames {
            let input = exerciseInput(at: offset, hardwareModel: hardwareModel)
            if !input.isEmpty { framesWithInput += 1 }
            try engine.setInput(input)
            try engine.runFrame()
            let video = FrameDifferential.fnv1a64(
                try contentRGB(engine.videoFrame())
            )
            let audio = try engine.audioBatch()
            let controlIndex = offset + 1
            if firstVideoDivergenceOffset == nil,
               video != controlVideo[controlIndex] {
                firstVideoDivergenceOffset = offset
            }
            let control = controlAudio[controlIndex]
            if firstAudioDivergenceOffset == nil,
               (audio.channels != control.channels
                || audio.sampleRate != control.sampleRate
                || audio.interleavedSamples != control.interleavedSamples) {
                firstAudioDivergenceOffset = offset
            }
        }
        try engine.setInput([])

        return InputExerciseReport(
            plan: hardwareModel == .pocketChallengeV2
                ? "pocket-challenge-controls-v1"
                : "wonderswan-controls-v1",
            comparedFrames: comparedFrames,
            settleFramesIgnored: 1,
            framesWithInput: framesWithInput,
            firstVideoDivergenceOffset: firstVideoDivergenceOffset,
            firstAudioDivergenceOffset: firstAudioDivergenceOffset,
            videoDiverged: firstVideoDivergenceOffset != nil,
            audioDiverged: firstAudioDivergenceOffset != nil
        )
    }

    private static func exerciseInput(
        at offset: Int,
        hardwareModel: EngineHardwareModel?
    ) -> EngineInput {
        let pulseLength = 3
        let phaseLength = 20
        guard offset % phaseLength < pulseLength else { return [] }
        let phase = offset / phaseLength
        let controls: [EngineInput]
        if hardwareModel == .pocketChallengeV2 {
            controls = [
                .pocketChallengeView,
                .pocketChallengeCircle,
                .pocketChallengePass,
                .pocketChallengeUp,
                .pocketChallengeRight,
                .pocketChallengeDown,
                .pocketChallengeLeft,
                .pocketChallengeClear,
                .pocketChallengeEscape,
            ]
        } else {
            controls = [
                .start,
                .a,
                .b,
                .y1,
                .y2,
                .y3,
                .y4,
                .x1,
                .x2,
                .x3,
                .x4,
            ]
        }
        return controls.indices.contains(phase) ? controls[phase] : []
    }

    private static func contentRGB(_ frame: EngineVideoFrame) throws -> Data {
        let dimensions = contentDimensions(frame)
        guard
            dimensions.width > 0,
            dimensions.height > 0,
            frame.strideBytes >= dimensions.width * 4,
            frame.pixels.count >= frame.strideBytes * dimensions.height
        else { throw ProbeError(message: "The engine returned an invalid video frame.") }

        var rgb = Data(capacity: dimensions.width * dimensions.height * 3)
        frame.pixels.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<dimensions.height {
                for x in 0..<dimensions.width {
                    let offset = y * frame.strideBytes + x * 4
                    rgb.append(bytes[offset + 2])
                    rgb.append(bytes[offset + 1])
                    rgb.append(bytes[offset])
                }
            }
        }
        return rgb
    }

    private static func ppmData(rgb: Data, width: Int, height: Int) throws -> Data {
        guard rgb.count == width * height * 3 else {
            throw ProbeError(message: "The captured RGB frame has the wrong size.")
        }
        var result = Data("P6\n\(width) \(height)\n255\n".utf8)
        result.append(rgb)
        return result
    }

    private static func parseOptions() throws -> Options {
        var options = Options()
        var arguments = Array(CommandLine.arguments.dropFirst())
        while let argument = arguments.first {
            arguments.removeFirst()
            switch argument {
            case "--rom":
                options.rom = URL(fileURLWithPath: try takeValue(&arguments, for: argument))
            case "--frames":
                guard let value = Int(try takeValue(&arguments, for: argument)), value > 0 else {
                    throw ProbeError(message: "--frames must be a positive integer.")
                }
                options.frameCount = value
            case "--warmup-frames":
                guard let value = Int(try takeValue(&arguments, for: argument)), value >= 0 else {
                    throw ProbeError(message: "--warmup-frames must be a nonnegative integer.")
                }
                options.warmupFrameCount = value
            case "--report":
                options.report = URL(fileURLWithPath: try takeValue(&arguments, for: argument))
            case "--capture":
                options.capture = URL(fileURLWithPath: try takeValue(&arguments, for: argument))
            case "--hardware-model":
                options.hardwareModel = try hardwareModel(
                    named: takeValue(&arguments, for: argument)
                )
            case "--require-video-activity":
                options.requireVideoActivity = true
            case "--require-state-replay-exact":
                options.requireStateReplayExact = true
            case "--require-settled-state-replay-exact":
                options.requireSettledStateReplayExact = true
            case "--require-pcv2-fixture-contract":
                options.requirePocketChallengeV2FixtureContract = true
            case "--exercise-inputs":
                options.exerciseInputs = true
            case "--help", "-h":
                print(usage)
                exit(0)
            default:
                throw ProbeError(message: "Unknown option \(argument).\n\n\(usage)")
            }
        }
        return options
    }

    private static func hardwareModel(named name: String) throws -> EngineHardwareModel {
        switch name.lowercased() {
        case "automatic": return .automatic
        case "wonderswan", "wonder-swan": return .wonderSwan
        case "wonderswancolor", "wonderswan-color", "wonder-swan-color":
            return .wonderSwanColor
        case "swancrystal", "swan-crystal": return .swanCrystal
        case "pocketchallengev2", "pocket-challenge-v2", "pcv2":
            return .pocketChallengeV2
        default:
            throw ProbeError(
                message: "Unknown hardware model \(name). Use automatic, wonderswan, wonderswan-color, swan-crystal, or pocket-challenge-v2."
            )
        }
    }

    private static func systemTitle(_ model: EngineHardwareModel) -> String {
        switch model {
        case .automatic: "Automatic"
        case .wonderSwan: "WonderSwan"
        case .wonderSwanColor: "WonderSwan Color"
        case .swanCrystal: "SwanCrystal"
        case .pocketChallengeV2: "Pocket Challenge V2"
        }
    }

    private static func takeValue(_ arguments: inout [String], for option: String) throws -> String {
        guard !arguments.isEmpty else {
            throw ProbeError(message: "\(option) requires a value.")
        }
        return arguments.removeFirst()
    }

    private static let usage = """
    Usage: SwanSongProbe --rom FILE [options]
      --frames N                Run N frames (default 600)
      --warmup-frames N         Treat the first N frames as startup warmup
                                (default min(120, --frames minus 1))
      --report FILE             Write a deterministic JSON activity report
      --capture FILE.ppm        Write the final native game raster as PPM
      --hardware-model MODEL    Select automatic, wonderswan, wonderswan-color,
                                swan-crystal, or pocket-challenge-v2
      --require-video-activity  Fail unless the raster becomes non-uniform and changes
                                after the startup warmup window
      --require-state-replay-exact
                                Fail unless the first restored video/audio batch is bit-exact
      --require-settled-state-replay-exact
                                Fail unless the second restored batch is bit-exact after
                                the established one-frame ares frontend settle
      --require-pcv2-fixture-contract
                                Require the clean-room PCV2 model, keypad, KARNAK,
                                deterministic restart, and flash round-trip contract
      --exercise-inputs         Compare a deterministic Start/A/B/X/Y input branch
                                with a no-input control branch from the same state
    """
}
