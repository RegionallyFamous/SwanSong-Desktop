import AppKit
import CoreGraphics
import Foundation
import SwanSongKit

struct TranslationEvidenceFrameComparison: Equatable, Sendable {
    let width: Int
    let height: Int
    let visualization: RGBFrameVisualization
    let heatmapPNG: Data
}

enum ScreenshotExporter {
    static func pngData(for frame: EngineVideoFrame) throws -> Data {
        try EngineFramePNGCodec.encode(frame)
    }

    /// Reconstructs a display-only frame from a saved-moment preview. State
    /// restore uses this lossless image while the ares frontend produces and
    /// discards its one unsettled post-unserialize raster.
    static func frame(fromPNG data: Data, frameNumber: UInt64) throws -> EngineVideoFrame {
        try EngineFramePNGCodec.decode(data, frameNumber: frameNumber)
    }

    /// Encodes only the native 224×144 (or 144×224) game raster. The separate
    /// 13-pixel hardware-indicator rail is intentionally excluded so library
    /// artwork remains an authentic, uncropped gameplay frame.
    static func gameRasterPNGData(for frame: EngineVideoFrame) throws -> Data {
        let contentWidth = frame.isVertical ? min(frame.width, 144) : min(frame.width, 224)
        let contentHeight = frame.isVertical ? min(frame.height, 224) : min(frame.height, 144)
        guard contentWidth > 0,
              contentHeight > 0,
              frame.strideBytes >= contentWidth * 4,
              frame.pixels.count >= frame.strideBytes * contentHeight else {
            throw CocoaError(.fileWriteUnknown)
        }
        var pixels = Data(count: contentWidth * contentHeight * 4)
        pixels.withUnsafeMutableBytes { destinationRaw in
            frame.pixels.withUnsafeBytes { sourceRaw in
                guard let destination = destinationRaw.baseAddress,
                      let source = sourceRaw.baseAddress else { return }
                for row in 0..<contentHeight {
                    memcpy(
                        destination.advanced(by: row * contentWidth * 4),
                        source.advanced(by: row * frame.strideBytes),
                        contentWidth * 4
                    )
                }
            }
        }
        return try pngData(
            for: EngineVideoFrame(
                pixels: pixels,
                width: contentWidth,
                height: contentHeight,
                strideBytes: contentWidth * 4,
                isVertical: frame.isVertical,
                number: frame.number
            )
        )
    }

    static func compareEvidenceFrames(
        _ firstPNG: Data,
        _ secondPNG: Data
    ) throws -> TranslationEvidenceFrameComparison {
        let first = try rgb888(fromPNG: firstPNG)
        let second = try rgb888(fromPNG: secondPNG)
        guard first.width == second.width, first.height == second.height else {
            throw FrameDifferentialError.invalidRGBDimensions(
                width: second.width,
                height: second.height,
                byteCount: second.rgb.count
            )
        }
        let visualization = try FrameDifferential.visualizeRGB888(
            expected: first.rgb,
            actual: second.rgb,
            width: first.width,
            height: first.height
        )
        return TranslationEvidenceFrameComparison(
            width: first.width,
            height: first.height,
            visualization: visualization,
            heatmapPNG: try pngData(
                rgb888: visualization.heatmapRGB888,
                width: first.width,
                height: first.height
            )
        )
    }

    private static func rgb888(
        fromPNG data: Data
    ) throws -> (width: Int, height: Int, rgb: Data) {
        guard
            let bitmap = NSBitmapImageRep(data: data),
            bitmap.pixelsWide > 0,
            bitmap.pixelsHigh > 0
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // WonderSwan frames include a separate 13-pixel hardware-icon strip.
        // Translation comparisons cover the native game raster only; volume
        // and orientation icons are console state, not translated pixels.
        let isVertical = bitmap.pixelsHigh > bitmap.pixelsWide
        let contentWidth = isVertical
            ? min(bitmap.pixelsWide, 144)
            : min(bitmap.pixelsWide, 224)
        let contentHeight = isVertical
            ? min(bitmap.pixelsHigh, 224)
            : min(bitmap.pixelsHigh, 144)
        var rgb = Data(capacity: contentWidth * contentHeight * 3)
        for y in 0..<contentHeight {
            for x in 0..<contentWidth {
                guard
                    let source = bitmap.colorAt(x: x, y: y),
                    let color = source.usingColorSpace(.sRGB)
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                rgb.append(channel(color.redComponent))
                rgb.append(channel(color.greenComponent))
                rgb.append(channel(color.blueComponent))
            }
        }
        return (contentWidth, contentHeight, rgb)
    }

    private static func pngData(
        rgb888: Data,
        width: Int,
        height: Int
    ) throws -> Data {
        guard
            width > 0,
            height > 0,
            rgb888.count == width * height * 3,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: .alphaNonpremultiplied,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        rgb888.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 3
                    var pixel = [
                        Int(bytes[index]),
                        Int(bytes[index + 1]),
                        Int(bytes[index + 2]),
                        255,
                    ]
                    pixel.withUnsafeMutableBufferPointer { values in
                        if let baseAddress = values.baseAddress {
                            bitmap.setPixel(baseAddress, atX: x, y: y)
                        }
                    }
                }
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }

    private static func channel(_ component: CGFloat) -> UInt8 {
        UInt8(clamping: Int((component * 255).rounded()))
    }
}
