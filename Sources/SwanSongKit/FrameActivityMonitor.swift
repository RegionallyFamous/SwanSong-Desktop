import Foundation

public enum FrameActivityIssue: String, Equatable, Sendable {
    case flatColor
    case lowMotion
}

public struct FrameActivityReport: Equatable, Sendable {
    public let consecutiveUniformFrames: Int
    public let consecutiveLowMotionFrames: Int
    public let approximateBrightness: UInt8
    public let dominantColorRatio: Double
    public let hasMeaningfulMotion: Bool
    public let issue: FrameActivityIssue?

    public var needsAttention: Bool { issue != nil }

    public init(
        consecutiveUniformFrames: Int,
        consecutiveLowMotionFrames: Int = 0,
        approximateBrightness: UInt8,
        dominantColorRatio: Double = 0,
        hasMeaningfulMotion: Bool = false,
        issue: FrameActivityIssue? = nil
    ) {
        self.consecutiveUniformFrames = consecutiveUniformFrames
        self.consecutiveLowMotionFrames = consecutiveLowMotionFrames
        self.approximateBrightness = approximateBrightness
        self.dominantColorRatio = dominantColorRatio
        self.hasMeaningfulMotion = hasMeaningfulMotion
        self.issue = issue
    }

    /// Backward-compatible construction for callers that only classify a
    /// completely flat raster.
    public init(
        consecutiveUniformFrames: Int,
        approximateBrightness: UInt8,
        needsAttention: Bool
    ) {
        self.init(
            consecutiveUniformFrames: consecutiveUniformFrames,
            approximateBrightness: approximateBrightness,
            issue: needsAttention ? .flatColor : nil
        )
    }
}

/// Watches the native game raster for two different recovery signals:
///
/// - a display that remains almost entirely one flat color; and
/// - a non-flat display whose sampled pixels barely change for much longer.
///
/// The second signal is deliberately slower and advisory. Static title/menu
/// screens are valid, but a low-motion warning gives a player who sees a
/// mostly blank raster a truthful route to controls, restart, and diagnostics.
public struct FrameActivityMonitor: Sendable {
    public let attentionThreshold: Int
    public let lowMotionAttentionThreshold: Int
    public let channelTolerance: UInt8
    public let changedSampleRatioTolerance: Double
    public private(set) var consecutiveUniformFrames = 0
    public private(set) var consecutiveLowMotionFrames = 0

    private var previousSamples: [UInt32]?

    public init(
        attentionThreshold: Int = 360,
        lowMotionAttentionThreshold: Int? = nil,
        channelTolerance: UInt8 = 3,
        changedSampleRatioTolerance: Double = 0.05
    ) {
        let flatThreshold = max(1, attentionThreshold)
        self.attentionThreshold = flatThreshold
        self.lowMotionAttentionThreshold = max(
            flatThreshold,
            lowMotionAttentionThreshold ?? flatThreshold * 3
        )
        self.channelTolerance = channelTolerance
        self.changedSampleRatioTolerance = min(
            max(changedSampleRatioTolerance, 0),
            1
        )
    }

    public mutating func observe(_ frame: EngineVideoFrame) -> FrameActivityReport {
        guard let sample = Self.sample(
            frame,
            channelTolerance: channelTolerance
        ) else {
            reset()
            return FrameActivityReport(
                consecutiveUniformFrames: 0,
                approximateBrightness: 0,
                hasMeaningfulMotion: true
            )
        }

        let hasMeaningfulMotion: Bool
        if let previousSamples, previousSamples.count == sample.pixels.count {
            let changed = zip(previousSamples, sample.pixels).reduce(into: 0) {
                if Self.sampleDistance($1.0, $1.1) > 12 { $0 += 1 }
            }
            let changedRatio = Double(changed) / Double(max(1, sample.pixels.count))
            hasMeaningfulMotion = changedRatio > changedSampleRatioTolerance
        } else {
            hasMeaningfulMotion = true
        }
        previousSamples = sample.pixels

        consecutiveUniformFrames = sample.isUniform
            ? consecutiveUniformFrames + 1
            : 0
        consecutiveLowMotionFrames = hasMeaningfulMotion
            ? 0
            : consecutiveLowMotionFrames + 1

        // A mostly one-color raster with only a small rail/icon changing is
        // the common "blank screen" shape. Escalate that sooner than a rich,
        // legitimate title/menu screen that happens to be static.
        let effectiveLowMotionThreshold = sample.dominantColorRatio >= 0.80
            ? attentionThreshold
            : lowMotionAttentionThreshold
        let issue: FrameActivityIssue?
        if consecutiveUniformFrames >= attentionThreshold {
            issue = .flatColor
        } else if consecutiveLowMotionFrames >= effectiveLowMotionThreshold {
            issue = .lowMotion
        } else {
            issue = nil
        }

        return FrameActivityReport(
            consecutiveUniformFrames: consecutiveUniformFrames,
            consecutiveLowMotionFrames: consecutiveLowMotionFrames,
            approximateBrightness: sample.brightness,
            dominantColorRatio: sample.dominantColorRatio,
            hasMeaningfulMotion: hasMeaningfulMotion,
            issue: issue
        )
    }

    public mutating func reset() {
        consecutiveUniformFrames = 0
        consecutiveLowMotionFrames = 0
        previousSamples = nil
    }

    private struct RasterSample {
        let pixels: [UInt32]
        let brightness: UInt8
        let dominantColorRatio: Double
        let isUniform: Bool
    }

    private static func sample(
        _ frame: EngineVideoFrame,
        channelTolerance: UInt8
    ) -> RasterSample? {
        let contentWidth = frame.isVertical
            ? min(frame.width, 144)
            : min(frame.width, 224)
        let contentHeight = frame.isVertical
            ? min(frame.height, 224)
            : min(frame.height, 144)
        guard
            contentWidth > 0,
            contentHeight > 0,
            frame.strideBytes >= contentWidth * 4,
            frame.pixels.count >= frame.strideBytes * contentHeight
        else { return nil }

        let columns = min(16, contentWidth)
        let rows = min(12, contentHeight)
        var minima = [UInt8](repeating: .max, count: 3)
        var maxima = [UInt8](repeating: .min, count: 3)
        var brightnessTotal = 0
        var pixels: [UInt32] = []
        pixels.reserveCapacity(columns * rows)
        var buckets: [UInt16: Int] = [:]

        frame.pixels.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for row in 0..<rows {
                let y = rows == 1 ? 0 : row * (contentHeight - 1) / (rows - 1)
                for column in 0..<columns {
                    let x = columns == 1 ? 0 : column * (contentWidth - 1) / (columns - 1)
                    let offset = y * frame.strideBytes + x * 4
                    // Engine frames are little-endian BGRA.
                    let blue = bytes[offset]
                    let green = bytes[offset + 1]
                    let red = bytes[offset + 2]
                    let channels = [red, green, blue]
                    for index in channels.indices {
                        minima[index] = min(minima[index], channels[index])
                        maxima[index] = max(maxima[index], channels[index])
                    }
                    brightnessTotal += (Int(red) * 54 + Int(green) * 183 + Int(blue) * 19) / 256
                    pixels.append(
                        UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
                    )
                    let bucket = UInt16(red >> 4) << 8
                        | UInt16(green >> 4) << 4
                        | UInt16(blue >> 4)
                    buckets[bucket, default: 0] += 1
                }
            }
        }

        let tolerance = Int(channelTolerance)
        let isUniform = zip(minima, maxima).allSatisfy {
            Int($0.1) - Int($0.0) <= tolerance
        }
        let sampleCount = max(1, pixels.count)
        let dominantCount = buckets.values.max() ?? 0
        return RasterSample(
            pixels: pixels,
            brightness: UInt8(clamping: brightnessTotal / sampleCount),
            dominantColorRatio: Double(dominantCount) / Double(sampleCount),
            isUniform: isUniform
        )
    }

    private static func sampleDistance(_ left: UInt32, _ right: UInt32) -> Int {
        let red = abs(Int((left >> 16) & 0xff) - Int((right >> 16) & 0xff))
        let green = abs(Int((left >> 8) & 0xff) - Int((right >> 8) & 0xff))
        let blue = abs(Int(left & 0xff) - Int(right & 0xff))
        return max(red, green, blue)
    }
}
