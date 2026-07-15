import Foundation

public struct TranslationVisualFramePair: Sendable {
    public let original: EngineVideoFrame
    public let patched: EngineVideoFrame

    public init(original: EngineVideoFrame, patched: EngineVideoFrame) {
        self.original = original
        self.patched = patched
    }
}

public struct TranslationVisualComparedFrame: Sendable {
    public let frameIndex: UInt64
    public let inputMask: UInt32
    public let frames: TranslationVisualFramePair

    public init(
        frameIndex: UInt64,
        inputMask: UInt32,
        frames: TranslationVisualFramePair
    ) {
        self.frameIndex = frameIndex
        self.inputMask = inputMask
        self.frames = frames
    }
}

public enum TranslationVisualDivergenceKind: String, Codable, Equatable, Sendable {
    case pixels
    case dimensions
    case orientation
    case dimensionsAndOrientation = "dimensions-and-orientation"
}

public struct TranslationVisualDivergence: Sendable {
    public let kind: TranslationVisualDivergenceKind
    public let frame: TranslationVisualComparedFrame
    public let previousIdenticalFrame: TranslationVisualComparedFrame?
    public let originalRaster: TranslationGameRasterDescriptor
    public let patchedRaster: TranslationGameRasterDescriptor
    public let visualization: RGBFrameVisualization?

    public init(
        kind: TranslationVisualDivergenceKind,
        frame: TranslationVisualComparedFrame,
        previousIdenticalFrame: TranslationVisualComparedFrame?,
        originalRaster: TranslationGameRasterDescriptor,
        patchedRaster: TranslationGameRasterDescriptor,
        visualization: RGBFrameVisualization?
    ) {
        self.kind = kind
        self.frame = frame
        self.previousIdenticalFrame = previousIdenticalFrame
        self.originalRaster = originalRaster
        self.patchedRaster = patchedRaster
        self.visualization = visualization
    }

    public var difference: RGBFrameDifference? { visualization?.difference }
    public var changedBounds: RGBFrameBounds? { visualization?.changedBounds }
}

public struct TranslationVisualNoDifference: Sendable {
    public let framesCompared: UInt64
    public let lastIdenticalFrame: TranslationVisualComparedFrame

    public init(
        framesCompared: UInt64,
        lastIdenticalFrame: TranslationVisualComparedFrame
    ) {
        self.framesCompared = framesCompared
        self.lastIdenticalFrame = lastIdenticalFrame
    }
}

public enum TranslationVisualDivergenceResult: Sendable {
    case firstDifference(TranslationVisualDivergence)
    case noDifference(TranslationVisualNoDifference)
}

public struct TranslationVisualDivergenceProgress: Equatable, Sendable {
    public let framesProcessed: UInt64
    public let totalFrames: UInt64
    public let firstDifferenceFrameIndex: UInt64?

    public var fractionComplete: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(framesProcessed) / Double(totalFrames)
    }
}

public enum TranslationVisualDivergenceStep: Sendable {
    case needsMoreFrames(TranslationVisualDivergenceProgress)
    case complete(TranslationVisualDivergenceResult)
}

public enum TranslationVisualDivergenceError: LocalizedError, Equatable, Sendable {
    case invalidFrameLimit
    case routeExceedsFrameLimit(totalFrames: UInt64, limit: UInt64)
    case unexpectedFrameNumber(
        role: TranslationROMRole,
        expected: UInt64,
        actual: UInt64
    )
    case originalCheckpointMismatch
    case incomplete(expectedFrames: UInt64, actualFrames: UInt64)
    case alreadyComplete

    public var errorDescription: String? {
        switch self {
        case .invalidFrameLimit:
            "The first-visual-change frame limit must be greater than zero."
        case let .routeExceedsFrameLimit(totalFrames, limit):
            "The route contains \(totalFrames) frames, exceeding the \(limit)-frame first-visual-change limit."
        case let .unexpectedFrameNumber(role, expected, actual):
            "\(role.title) produced frame \(actual), but clean deterministic replay expected frame \(expected)."
        case .originalCheckpointMismatch:
            "Original no longer matches the route checkpoint; re-record the route before comparing it."
        case let .incomplete(expectedFrames, actualFrames):
            "The comparison ended after \(actualFrames) of \(expectedFrames) route frames."
        case .alreadyComplete:
            "The first-visual-change comparison is already complete."
        }
    }
}

/// Incrementally compares one deterministic Original/Patched frame pair at a time.
///
/// The analyzer retains only the first divergent pair, the preceding identical pair,
/// and the current pair. A caller can therefore check `Task.checkCancellation()`
/// between calls without buffering a route-length frame sequence.
public struct TranslationVisualDivergenceAnalyzer: Sendable {
    public static let defaultFrameLimit: UInt64 = 120_000

    public let route: TranslationRoute
    public let frameLimit: UInt64

    private var nextFrameIndex: UInt64 = 0
    private var previousIdenticalFrame: TranslationVisualComparedFrame?
    private var firstDivergence: TranslationVisualDivergence?
    private var completedResult: TranslationVisualDivergenceResult?

    public init(
        route: TranslationRoute,
        frameLimit: UInt64 = Self.defaultFrameLimit
    ) throws {
        guard frameLimit > 0 else {
            throw TranslationVisualDivergenceError.invalidFrameLimit
        }
        try route.validateForProof()
        guard route.totalFrames <= frameLimit else {
            throw TranslationVisualDivergenceError.routeExceedsFrameLimit(
                totalFrames: route.totalFrames,
                limit: frameLimit
            )
        }
        self.route = route
        self.frameLimit = frameLimit
    }

    public var progress: TranslationVisualDivergenceProgress {
        TranslationVisualDivergenceProgress(
            framesProcessed: nextFrameIndex,
            totalFrames: route.totalFrames,
            firstDifferenceFrameIndex: firstDivergence?.frame.frameIndex
        )
    }

    public mutating func consume(
        original: EngineVideoFrame,
        patched: EngineVideoFrame
    ) throws -> TranslationVisualDivergenceStep {
        guard completedResult == nil else {
            throw TranslationVisualDivergenceError.alreadyComplete
        }

        let expectedFrameNumber = nextFrameIndex + 1
        guard original.number == expectedFrameNumber else {
            throw TranslationVisualDivergenceError.unexpectedFrameNumber(
                role: .original,
                expected: expectedFrameNumber,
                actual: original.number
            )
        }
        guard patched.number == expectedFrameNumber else {
            throw TranslationVisualDivergenceError.unexpectedFrameNumber(
                role: .patched,
                expected: expectedFrameNumber,
                actual: patched.number
            )
        }

        if firstDivergence == nil {
            if let divergence = try Self.compareFramePair(
                route: route,
                frameIndex: nextFrameIndex,
                original: original,
                patched: patched,
                previousIdenticalFrame: previousIdenticalFrame
            ) {
                firstDivergence = divergence
            } else {
                previousIdenticalFrame = TranslationVisualComparedFrame(
                    frameIndex: nextFrameIndex,
                    inputMask: route.input(at: nextFrameIndex).rawValue,
                    frames: TranslationVisualFramePair(
                        original: original,
                        patched: patched
                    )
                )
            }
        }

        nextFrameIndex += 1
        guard nextFrameIndex == route.totalFrames else {
            return .needsMoreFrames(progress)
        }
        guard route.checkpoint?.matches(original) == true else {
            throw TranslationVisualDivergenceError.originalCheckpointMismatch
        }

        let result: TranslationVisualDivergenceResult
        if let firstDivergence {
            result = .firstDifference(firstDivergence)
        } else if let previousIdenticalFrame {
            result = .noDifference(
                TranslationVisualNoDifference(
                    framesCompared: nextFrameIndex,
                    lastIdenticalFrame: previousIdenticalFrame
                )
            )
        } else {
            // A proof route always contains at least one frame, so reaching this
            // branch would mean its validation contract changed unexpectedly.
            throw TranslationVisualDivergenceError.incomplete(
                expectedFrames: route.totalFrames,
                actualFrames: nextFrameIndex
            )
        }
        completedResult = result
        return .complete(result)
    }

    public func finish() throws -> TranslationVisualDivergenceResult {
        guard let completedResult else {
            throw TranslationVisualDivergenceError.incomplete(
                expectedFrames: route.totalFrames,
                actualFrames: nextFrameIndex
            )
        }
        return completedResult
    }

    public static func analyze<Frames: Sequence>(
        route: TranslationRoute,
        pairs: Frames,
        frameLimit: UInt64 = Self.defaultFrameLimit,
        cancellationCheck: () throws -> Void = {}
    ) throws -> TranslationVisualDivergenceResult
    where Frames.Element == TranslationVisualFramePair {
        var analyzer = try Self(route: route, frameLimit: frameLimit)
        for pair in pairs {
            try cancellationCheck()
            _ = try analyzer.consume(original: pair.original, patched: pair.patched)
        }
        return try analyzer.finish()
    }

    public static func compareFramePair(
        route: TranslationRoute,
        frameIndex: UInt64,
        original: EngineVideoFrame,
        patched: EngineVideoFrame,
        previousIdenticalFrame: TranslationVisualComparedFrame? = nil
    ) throws -> TranslationVisualDivergence? {
        guard frameIndex < route.totalFrames else {
            throw TranslationLabError.invalidRoute(
                "the compared visual frame is beyond the route endpoint"
            )
        }
        let expectedFrameNumber = frameIndex + 1
        guard original.number == expectedFrameNumber else {
            throw TranslationVisualDivergenceError.unexpectedFrameNumber(
                role: .original,
                expected: expectedFrameNumber,
                actual: original.number
            )
        }
        guard patched.number == expectedFrameNumber else {
            throw TranslationVisualDivergenceError.unexpectedFrameNumber(
                role: .patched,
                expected: expectedFrameNumber,
                actual: patched.number
            )
        }
        let frame = TranslationVisualComparedFrame(
            frameIndex: frameIndex,
            inputMask: route.input(at: frameIndex).rawValue,
            frames: TranslationVisualFramePair(original: original, patched: patched)
        )
        let originalRaster = try TranslationRouteCheckpoint.canonicalGameRaster(original)
        let patchedRaster = try TranslationRouteCheckpoint.canonicalGameRaster(patched)
        return try divergence(
            frame: frame,
            previousIdenticalFrame: previousIdenticalFrame,
            originalRaster: originalRaster,
            patchedRaster: patchedRaster
        )
    }

    private static func divergence(
        frame: TranslationVisualComparedFrame,
        previousIdenticalFrame: TranslationVisualComparedFrame?,
        originalRaster: TranslationGameRaster,
        patchedRaster: TranslationGameRaster
    ) throws -> TranslationVisualDivergence? {
        let dimensionsMatch = originalRaster.descriptor.width == patchedRaster.descriptor.width
            && originalRaster.descriptor.height == patchedRaster.descriptor.height
        let orientationMatches = originalRaster.descriptor.orientation
            == patchedRaster.descriptor.orientation
        guard dimensionsMatch, orientationMatches else {
            let kind: TranslationVisualDivergenceKind
            switch (dimensionsMatch, orientationMatches) {
            case (false, false): kind = .dimensionsAndOrientation
            case (false, true): kind = .dimensions
            case (true, false): kind = .orientation
            case (true, true): preconditionFailure("matched raster descriptors")
            }
            return TranslationVisualDivergence(
                kind: kind,
                frame: frame,
                previousIdenticalFrame: previousIdenticalFrame,
                originalRaster: originalRaster.descriptor,
                patchedRaster: patchedRaster.descriptor,
                visualization: nil
            )
        }

        let originalRGB = try originalRaster.rgb888()
        let patchedRGB = try patchedRaster.rgb888()
        guard originalRGB != patchedRGB else { return nil }
        let visualization = try FrameDifferential.visualizeRGB888(
            expected: originalRGB,
            actual: patchedRGB,
            width: originalRaster.descriptor.width,
            height: originalRaster.descriptor.height
        )
        return TranslationVisualDivergence(
            kind: .pixels,
            frame: frame,
            previousIdenticalFrame: previousIdenticalFrame,
            originalRaster: originalRaster.descriptor,
            patchedRaster: patchedRaster.descriptor,
            visualization: visualization
        )
    }
}

public extension TranslationRoute {
    /// Creates a new immutable proof route ending at `frameIndex`.
    /// Input changes after the new endpoint are omitted; the original route is untouched.
    func prefix(
        through frameIndex: UInt64,
        originalFrame: EngineVideoFrame,
        createdAt: Date = Date()
    ) throws -> TranslationRoute {
        try validateForProof()
        guard frameIndex < totalFrames else {
            throw TranslationLabError.invalidRoute(
                "the requested derived endpoint is beyond the route"
            )
        }
        guard originalFrame.number == frameIndex + 1 else {
            throw TranslationLabError.invalidRoute(
                "the derived checkpoint does not match its clean-boot frame index"
            )
        }
        guard let start else {
            throw TranslationLabError.invalidRoute("the route start context is missing")
        }
        return try TranslationRoute(
            createdAt: createdAt,
            recordedFrom: recordedFrom,
            sourceROM: sourceROM,
            start: start,
            totalFrames: frameIndex + 1,
            events: events.filter { $0.frameIndex <= frameIndex },
            checkpoint: TranslationRouteCheckpoint(
                frameIndex: frameIndex,
                frame: originalFrame
            )
        )
    }
}
