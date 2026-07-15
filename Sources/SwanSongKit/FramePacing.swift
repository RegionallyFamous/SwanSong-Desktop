import Foundation

/// Separates an ordinary late producer callback from a transport discontinuity.
///
/// The steady-state queue remains deliberately small. Recovery is armed only
/// after playback has primed, the producer has been absent for at least the
/// whole target-buffer horizon, and the renderer has actually exhausted that
/// queue. At that point continuing the old sample timeline only turns one host
/// scheduling gap into persistent drift. The player instead starts a new
/// timeline epoch and briefly re-primes before resuming.
public struct AudioTransportDiscontinuityPolicy: Sendable {
    public var minimumHostGapSeconds: Double
    public var queueDepletionToleranceSeconds: Double
    public var reprimeBufferedFrames: Double

    public init(
        minimumHostGapSeconds: Double = 0.050,
        queueDepletionToleranceSeconds: Double = 0.000_1,
        reprimeBufferedFrames: Double = 3
    ) {
        self.minimumHostGapSeconds = minimumHostGapSeconds
        self.queueDepletionToleranceSeconds = queueDepletionToleranceSeconds
        self.reprimeBufferedFrames = reprimeBufferedFrames
    }

    public func recoveryThresholdSeconds(
        nominalBatchSeconds: Double,
        targetBufferedFrames: Double
    ) -> Double {
        max(
            minimumHostGapSeconds,
            max(0, nominalBatchSeconds) * max(1, targetBufferedFrames)
        )
    }

    public func shouldRecover(
        hostGapSeconds: Double,
        queuedAudioSeconds: Double,
        nominalBatchSeconds: Double,
        targetBufferedFrames: Double,
        transportWasPrimed: Bool
    ) -> Bool {
        guard transportWasPrimed,
              hostGapSeconds.isFinite,
              queuedAudioSeconds.isFinite,
              nominalBatchSeconds.isFinite,
              hostGapSeconds >= recoveryThresholdSeconds(
                nominalBatchSeconds: nominalBatchSeconds,
                targetBufferedFrames: targetBufferedFrames
              ) else { return false }

        return hostGapSeconds
            > max(0, queuedAudioSeconds) + queueDepletionToleranceSeconds
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
        // Four audio batches are about 53 ms at the native rate. Engine work
        // consumes part of that cushion before the next pacing sleep, leaving
        // enough margin for ordinary macOS scheduling jitter while remaining
        // far below AudioOutput's 180 ms hard queue bound.
        targetBufferedFrames: Double = 4,
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
        queuedAudioSeconds: Double,
        fastForwarding: Bool
    ) -> Double {
        guard !fastForwarding else { return 0 }
        let nominal = producedAudioFrames > 0 && sampleRate > 0
            ? Double(producedAudioFrames) / Double(sampleRate)
            : 1 / fallbackFrameRate
        let target = nominal * targetBufferedFrames
        let correction = (queuedAudioSeconds - target) * correctionStrength
        return min(nominal * 2, max(0, nominal + correction))
    }
}
