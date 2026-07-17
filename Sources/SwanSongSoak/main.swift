import Darwin
import Foundation
import SwanSongKit

private enum SinkClockMode: String {
    case wallClock = "wall-clock"
    case mediaTime = "media-time"
}

private struct Options {
    var rom: URL?
    var fixtureID = "unspecified-open-fixture"
    var requestedDurationMilliseconds = 1_800_000
    var stallThresholdMilliseconds = 250
    var maximumDriftMilliseconds = 2.0
    var injectedHostGapMilliseconds: Int?
    var injectedHostGapAfterFrames = 120
    var discontinuityRecoveryEnabled = true
    var sinkClockMode = SinkClockMode.wallClock
    var report: URL?
}

private struct SoakReport: Codable {
    let schema: String
    let status: String
    let scope: String
    let fixtureID: String
    let backend: String
    let engineBuildID: String
    let openIPLIdentifier: String
    let rtcMode: String
    let rtcSeedUnixSeconds: UInt64
    let sinkClockMode: String
    let durationMode: String
    let requestedDurationMilliseconds: Int
    let elapsedMilliseconds: Int
    let durationCompleted: Bool
    let video: VideoReport
    let audio: AudioReport
    let pacing: PacingReport
    let thresholds: ThresholdReport
    let issues: [String]
}

private struct VideoReport: Codable {
    let framesProduced: Int
    let firstFrameNumber: UInt64?
    let finalFrameNumber: UInt64?
    let invalidFrames: Int
    let nonIncreasingFrames: Int
    let droppedFrameNumbers: UInt64
    let temporalStalls: Int
    let maximumFrameGapMilliseconds: Int
    let p99FrameGapMilliseconds: Int
}

private struct AudioReport: Codable {
    let sink: String
    let queuePrimed: Bool
    let batchesProduced: Int
    let framesProduced: Int
    let channels: Int
    let sampleRate: Int
    let invalidBatches: Int
    let formatChanges: Int
    let underrunEpisodes: Int
    let recoveredDiscontinuities: Int
    let totalRecoveredStarvationMilliseconds: Int
    let maximumRecoveredHostGapMilliseconds: Int
    let recoveryInProgress: Bool
    let droppedBatches: Int
    let totalStarvedMilliseconds: Int
    let finalQueueMilliseconds: Int
    let maximumQueueMilliseconds: Int
    let maximumAbsoluteTransportDriftMilliseconds: Double
}

private struct PacingReport: Codable {
    let policy: String
    let targetBufferedFrames: Double
    let discontinuityRecoveryEnabled: Bool
    let discontinuityHorizonFrames: Double
    let discontinuityThresholdMilliseconds: Int
    let recoveryReprimeFrames: Double
    let injectedHostGapMilliseconds: Int?
    let averageVideoRateMilliHz: Int
    let maximumEngineWorkMilliseconds: Int
    let maximumRequestedSleepMilliseconds: Int
}

private struct ThresholdReport: Codable {
    let maximumUnderrunEpisodes: Int
    let maximumRecoveredDiscontinuities: Int
    let maximumDroppedAudioBatches: Int
    let maximumTemporalStalls: Int
    let stallThresholdMilliseconds: Int
    let maximumAbsoluteTransportDriftMilliseconds: Double
    let maximumAudioQueueMilliseconds: Int
    let minimumAverageVideoRateMilliHz: Int
    let maximumAverageVideoRateMilliHz: Int
}

private struct SoakError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A real-time model of the bounded queue used by AudioOutput. This sink does
/// not touch Core Audio: that distinction is important because this gate can
/// prove that live emulation and the pacing policy keep a 48 kHz stereo stream
/// fed, but cannot prove a particular Mac, output device, or driver is clean.
private struct VirtualRealtimeAudioSink {
    private(set) var queueSeconds = 0.0
    private(set) var maximumQueueSeconds = 0.0
    private(set) var totalScheduledSeconds = 0.0
    private(set) var totalStarvedSeconds = 0.0
    private(set) var underrunEpisodes = 0
    private(set) var recoveredDiscontinuities = 0
    private(set) var totalRecoveredStarvationSeconds = 0.0
    private(set) var maximumRecoveredHostGapSeconds = 0.0
    private(set) var droppedBatches = 0
    private(set) var maximumAbsoluteTransportDriftSeconds = 0.0

    private var transportStartedAt: TimeInterval?
    private var epochScheduledSeconds = 0.0
    private var lastUpdate: TimeInterval?
    private var lastNominalBatchSeconds = 0.0
    private(set) var isPrimed = false
    private(set) var hasEverPrimed = false
    private(set) var isRebuffering = true
    private let pacingPolicy: FramePacingPolicy
    private let discontinuityRecoveryEnabled: Bool
    private let maximumQueuedSeconds = 0.18
    private let starvationToleranceSeconds = 0.000_1
    private let primingToleranceSeconds = 0.002

    init(
        pacingPolicy: FramePacingPolicy,
        discontinuityRecoveryEnabled: Bool
    ) {
        self.pacingPolicy = pacingPolicy
        self.discontinuityRecoveryEnabled = discontinuityRecoveryEnabled
    }

    /// A stopped transport is not consuming its scheduled buffers. Feeding a
    /// zero pacing value fills the bounded re-prime cushion immediately, just
    /// like AudioOutput.pacingQueuedSeconds.
    var pacingQueueSeconds: Double { isRebuffering ? 0 : queueSeconds }

    mutating func enqueue(
        frameCount: Int,
        sampleRate: Int,
        now: TimeInterval
    ) {
        guard frameCount > 0, sampleRate > 0 else { return }
        let duration = Double(frameCount) / Double(sampleRate)
        lastNominalBatchSeconds = duration
        advance(to: now, nominalBatchSeconds: duration)

        if lastUpdate == nil { lastUpdate = now }
        if queueSeconds >= maximumQueuedSeconds {
            droppedBatches += 1
            observeDrift(at: now)
            return
        }

        queueSeconds += duration
        totalScheduledSeconds += duration
        epochScheduledSeconds += duration
        maximumQueueSeconds = max(maximumQueueSeconds, queueSeconds)
        let reprimeTarget = pacingPolicy.discontinuity.reprimeTargetSeconds(
            nominalBatchSeconds: duration
        )
        if isRebuffering,
           queueSeconds + primingToleranceSeconds >= reprimeTarget {
            isRebuffering = false
            isPrimed = true
            hasEverPrimed = true
            transportStartedAt = now
        }
        observeDrift(at: now)
    }

    mutating func finish(at now: TimeInterval) {
        advance(to: now, nominalBatchSeconds: lastNominalBatchSeconds)
        observeDrift(at: now)
    }

    private mutating func advance(
        to now: TimeInterval,
        nominalBatchSeconds: Double
    ) {
        guard let lastUpdate else { return }
        let elapsed = max(0, now - lastUpdate)
        self.lastUpdate = now
        // AudioOutput stops AVAudioPlayerNode while it fills the initial or
        // recovery cushion. The virtual sink must not drain buffers that the
        // corresponding real transport is not rendering.
        guard elapsed > 0, !isRebuffering else { return }

        let queuedBeforeAdvance = queueSeconds
        if elapsed > queuedBeforeAdvance {
            let starved = elapsed - queuedBeforeAdvance
            if isPrimed, starved > starvationToleranceSeconds {
                if discontinuityRecoveryEnabled,
                   pacingPolicy.discontinuity.shouldRecover(
                    hostGapSeconds: elapsed,
                    remainingQueuedAudioSeconds: 0,
                    nominalBatchSeconds: nominalBatchSeconds,
                    transportWasPrimed: true
                   ) {
                    recoveredDiscontinuities += 1
                    totalRecoveredStarvationSeconds += starved
                    maximumRecoveredHostGapSeconds = max(
                        maximumRecoveredHostGapSeconds,
                        elapsed
                    )
                    // AVAudioPlayerNode.stop() resets the player sample timeline.
                    // Mirror that new epoch instead of carrying the old wall-clock
                    // discontinuity forward as permanent transport drift.
                    isPrimed = false
                    isRebuffering = true
                    transportStartedAt = nil
                    epochScheduledSeconds = 0
                } else {
                    underrunEpisodes += 1
                    totalStarvedSeconds += starved
                }
            }
            queueSeconds = 0
        } else {
            queueSeconds -= elapsed
        }
    }

    private mutating func observeDrift(at now: TimeInterval) {
        guard isPrimed, let transportStartedAt else { return }
        // Scheduled media time should equal elapsed transport time plus the
        // queue. Any residual is clock drift or time lost to starvation.
        let drift = epochScheduledSeconds - (now - transportStartedAt) - queueSeconds
        maximumAbsoluteTransportDriftSeconds = max(
            maximumAbsoluteTransportDriftSeconds,
            abs(drift)
        )
    }
}

@main
private struct SwanSongSoak {
    static func main() {
        do {
            let options = try parseOptions()
            let report = try run(options)
            let data = try encode(report)
            if let reportURL = options.report {
                try FileManager.default.createDirectory(
                    at: reportURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: reportURL, options: .atomic)
            }
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            if report.status != "pass" { exit(1) }
        } catch {
            FileHandle.standardError.write(
                Data("SwanSongSoak: \(error.localizedDescription)\n".utf8)
            )
            exit(2)
        }
    }

    private static func run(_ options: Options) throws -> SoakReport {
        guard let romURL = options.rom else {
            throw SoakError(message: usage)
        }

        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])

        let engine = try EngineSession(rtcMode: .deterministic(seedUnixSeconds: 1))
        guard engine.capabilities.contains(.execution), engine.capabilities.contains(.audio) else {
            throw SoakError(message: "SwanSongSoak requires the live ares execution and audio backend.")
        }
        _ = try engine.load(rom: rom)

        let durationSeconds = Double(options.requestedDurationMilliseconds) / 1_000
        let policy = FramePacingPolicy()
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + durationSeconds
        var sink = VirtualRealtimeAudioSink(
            pacingPolicy: policy,
            discontinuityRecoveryEnabled: options.discontinuityRecoveryEnabled
        )
        var framesProduced = 0
        var firstFrameNumber: UInt64?
        var finalFrameNumber: UInt64?
        var invalidFrames = 0
        var nonIncreasingFrames = 0
        var droppedFrameNumbers: UInt64 = 0
        var temporalStalls = 0
        var frameGaps: [TimeInterval] = []
        var previousFrameAt: TimeInterval?
        var batchesProduced = 0
        var audioFramesProduced = 0
        var audioChannels = 0
        var audioSampleRate = 0
        var invalidAudioBatches = 0
        var audioFormatChanges = 0
        var maximumEngineWork = 0.0
        var maximumRequestedSleep = 0.0
        var didInjectHostGap = false
        var mediaClock = 0.0
        var mediaTransportStartedAt: TimeInterval?
        var mediaTransportStartedAtMediaTime = 0.0

        while ProcessInfo.processInfo.systemUptime < deadline {
            if !didInjectHostGap,
               let injectedGap = options.injectedHostGapMilliseconds,
               framesProduced >= options.injectedHostGapAfterFrames {
                didInjectHostGap = true
                Thread.sleep(forTimeInterval: Double(injectedGap) / 1_000)
            }
            let workStartedAt = ProcessInfo.processInfo.systemUptime
            try engine.setInput([])
            try engine.runFrame()
            let frame = try engine.videoFrame()
            let audio = try engine.audioBatch()
            let frameArrivedAt = ProcessInfo.processInfo.systemUptime
            maximumEngineWork = max(maximumEngineWork, frameArrivedAt - workStartedAt)

            if let previousFrameAt {
                let gap = max(0, frameArrivedAt - previousFrameAt)
                frameGaps.append(gap)
                if gap * 1_000 > Double(options.stallThresholdMilliseconds) {
                    temporalStalls += 1
                }
            }
            previousFrameAt = frameArrivedAt

            if frame.width <= 0
                || frame.height <= 0
                || frame.strideBytes < frame.width * 4
                || frame.pixels.count < frame.strideBytes * frame.height
            {
                invalidFrames += 1
            }
            if let finalFrameNumber {
                if frame.number <= finalFrameNumber {
                    nonIncreasingFrames += 1
                } else if frame.number > finalFrameNumber + 1 {
                    droppedFrameNumbers += frame.number - finalFrameNumber - 1
                }
            }
            if firstFrameNumber == nil { firstFrameNumber = frame.number }
            finalFrameNumber = frame.number
            framesProduced += 1

            let validAudio = audio.frameCount > 0
                && audio.channels == 2
                && audio.sampleRate == 48_000
                && audio.interleavedSamples.count == audio.frameCount * audio.channels
            if !validAudio { invalidAudioBatches += 1 }
            if audioChannels != 0,
               (audioChannels != audio.channels || audioSampleRate != audio.sampleRate) {
                audioFormatChanges += 1
            }
            audioChannels = audio.channels
            audioSampleRate = audio.sampleRate
            batchesProduced += 1
            audioFramesProduced += audio.frameCount
            let sinkNow: TimeInterval
            switch options.sinkClockMode {
            case .wallClock:
                sinkNow = frameArrivedAt
            case .mediaTime:
                if audio.frameCount > 0, audio.sampleRate > 0 {
                    mediaClock += Double(audio.frameCount) / Double(audio.sampleRate)
                }
                sinkNow = mediaClock
            }
            sink.enqueue(
                frameCount: audio.frameCount,
                sampleRate: audio.sampleRate,
                now: sinkNow
            )
            if options.sinkClockMode == .mediaTime,
               !sink.isRebuffering,
               mediaTransportStartedAt == nil {
                mediaTransportStartedAt = frameArrivedAt
                mediaTransportStartedAtMediaTime = mediaClock
            }

            let delay = policy.delaySeconds(
                producedAudioFrames: audio.frameCount,
                sampleRate: audio.sampleRate,
                queuedAudioSeconds: sink.pacingQueueSeconds,
                fastForwarding: false
            )
            let clockAdjustedDelay: TimeInterval
            if options.sinkClockMode == .mediaTime,
               let mediaTransportStartedAt {
                let target = mediaTransportStartedAt
                    + (mediaClock - mediaTransportStartedAtMediaTime)
                clockAdjustedDelay = max(
                    0,
                    target - ProcessInfo.processInfo.systemUptime
                )
            } else {
                clockAdjustedDelay = delay
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            let boundedDelay = min(clockAdjustedDelay, max(0, remaining))
            maximumRequestedSleep = max(maximumRequestedSleep, boundedDelay)
            if boundedDelay > 0 { Thread.sleep(forTimeInterval: boundedDelay) }
        }

        let finishedAt = ProcessInfo.processInfo.systemUptime
        sink.finish(at: options.sinkClockMode == .wallClock ? finishedAt : mediaClock)
        if let previousFrameAt {
            let finalGap = max(0, finishedAt - previousFrameAt)
            frameGaps.append(finalGap)
            if finalGap * 1_000 > Double(options.stallThresholdMilliseconds) {
                temporalStalls += 1
            }
        }
        let elapsed = max(0, finishedAt - startedAt)
        let elapsedMilliseconds = Int((elapsed * 1_000).rounded())
        let durationCompleted = elapsedMilliseconds >= options.requestedDurationMilliseconds
        let sortedGaps = frameGaps.sorted()
        let p99Gap = percentile(sortedGaps, percentile: 0.99)
        let maxGap = sortedGaps.last ?? 0
        let rateMilliHz = elapsed > 0
            ? Int((Double(framesProduced) / elapsed * 1_000).rounded())
            : 0
        let driftMilliseconds = sink.maximumAbsoluteTransportDriftSeconds * 1_000
        let maximumRecoveredDiscontinuities = max(
            1,
            Int(ceil(durationSeconds / 60))
        )

        var issues: [String] = []
        if engine.backendName != "ares" { issues.append("live ares backend was not used") }
        if !engine.buildID.hasPrefix("ares-")
            || !engine.buildID.hasSuffix("-swan-abi6") {
            issues.append("live engine build identity was not ABI 6")
        }
        if !durationCompleted { issues.append("requested wall-clock duration did not complete") }
        if framesProduced == 0 { issues.append("no video frames were produced") }
        if invalidFrames > 0 { issues.append("invalid video frames were produced") }
        if nonIncreasingFrames > 0 { issues.append("video frame numbers stopped or moved backward") }
        if droppedFrameNumbers > 0 { issues.append("video frame numbers skipped") }
        if temporalStalls > 0 { issues.append("video frame delivery exceeded the stall threshold") }
        if batchesProduced == 0 { issues.append("no audio batches were produced") }
        if invalidAudioBatches > 0 { issues.append("invalid or non-48-kHz-stereo audio batches were produced") }
        if audioFormatChanges > 0 { issues.append("audio format changed during the soak") }
        if !sink.hasEverPrimed { issues.append("the virtual real-time audio queue never primed") }
        if sink.hasEverPrimed, sink.isRebuffering {
            issues.append("the virtual real-time audio queue did not finish re-priming")
        }
        if sink.underrunEpisodes > 0 { issues.append("the virtual real-time audio queue underrun") }
        if sink.recoveredDiscontinuities > maximumRecoveredDiscontinuities {
            issues.append("audio transport discontinuity recovery exceeded its rarity budget")
        }
        if sink.droppedBatches > 0 { issues.append("the virtual real-time audio queue dropped batches") }
        if driftMilliseconds > options.maximumDriftMilliseconds {
            issues.append("audio transport drift exceeded the configured threshold")
        }
        if sink.maximumQueueSeconds > 0.18 + 0.000_001 {
            issues.append("audio queue depth exceeded the player queue bound")
        }
        if !(70_000...82_000).contains(rateMilliHz) {
            issues.append("average video delivery was outside the native-rate tolerance")
        }

        return SoakReport(
            schema: "swan-song-av-soak-v4",
            status: issues.isEmpty ? "pass" : "fail",
            scope: options.sinkClockMode == .wallClock
                ? "Checked-in open fixture using SwanSong Open IPL; live ares execution and virtual wall-clock audio sink only; no commercial-game, Core Audio device, or original-hardware compatibility evidence."
                : "Checked-in open fixture using SwanSong Open IPL; live ares execution and scheduler-neutral produced-media-time virtual audio sink for shared-runner integrity; no commercial-game, Core Audio device, wall-clock realtime, or original-hardware compatibility evidence.",
            fixtureID: options.fixtureID,
            backend: engine.backendName,
            engineBuildID: engine.buildID,
            openIPLIdentifier: WonderSwanOpenIPL.identifier,
            rtcMode: "deterministic",
            rtcSeedUnixSeconds: 1,
            sinkClockMode: options.sinkClockMode.rawValue,
            durationMode: options.requestedDurationMilliseconds == 1_800_000
                ? "release-30-minute"
                : "duration-override",
            requestedDurationMilliseconds: options.requestedDurationMilliseconds,
            elapsedMilliseconds: elapsedMilliseconds,
            durationCompleted: durationCompleted,
            video: VideoReport(
                framesProduced: framesProduced,
                firstFrameNumber: firstFrameNumber,
                finalFrameNumber: finalFrameNumber,
                invalidFrames: invalidFrames,
                nonIncreasingFrames: nonIncreasingFrames,
                droppedFrameNumbers: droppedFrameNumbers,
                temporalStalls: temporalStalls,
                maximumFrameGapMilliseconds: milliseconds(maxGap),
                p99FrameGapMilliseconds: milliseconds(p99Gap)
            ),
            audio: AudioReport(
                sink: options.sinkClockMode == .wallClock
                    ? "virtual-realtime-48khz-stereo"
                    : "virtual-media-clock-48khz-stereo",
                queuePrimed: sink.hasEverPrimed,
                batchesProduced: batchesProduced,
                framesProduced: audioFramesProduced,
                channels: audioChannels,
                sampleRate: audioSampleRate,
                invalidBatches: invalidAudioBatches,
                formatChanges: audioFormatChanges,
                underrunEpisodes: sink.underrunEpisodes,
                recoveredDiscontinuities: sink.recoveredDiscontinuities,
                totalRecoveredStarvationMilliseconds: milliseconds(
                    sink.totalRecoveredStarvationSeconds
                ),
                maximumRecoveredHostGapMilliseconds: milliseconds(
                    sink.maximumRecoveredHostGapSeconds
                ),
                recoveryInProgress: sink.hasEverPrimed && sink.isRebuffering,
                droppedBatches: sink.droppedBatches,
                totalStarvedMilliseconds: milliseconds(sink.totalStarvedSeconds),
                finalQueueMilliseconds: milliseconds(sink.queueSeconds),
                maximumQueueMilliseconds: milliseconds(sink.maximumQueueSeconds),
                maximumAbsoluteTransportDriftMilliseconds: roundedMilliseconds(driftMilliseconds)
            ),
            pacing: PacingReport(
                policy: "audio-duration with bounded queue correction",
                targetBufferedFrames: policy.targetBufferedFrames,
                discontinuityRecoveryEnabled: options.discontinuityRecoveryEnabled,
                discontinuityHorizonFrames: policy.discontinuity.recoveryHorizonFrames,
                discontinuityThresholdMilliseconds: milliseconds(
                    policy.discontinuity.recoveryThresholdSeconds(
                        nominalBatchSeconds: audioSampleRate > 0
                            ? Double(audioFramesProduced) / Double(max(1, batchesProduced))
                                / Double(audioSampleRate)
                            : 0
                    )
                ),
                recoveryReprimeFrames: policy.discontinuity.reprimeBufferedFrames,
                injectedHostGapMilliseconds: options.injectedHostGapMilliseconds,
                averageVideoRateMilliHz: rateMilliHz,
                maximumEngineWorkMilliseconds: milliseconds(maximumEngineWork),
                maximumRequestedSleepMilliseconds: milliseconds(maximumRequestedSleep)
            ),
            thresholds: ThresholdReport(
                maximumUnderrunEpisodes: 0,
                maximumRecoveredDiscontinuities: maximumRecoveredDiscontinuities,
                maximumDroppedAudioBatches: 0,
                maximumTemporalStalls: 0,
                stallThresholdMilliseconds: options.stallThresholdMilliseconds,
                maximumAbsoluteTransportDriftMilliseconds: options.maximumDriftMilliseconds,
                maximumAudioQueueMilliseconds: 180,
                minimumAverageVideoRateMilliHz: 70_000,
                maximumAverageVideoRateMilliHz: 82_000
            ),
            issues: issues
        )
    }

    private static func parseOptions() throws -> Options {
        var options = Options()
        var arguments = Array(CommandLine.arguments.dropFirst())
        while let argument = arguments.first {
            arguments.removeFirst()
            switch argument {
            case "--rom":
                options.rom = URL(fileURLWithPath: try takeValue(&arguments, for: argument))
            case "--fixture-id":
                let value = try takeValue(&arguments, for: argument)
                guard !value.isEmpty else { throw SoakError(message: "--fixture-id cannot be empty.") }
                options.fixtureID = value
            case "--duration-ms":
                guard let value = Int(try takeValue(&arguments, for: argument)), value > 0 else {
                    throw SoakError(message: "--duration-ms must be a positive integer.")
                }
                options.requestedDurationMilliseconds = value
            case "--stall-threshold-ms":
                guard let value = Int(try takeValue(&arguments, for: argument)), value > 0 else {
                    throw SoakError(message: "--stall-threshold-ms must be a positive integer.")
                }
                options.stallThresholdMilliseconds = value
            case "--maximum-drift-ms":
                guard let value = Double(try takeValue(&arguments, for: argument)), value >= 0 else {
                    throw SoakError(message: "--maximum-drift-ms must be a nonnegative number.")
                }
                options.maximumDriftMilliseconds = value
            case "--inject-host-gap-ms":
                guard let value = Int(try takeValue(&arguments, for: argument)), value > 0 else {
                    throw SoakError(message: "--inject-host-gap-ms must be a positive integer.")
                }
                options.injectedHostGapMilliseconds = value
            case "--inject-host-gap-after-frames":
                guard let value = Int(try takeValue(&arguments, for: argument)), value > 0 else {
                    throw SoakError(
                        message: "--inject-host-gap-after-frames must be a positive integer."
                    )
                }
                options.injectedHostGapAfterFrames = value
            case "--disable-discontinuity-recovery":
                options.discontinuityRecoveryEnabled = false
            case "--sink-clock":
                let value = try takeValue(&arguments, for: argument)
                guard let mode = SinkClockMode(rawValue: value) else {
                    throw SoakError(message: "--sink-clock must be wall-clock or media-time.")
                }
                options.sinkClockMode = mode
            case "--report":
                options.report = URL(fileURLWithPath: try takeValue(&arguments, for: argument))
            case "--help", "-h":
                print(usage)
                exit(0)
            default:
                throw SoakError(message: "Unknown option \(argument).\n\n\(usage)")
            }
        }
        return options
    }

    private static func takeValue(_ arguments: inout [String], for option: String) throws -> String {
        guard !arguments.isEmpty else {
            throw SoakError(message: "\(option) requires a value.")
        }
        return arguments.removeFirst()
    }

    private static func percentile(_ sorted: [TimeInterval], percentile: Double) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * percentile).rounded(.up)))
        return sorted[index]
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((max(0, seconds) * 1_000).rounded())
    }

    private static func roundedMilliseconds(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }

    private static func encode(_ report: SoakReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    private static let usage = """
    Usage: SwanSongSoak --rom OPEN_FIXTURE [options]
      --fixture-id ID             Source-free fixture label for the report
      --duration-ms N             Exact requested wall duration (default 1800000)
      --stall-threshold-ms N      Fail on a frame gap above N (default 250)
      --maximum-drift-ms N        Fail above N ms transport drift (default 2)
      --inject-host-gap-ms N      Deliberately suspend the producer for N ms
      --inject-host-gap-after-frames N
                                  Injection point (default 120)
      --disable-discontinuity-recovery
                                  Keep the old continuous transport for a control run
      --sink-clock MODE           wall-clock (release gate) or media-time (CI integrity)
      --report FILE               Atomically write sorted-key JSON evidence

    The gate uses a virtual audio sink. Wall-clock mode is the strict release
    gate; media-time mode isolates shared-runner scheduling for CI integrity.
    Neither mode claims Core Audio device, commercial-game, or
    original-hardware compatibility evidence.
    """
}
