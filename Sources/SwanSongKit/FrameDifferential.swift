import Foundation

public struct RGBFrameDifference: Codable, Equatable, Sendable {
    public let pixelCount: Int
    public let differentPixelCount: Int
    public let meanAbsoluteChannelError: Double
    public let maximumChannelError: UInt8

    public var differentPixelFraction: Double {
        guard pixelCount > 0 else { return 0 }
        return Double(differentPixelCount) / Double(pixelCount)
    }
}

public struct RGBFrameBounds: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct RGBFrameVisualization: Equatable, Sendable {
    public let difference: RGBFrameDifference
    public let changedBounds: RGBFrameBounds?
    public let heatmapRGB888: Data

    public init(
        difference: RGBFrameDifference,
        changedBounds: RGBFrameBounds?,
        heatmapRGB888: Data
    ) {
        self.difference = difference
        self.changedBounds = changedBounds
        self.heatmapRGB888 = heatmapRGB888
    }
}

public enum FrameDifferentialError: LocalizedError, Equatable, Sendable {
    case invalidRGBByteCount(expected: Int, actual: Int)
    case invalidRGBDimensions(width: Int, height: Int, byteCount: Int)
    case invalidBGRAFrame

    public var errorDescription: String? {
        switch self {
        case let .invalidRGBByteCount(expected, actual):
            "RGB frame byte count mismatch: expected \(expected), found \(actual)."
        case let .invalidRGBDimensions(width, height, byteCount):
            "RGB frame dimensions \(width)×\(height) do not match \(byteCount) bytes."
        case .invalidBGRAFrame:
            "The BGRA frame dimensions or stride are invalid."
        }
    }
}

public enum FrameDifferential {
    public static func compareRGB888(
        expected: Data,
        actual: Data
    ) throws -> RGBFrameDifference {
        guard expected.count == actual.count, expected.count.isMultiple(of: 3) else {
            throw FrameDifferentialError.invalidRGBByteCount(
                expected: expected.count,
                actual: actual.count
            )
        }
        var differentPixels = 0
        var totalError: UInt64 = 0
        var maximumError: UInt8 = 0
        expected.withUnsafeBytes { expectedBytes in
            actual.withUnsafeBytes { actualBytes in
                let expected = expectedBytes.bindMemory(to: UInt8.self)
                let actual = actualBytes.bindMemory(to: UInt8.self)
                for pixel in 0..<(expected.count / 3) {
                    var pixelIsDifferent = false
                    for channel in 0..<3 {
                        let index = pixel * 3 + channel
                        let error = UInt8(abs(Int(expected[index]) - Int(actual[index])))
                        totalError += UInt64(error)
                        maximumError = max(maximumError, error)
                        pixelIsDifferent = pixelIsDifferent || error != 0
                    }
                    if pixelIsDifferent { differentPixels += 1 }
                }
            }
        }
        let channelCount = max(expected.count, 1)
        return RGBFrameDifference(
            pixelCount: expected.count / 3,
            differentPixelCount: differentPixels,
            meanAbsoluteChannelError: Double(totalError) / Double(channelCount),
            maximumChannelError: maximumError
        )
    }

    public static func visualizeRGB888(
        expected: Data,
        actual: Data,
        width: Int,
        height: Int
    ) throws -> RGBFrameVisualization {
        let (pixelCount, pixelCountOverflow) = width.multipliedReportingOverflow(by: height)
        let (expectedByteCount, byteCountOverflow) = pixelCount.multipliedReportingOverflow(by: 3)
        guard
            width > 0,
            height > 0,
            !pixelCountOverflow,
            !byteCountOverflow,
            expectedByteCount == expected.count
        else {
            throw FrameDifferentialError.invalidRGBDimensions(
                width: width,
                height: height,
                byteCount: expected.count
            )
        }
        let difference = try compareRGB888(expected: expected, actual: actual)
        var heatmap = Data(capacity: expected.count)
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1

        expected.withUnsafeBytes { expectedBytes in
            actual.withUnsafeBytes { actualBytes in
                let expected = expectedBytes.bindMemory(to: UInt8.self)
                let actual = actualBytes.bindMemory(to: UInt8.self)
                for pixel in 0..<pixelCount {
                    let index = pixel * 3
                    let redError = abs(Int(expected[index]) - Int(actual[index]))
                    let greenError = abs(Int(expected[index + 1]) - Int(actual[index + 1]))
                    let blueError = abs(Int(expected[index + 2]) - Int(actual[index + 2]))
                    let magnitude = max(redError, greenError, blueError)
                    if magnitude == 0 {
                        let luminance = (
                            77 * Int(expected[index])
                                + 150 * Int(expected[index + 1])
                                + 29 * Int(expected[index + 2])
                        ) >> 8
                        let dimmed = UInt8(luminance / 5)
                        heatmap.append(dimmed)
                        heatmap.append(dimmed)
                        heatmap.append(dimmed)
                    } else {
                        let x = pixel % width
                        let y = pixel / width
                        minimumX = min(minimumX, x)
                        minimumY = min(minimumY, y)
                        maximumX = max(maximumX, x)
                        maximumY = max(maximumY, y)
                        heatmap.append(255)
                        heatmap.append(UInt8(max(32, 208 - magnitude / 2)))
                        heatmap.append(UInt8(min(255, 64 + magnitude * 3 / 4)))
                    }
                }
            }
        }

        let bounds = maximumX < 0
            ? nil
            : RGBFrameBounds(
                x: minimumX,
                y: minimumY,
                width: maximumX - minimumX + 1,
                height: maximumY - minimumY + 1
            )
        return RGBFrameVisualization(
            difference: difference,
            changedBounds: bounds,
            heatmapRGB888: heatmap
        )
    }

    public static func fnv1a64(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    public static func normalizeMonochromeRGB888(_ data: Data) throws -> Data {
        guard data.count.isMultiple(of: 3) else {
            throw FrameDifferentialError.invalidRGBByteCount(
                expected: (data.count / 3) * 3,
                actual: data.count
            )
        }
        var normalized = Data(capacity: data.count)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for pixel in 0..<(bytes.count / 3) {
                let index = pixel * 3
                let luminance = (
                    77 * Int(bytes[index])
                        + 150 * Int(bytes[index + 1])
                        + 29 * Int(bytes[index + 2])
                ) >> 8
                let level = min((luminance + 42) / 85, 3)
                let channel = UInt8(level * 85)
                normalized.append(channel)
                normalized.append(channel)
                normalized.append(channel)
            }
        }
        return normalized
    }

    public static func rgb888FromBGRA(
        _ data: Data,
        frameWidth: Int,
        frameHeight: Int,
        strideBytes: Int,
        contentWidth: Int,
        contentHeight: Int
    ) throws -> Data {
        guard
            frameWidth > 0,
            frameHeight > 0,
            contentWidth > 0,
            contentHeight > 0,
            contentWidth <= frameWidth,
            contentHeight <= frameHeight,
            strideBytes >= frameWidth * 4,
            data.count >= strideBytes * frameHeight
        else {
            throw FrameDifferentialError.invalidBGRAFrame
        }
        var rgb = Data(capacity: contentWidth * contentHeight * 3)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for row in 0..<contentHeight {
                let rowStart = row * strideBytes
                for column in 0..<contentWidth {
                    let index = rowStart + column * 4
                    rgb.append(bytes[index + 2])
                    rgb.append(bytes[index + 1])
                    rgb.append(bytes[index])
                }
            }
        }
        return rgb
    }
}
