import Foundation

public enum RewindCheckpointError: LocalizedError, Equatable, Sendable {
    case emptyState
    case invalidPreviewFrame
    case payloadByteCountOverflow

    public var errorDescription: String? {
        switch self {
        case .emptyState:
            "A rewind checkpoint cannot contain an empty engine state."
        case .invalidPreviewFrame:
            "A rewind checkpoint requires a complete native preview frame."
        case .payloadByteCountOverflow:
            "The rewind checkpoint is too large to measure safely."
        }
    }
}

/// An exact engine state and the native frame that was visible when it was
/// captured. Rewind checkpoints are intentionally memory-only; persistence and
/// compatibility policy remain the responsibility of `GameStateStore`.
public struct RewindCheckpoint: Identifiable, Equatable, Sendable {
    public var id: UInt64 { frameNumber }
    public var frameNumber: UInt64 { previewFrame.number }

    public let state: Data
    public let previewFrame: EngineVideoFrame

    /// The byte count governed by `RewindBufferConfiguration.maximumByteCount`.
    /// This covers both retained `Data` payloads, not incidental collection
    /// metadata.
    public let payloadByteCount: Int

    public init(state: Data, previewFrame: EngineVideoFrame) throws {
        guard !state.isEmpty else { throw RewindCheckpointError.emptyState }

        let (minimumStride, strideOverflow) = previewFrame.width.multipliedReportingOverflow(by: 4)
        let (minimumPixelCount, pixelCountOverflow) = previewFrame.strideBytes
            .multipliedReportingOverflow(by: previewFrame.height)
        guard
            previewFrame.width > 0,
            previewFrame.height > 0,
            !strideOverflow,
            !pixelCountOverflow,
            previewFrame.strideBytes >= minimumStride,
            minimumPixelCount > 0,
            previewFrame.pixels.count >= minimumPixelCount
        else { throw RewindCheckpointError.invalidPreviewFrame }

        let (payloadByteCount, byteCountOverflow) = state.count
            .addingReportingOverflow(previewFrame.pixels.count)
        guard !byteCountOverflow else {
            throw RewindCheckpointError.payloadByteCountOverflow
        }

        self.state = state
        self.previewFrame = previewFrame
        self.payloadByteCount = payloadByteCount
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state
            && lhs.previewFrame.pixels == rhs.previewFrame.pixels
            && lhs.previewFrame.width == rhs.previewFrame.width
            && lhs.previewFrame.height == rhs.previewFrame.height
            && lhs.previewFrame.strideBytes == rhs.previewFrame.strideBytes
            && lhs.previewFrame.isVertical == rhs.previewFrame.isVertical
            && lhs.previewFrame.number == rhs.previewFrame.number
    }
}

public enum RewindBufferConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidRetentionSeconds
    case invalidFrameRate
    case invalidMaximumByteCount
    case retentionFrameSpanOverflow
    case retentionWindowTooSmall

    public var errorDescription: String? {
        switch self {
        case .invalidRetentionSeconds:
            "Rewind retention must be at least one second."
        case .invalidFrameRate:
            "Rewind frame-rate terms must both be greater than zero."
        case .invalidMaximumByteCount:
            "The rewind byte limit must be greater than zero."
        case .retentionFrameSpanOverflow:
            "The rewind retention window is too large to represent safely."
        case .retentionWindowTooSmall:
            "The rewind retention window must span at least one emulated frame."
        }
    }
}

public struct RewindBufferConfiguration: Equatable, Sendable {
    /// WonderSwan's nominal 3.072 MHz clock divided by 256 cycles and 159 lines.
    public static let wonderSwanFrameRateNumerator: UInt64 = 4_000
    public static let wonderSwanFrameRateDenominator: UInt64 = 53
    public static let defaultRetentionSeconds: UInt64 = 30
    public static let defaultMaximumByteCount = 48 * 1_024 * 1_024

    public static let standard = Self(
        retentionSeconds: defaultRetentionSeconds,
        frameRateNumerator: wonderSwanFrameRateNumerator,
        frameRateDenominator: wonderSwanFrameRateDenominator,
        maximumByteCount: defaultMaximumByteCount,
        maximumFrameSpan: defaultRetentionSeconds
            * wonderSwanFrameRateNumerator
            / wonderSwanFrameRateDenominator
    )

    public let retentionSeconds: UInt64
    public let frameRateNumerator: UInt64
    public let frameRateDenominator: UInt64
    public let maximumByteCount: Int

    /// The largest permitted distance from the newest retained frame to the
    /// oldest one. The floor conversion ensures the buffer never retains more
    /// emulated time than `retentionSeconds`.
    public let maximumFrameSpan: UInt64

    public var nominalFramesPerSecond: Double {
        Double(frameRateNumerator) / Double(frameRateDenominator)
    }

    public init(
        retentionSeconds: UInt64 = Self.defaultRetentionSeconds,
        frameRateNumerator: UInt64 = Self.wonderSwanFrameRateNumerator,
        frameRateDenominator: UInt64 = Self.wonderSwanFrameRateDenominator,
        maximumByteCount: Int = Self.defaultMaximumByteCount
    ) throws {
        guard retentionSeconds > 0 else {
            throw RewindBufferConfigurationError.invalidRetentionSeconds
        }
        guard frameRateNumerator > 0, frameRateDenominator > 0 else {
            throw RewindBufferConfigurationError.invalidFrameRate
        }
        guard maximumByteCount > 0 else {
            throw RewindBufferConfigurationError.invalidMaximumByteCount
        }
        let (scaledFrames, overflow) = retentionSeconds
            .multipliedReportingOverflow(by: frameRateNumerator)
        guard !overflow else {
            throw RewindBufferConfigurationError.retentionFrameSpanOverflow
        }
        let maximumFrameSpan = scaledFrames / frameRateDenominator
        guard maximumFrameSpan > 0 else {
            throw RewindBufferConfigurationError.retentionWindowTooSmall
        }

        self.init(
            retentionSeconds: retentionSeconds,
            frameRateNumerator: frameRateNumerator,
            frameRateDenominator: frameRateDenominator,
            maximumByteCount: maximumByteCount,
            maximumFrameSpan: maximumFrameSpan
        )
    }

    private init(
        retentionSeconds: UInt64,
        frameRateNumerator: UInt64,
        frameRateDenominator: UInt64,
        maximumByteCount: Int,
        maximumFrameSpan: UInt64
    ) {
        self.retentionSeconds = retentionSeconds
        self.frameRateNumerator = frameRateNumerator
        self.frameRateDenominator = frameRateDenominator
        self.maximumByteCount = maximumByteCount
        self.maximumFrameSpan = maximumFrameSpan
    }
}

public enum RewindBufferError: LocalizedError, Equatable, Sendable {
    case checkpointExceedsByteLimit(actual: Int, maximum: Int)
    case outOfOrderFrame(attempted: UInt64, latest: UInt64)

    public var errorDescription: String? {
        switch self {
        case let .checkpointExceedsByteLimit(actual, maximum):
            "The rewind checkpoint uses \(actual) bytes, exceeding the \(maximum)-byte limit."
        case let .outOfOrderFrame(attempted, latest):
            "Frame \(attempted) cannot be appended after frame \(latest). Truncate the rewind branch first."
        }
    }
}

public struct RewindBufferAppendResult: Equatable, Sendable {
    public let replacedExistingCheckpoint: Bool
    public let evictedCheckpointCount: Int
    public let checkpointWasRetained: Bool

    public init(
        replacedExistingCheckpoint: Bool,
        evictedCheckpointCount: Int,
        checkpointWasRetained: Bool
    ) {
        self.replacedExistingCheckpoint = replacedExistingCheckpoint
        self.evictedCheckpointCount = evictedCheckpointCount
        self.checkpointWasRetained = checkpointWasRetained
    }
}

/// A chronologically ordered, memory-only rewind history.
///
/// Invariants after every successful mutation:
/// - frame numbers are unique and strictly increasing;
/// - `totalPayloadByteCount` equals the state-plus-preview bytes retained;
/// - total payload bytes never exceed the configured hard cap;
/// - the oldest and newest frames never span more than the retention window.
public struct RewindBuffer: Sendable {
    public let configuration: RewindBufferConfiguration
    public private(set) var checkpoints: [RewindCheckpoint] = []
    public private(set) var totalPayloadByteCount = 0

    public init(configuration: RewindBufferConfiguration = .standard) {
        self.configuration = configuration
    }

    public var isEmpty: Bool { checkpoints.isEmpty }
    public var count: Int { checkpoints.count }
    public var oldestCheckpoint: RewindCheckpoint? { checkpoints.first }
    public var latestCheckpoint: RewindCheckpoint? { checkpoints.last }

    public var retainedFrameRange: ClosedRange<UInt64>? {
        guard let oldestCheckpoint, let latestCheckpoint else { return nil }
        return oldestCheckpoint.frameNumber...latestCheckpoint.frameNumber
    }

    /// Appends a newer frame or replaces an existing checkpoint at the exact
    /// same frame. Inserting a missing historical frame is rejected so callers
    /// must make a branch explicit with `truncate(afterFrame:)`.
    @discardableResult
    public mutating func append(
        _ checkpoint: RewindCheckpoint
    ) throws -> RewindBufferAppendResult {
        guard checkpoint.payloadByteCount <= configuration.maximumByteCount else {
            throw RewindBufferError.checkpointExceedsByteLimit(
                actual: checkpoint.payloadByteCount,
                maximum: configuration.maximumByteCount
            )
        }

        let insertionIndex = lowerBoundIndex(for: checkpoint.frameNumber)
        let replacesExisting = insertionIndex < checkpoints.count
            && checkpoints[insertionIndex].frameNumber == checkpoint.frameNumber
        if !replacesExisting, let latestCheckpoint,
           checkpoint.frameNumber < latestCheckpoint.frameNumber {
            throw RewindBufferError.outOfOrderFrame(
                attempted: checkpoint.frameNumber,
                latest: latestCheckpoint.frameNumber
            )
        }

        var next = checkpoints
        var nextByteCount = UInt64(totalPayloadByteCount)
        if replacesExisting {
            nextByteCount -= UInt64(next[insertionIndex].payloadByteCount)
            next[insertionIndex] = checkpoint
        } else {
            next.append(checkpoint)
        }
        nextByteCount += UInt64(checkpoint.payloadByteCount)

        var evictedCheckpointCount = 0
        if let newestFrame = next.last?.frameNumber {
            let oldestPermittedFrame = newestFrame > configuration.maximumFrameSpan
                ? newestFrame - configuration.maximumFrameSpan
                : 0
            while let first = next.first,
                  first.frameNumber < oldestPermittedFrame {
                nextByteCount -= UInt64(first.payloadByteCount)
                next.removeFirst()
                evictedCheckpointCount += 1
            }
        }
        while nextByteCount > UInt64(configuration.maximumByteCount),
              let first = next.first {
            nextByteCount -= UInt64(first.payloadByteCount)
            next.removeFirst()
            evictedCheckpointCount += 1
        }

        checkpoints = next
        totalPayloadByteCount = Int(nextByteCount)
        assert(invariantsHold)
        return RewindBufferAppendResult(
            replacedExistingCheckpoint: replacesExisting,
            evictedCheckpointCount: evictedCheckpointCount,
            checkpointWasRetained: checkpoints.contains {
                $0.frameNumber == checkpoint.frameNumber
            }
        )
    }

    public func checkpoint(nearestToFrame targetFrame: UInt64) -> RewindCheckpoint? {
        guard !checkpoints.isEmpty else { return nil }
        let upperIndex = lowerBoundIndex(for: targetFrame)
        if upperIndex == 0 { return checkpoints[0] }
        if upperIndex == checkpoints.count { return checkpoints[checkpoints.count - 1] }

        let lower = checkpoints[upperIndex - 1]
        let upper = checkpoints[upperIndex]
        let lowerDistance = targetFrame - lower.frameNumber
        let upperDistance = upper.frameNumber - targetFrame
        return lowerDistance <= upperDistance ? lower : upper
    }

    public func checkpoint(atOrBeforeFrame targetFrame: UInt64) -> RewindCheckpoint? {
        guard !checkpoints.isEmpty else { return nil }
        let index = lowerBoundIndex(for: targetFrame)
        if index < checkpoints.count,
           checkpoints[index].frameNumber == targetFrame {
            return checkpoints[index]
        }
        guard index > 0 else { return nil }
        return checkpoints[index - 1]
    }

    /// Selects the checkpoint nearest to an emulated time offset. Invalid time
    /// values return `nil`; requests older than the retained history clamp to
    /// its oldest checkpoint.
    public func checkpoint(
        secondsBack: TimeInterval,
        fromFrame: UInt64? = nil
    ) -> RewindCheckpoint? {
        guard secondsBack.isFinite, secondsBack >= 0,
              let originFrame = fromFrame ?? latestCheckpoint?.frameNumber else {
            return nil
        }
        let scaledFrames = secondsBack * configuration.nominalFramesPerSecond
        let frameDelta: UInt64
        if scaledFrames >= Double(UInt64.max) {
            frameDelta = UInt64.max
        } else {
            frameDelta = UInt64(scaledFrames.rounded(.toNearestOrAwayFromZero))
        }
        let targetFrame = frameDelta >= originFrame ? 0 : originFrame - frameDelta
        return checkpoint(nearestToFrame: targetFrame)
    }

    /// Removes checkpoints belonging to the abandoned future of a rewound
    /// session. The checkpoint at `frameNumber`, when present, is retained.
    @discardableResult
    public mutating func truncate(afterFrame frameNumber: UInt64) -> Int {
        let firstRemovedIndex = upperBoundIndex(for: frameNumber)
        guard firstRemovedIndex < checkpoints.count else { return 0 }
        let removed = checkpoints[firstRemovedIndex...]
        for checkpoint in removed {
            totalPayloadByteCount -= checkpoint.payloadByteCount
        }
        let removedCount = removed.count
        checkpoints.removeSubrange(firstRemovedIndex...)
        assert(invariantsHold)
        return removedCount
    }

    public mutating func reset() {
        checkpoints.removeAll(keepingCapacity: false)
        totalPayloadByteCount = 0
        assert(invariantsHold)
    }

    private func lowerBoundIndex(for frameNumber: UInt64) -> Int {
        var lower = 0
        var upper = checkpoints.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if checkpoints[middle].frameNumber < frameNumber {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func upperBoundIndex(for frameNumber: UInt64) -> Int {
        var lower = 0
        var upper = checkpoints.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if checkpoints[middle].frameNumber <= frameNumber {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private var invariantsHold: Bool {
        guard totalPayloadByteCount >= 0,
              totalPayloadByteCount <= configuration.maximumByteCount else {
            return false
        }
        var measuredByteCount = 0
        for (index, checkpoint) in checkpoints.enumerated() {
            let (nextByteCount, overflow) = measuredByteCount
                .addingReportingOverflow(checkpoint.payloadByteCount)
            guard !overflow,
                  checkpoint.payloadByteCount <= configuration.maximumByteCount else {
                return false
            }
            measuredByteCount = nextByteCount
            if index > 0,
               checkpoints[index - 1].frameNumber >= checkpoint.frameNumber {
                return false
            }
        }
        guard measuredByteCount == totalPayloadByteCount else { return false }
        if let oldestCheckpoint, let latestCheckpoint {
            return latestCheckpoint.frameNumber - oldestCheckpoint.frameNumber
                <= configuration.maximumFrameSpan
        }
        return true
    }
}
