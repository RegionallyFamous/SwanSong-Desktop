import Foundation

/// Separates an ordinary late producer callback from a transport discontinuity.
///
/// The steady-state queue remains deliberately small. Recovery is armed only
/// after playback has primed, the producer has been absent for the complete
/// discontinuity horizon, and the renderer has actually exhausted its queue.
/// At that point continuing the old sample timeline only turns one host
/// scheduling gap into persistent drift. The player instead starts a new
/// timeline epoch and re-primes before resuming.
public struct AudioTransportDiscontinuityPolicy: Sendable {
    public var minimumHostGapSeconds: Double
    public var queueDepletionToleranceSeconds: Double
    public var recoveryHorizonFrames: Double
    public var reprimeBufferedFrames: Double

    public init(
        minimumHostGapSeconds: Double = 0.050,
        queueDepletionToleranceSeconds: Double = 0.000_1,
        recoveryHorizonFrames: Double = 4,
        reprimeBufferedFrames: Double = 5
    ) {
        self.minimumHostGapSeconds = minimumHostGapSeconds
        self.queueDepletionToleranceSeconds = queueDepletionToleranceSeconds
        self.recoveryHorizonFrames = recoveryHorizonFrames
        self.reprimeBufferedFrames = reprimeBufferedFrames
    }

    public func recoveryThresholdSeconds(nominalBatchSeconds: Double) -> Double {
        max(
            minimumHostGapSeconds,
            max(0, nominalBatchSeconds) * max(1, recoveryHorizonFrames)
        )
    }

    public func shouldRecover(
        hostGapSeconds: Double,
        remainingQueuedAudioSeconds: Double,
        nominalBatchSeconds: Double,
        transportWasPrimed: Bool
    ) -> Bool {
        guard transportWasPrimed,
              hostGapSeconds.isFinite,
              remainingQueuedAudioSeconds.isFinite,
              nominalBatchSeconds.isFinite,
              hostGapSeconds >= recoveryThresholdSeconds(
                nominalBatchSeconds: nominalBatchSeconds
              ) else { return false }

        // The caller samples the renderer at the end of the host gap. A long
        // producer delay is recoverable only if that sample confirms the
        // renderer queue is empty; a merely late callback with audio remaining
        // must stay on the existing transport epoch.
        return max(0, remainingQueuedAudioSeconds)
            <= queueDepletionToleranceSeconds
    }

    public func reprimeTargetSeconds(nominalBatchSeconds: Double) -> Double {
        max(0, nominalBatchSeconds) * max(1, reprimeBufferedFrames)
    }
}

public struct FramePacingPolicy: Sendable {
    public var fallbackFrameRate: Double
    public var targetBufferedFrames: Double
    public var correctionStrength: Double
    public var discontinuity: AudioTransportDiscontinuityPolicy

    public init(
        fallbackFrameRate: Double = 75.47,
        // Five audio batches are about 66 ms at the native rate. That leaves a
        // complete batch beyond the four-batch discontinuity horizon, even
        // after engine work consumes part of the queue before the next sleep,
        // while remaining far below AudioOutput's 180 ms hard queue bound.
        targetBufferedFrames: Double = 5,
        correctionStrength: Double = 0.35,
        discontinuity: AudioTransportDiscontinuityPolicy = .init()
    ) {
        self.fallbackFrameRate = fallbackFrameRate
        self.targetBufferedFrames = targetBufferedFrames
        self.correctionStrength = correctionStrength
        self.discontinuity = discontinuity
    }

    public func delaySeconds(
        producedAudioFrames: Int,
        sampleRate: Int,
        queuedAudioSeconds: Double?,
        fastForwarding: Bool
    ) -> Double {
        guard !fastForwarding else { return 0 }
        let nominal = producedAudioFrames > 0 && sampleRate > 0
            ? Double(producedAudioFrames) / Double(sampleRate)
            : 1 / fallbackFrameRate
        // When Core Audio is unavailable there is no renderer queue to use as
        // feedback. Preserve the native frame period instead of treating the
        // missing sink as a permanently starved queue and collapsing to an
        // unthrottled loop.
        guard let queuedAudioSeconds, queuedAudioSeconds.isFinite else {
            return nominal
        }
        let target = nominal * targetBufferedFrames
        let correction = (queuedAudioSeconds - target) * correctionStrength
        return min(nominal * 2, max(0, nominal + correction))
    }
}
