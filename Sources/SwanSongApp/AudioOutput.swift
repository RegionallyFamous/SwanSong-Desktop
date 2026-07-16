import AVFAudio
import Foundation
import SwanSongKit

@MainActor
final class AudioOutput {
    struct ScheduleResult {
        let queuedSeconds: Double
        let dropped: Bool
        let recoveredDiscontinuity: Bool
        let isRebuffering: Bool
    }

    private let pacingPolicy: FramePacingPolicy
    private let isHeadless: Bool
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var scheduledFrames: AVAudioFramePosition = 0
    private var suppressScheduling = false
    private var isPaused = false
    private var lastEnqueueUptime: TimeInterval?
    private var transportWasPrimed = false
    private var isRebuffering = false
    private var fadeInNextBuffer = false
    private(set) var isRunning = false
    private(set) var recoveredDiscontinuities = 0

    /// Headless automation explicitly trades realtime pacing for test speed.
    /// Ordinary audio startup failures must never take this path.
    var usesUnthrottledHeadlessMode: Bool { isHeadless }

    /// Queue feedback is meaningful only while Core Audio owns a live sink.
    /// During initial priming or recovery the player is intentionally stopped;
    /// expose a starved pacing queue so the producer fills the resume cushion
    /// without sleeping between batches.
    var pacingQueuedSeconds: Double? {
        isRunning ? (isRebuffering ? 0 : queuedSeconds) : nil
    }

    private let maximumQueuedSeconds = 0.18

    init(pacingPolicy: FramePacingPolicy = .init()) {
        self.pacingPolicy = pacingPolicy
        isHeadless = ProcessInfo.processInfo.environment["SWAN_SONG_HEADLESS"] == "1"
        engine = nil
        player = nil
    }

    func start(sampleRate: Double = 48_000) throws {
        stop()
        guard !isHeadless else { return }
        // AVAudioPlayerNode can abort during construction on managed/no-audio
        // hosts. Delay all CoreAudio component work until playback actually
        // starts so the library and diagnostics remain usable.
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        self.engine = engine
        self.player = player
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw CocoaError(.coderInvalidValue)
        }

        self.format = format
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        scheduledFrames = 0
        suppressScheduling = false
        isPaused = false
        lastEnqueueUptime = nil
        transportWasPrimed = false
        // Do not start an empty renderer. Initial playback follows the same
        // bounded re-prime path as a recovered transport discontinuity.
        isRebuffering = true
        fadeInNextBuffer = true
        recoveredDiscontinuities = 0
        isRunning = true
    }

    @discardableResult
    func enqueue(_ batch: EngineAudioBatch) -> ScheduleResult {
        let now = ProcessInfo.processInfo.systemUptime
        let nominalBatchSeconds = batch.frameCount > 0 && batch.sampleRate > 0
            ? Double(batch.frameCount) / Double(batch.sampleRate)
            : 0
        var before = queuedSeconds
        var recoveredDiscontinuity = false
        if let lastEnqueueUptime,
           !isPaused,
           !suppressScheduling,
           pacingPolicy.discontinuity.shouldRecover(
            hostGapSeconds: max(0, now - lastEnqueueUptime),
            remainingQueuedAudioSeconds: before,
            nominalBatchSeconds: nominalBatchSeconds,
            transportWasPrimed: transportWasPrimed
           ), let player {
            beginDiscontinuityRecovery(player: player)
            before = 0
            recoveredDiscontinuity = true
        }
        lastEnqueueUptime = now

        guard
            isRunning,
            !suppressScheduling,
            batch.channels == 2,
            batch.frameCount > 0,
            before < maximumQueuedSeconds,
            let player,
            let format,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(batch.frameCount)
            ),
            let channels = buffer.floatChannelData
        else {
            return ScheduleResult(
                queuedSeconds: before,
                dropped: isRunning && !suppressScheduling && before >= maximumQueuedSeconds,
                recoveredDiscontinuity: recoveredDiscontinuity,
                isRebuffering: isRebuffering
            )
        }

        buffer.frameLength = AVAudioFrameCount(batch.frameCount)
        let fadeFrameCount = fadeInNextBuffer
            ? min(batch.frameCount, max(1, batch.sampleRate / 200))
            : 0
        for frame in 0..<batch.frameCount {
            let gain = frame < fadeFrameCount
                ? Float(frame) / Float(max(1, fadeFrameCount - 1))
                : 1
            channels[0][frame] = batch.interleavedSamples[frame * 2] * gain
            channels[1][frame] = batch.interleavedSamples[frame * 2 + 1] * gain
        }
        if fadeFrameCount > 0 { fadeInNextBuffer = false }
        player.scheduleBuffer(buffer)
        scheduledFrames += AVAudioFramePosition(batch.frameCount)
        let after = queuedSeconds
        let reprimeTarget = pacingPolicy.discontinuity.reprimeTargetSeconds(
            nominalBatchSeconds: nominalBatchSeconds
        )
        if isRebuffering,
           after + pacingPolicy.discontinuity.queueDepletionToleranceSeconds
            >= reprimeTarget {
            isRebuffering = false
            transportWasPrimed = true
            if !isPaused { player.play() }
        } else if !transportWasPrimed,
                  after + pacingPolicy.discontinuity.queueDepletionToleranceSeconds
                    >= reprimeTarget {
            transportWasPrimed = true
        }
        return ScheduleResult(
            queuedSeconds: after,
            dropped: false,
            recoveredDiscontinuity: recoveredDiscontinuity,
            isRebuffering: isRebuffering
        )
    }

    func stop() {
        guard let engine, let player else {
            self.engine = nil
            self.player = nil
            format = nil
            scheduledFrames = 0
            suppressScheduling = false
            isPaused = false
            lastEnqueueUptime = nil
            transportWasPrimed = false
            isRebuffering = false
            fadeInNextBuffer = false
            recoveredDiscontinuities = 0
            isRunning = false
            return
        }
        if player.engine != nil {
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        engine.stop()
        engine.reset()
        self.engine = nil
        self.player = nil
        format = nil
        scheduledFrames = 0
        suppressScheduling = false
        isPaused = false
        lastEnqueueUptime = nil
        transportWasPrimed = false
        isRebuffering = false
        fadeInNextBuffer = false
        recoveredDiscontinuities = 0
        isRunning = false
    }

    func setPaused(_ paused: Bool) {
        guard isRunning, let player else { return }
        isPaused = paused
        lastEnqueueUptime = paused ? nil : ProcessInfo.processInfo.systemUptime
        if paused {
            player.pause()
        } else if !isRebuffering, !player.isPlaying {
            player.play()
        }
    }

    func setFastForwarding(_ fastForwarding: Bool) {
        guard isRunning, let player, suppressScheduling != fastForwarding else { return }
        suppressScheduling = fastForwarding
        player.stop()
        player.reset()
        scheduledFrames = 0
        lastEnqueueUptime = nil
        transportWasPrimed = false
        // Leaving fast-forward creates a new player timeline. Refill the same
        // startup/recovery cushion before making it audible.
        isRebuffering = !fastForwarding
        fadeInNextBuffer = !fastForwarding
    }

    private func beginDiscontinuityRecovery(player: AVAudioPlayerNode) {
        // AVAudioPlayerNode.stop() clears scheduled buffers and resets its
        // player timeline to sample zero. Keep AVAudioEngine running, refill a
        // short low-latency cushion, then resume this new transport epoch.
        player.stop()
        player.reset()
        scheduledFrames = 0
        transportWasPrimed = false
        isRebuffering = true
        fadeInNextBuffer = true
        recoveredDiscontinuities += 1
    }

    private var queuedSeconds: Double {
        guard let player, let format else { return 0 }
        let rendered: AVAudioFramePosition
        if
            let renderTime = player.lastRenderTime,
            let playerTime = player.playerTime(forNodeTime: renderTime)
        {
            rendered = max(0, playerTime.sampleTime)
        } else {
            rendered = 0
        }
        let queued = max(0, scheduledFrames - rendered)
        return Double(queued) / format.sampleRate
    }
}
