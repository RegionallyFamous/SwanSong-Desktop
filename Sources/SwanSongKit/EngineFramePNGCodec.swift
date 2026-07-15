import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum EngineFramePNGCodecError: LocalizedError, Equatable, Sendable {
    case unsupportedDimensions(width: Int, height: Int)
    case invalidFrameBuffer
    case invalidPNG

    public var errorDescription: String? {
        switch self {
        case let .unsupportedDimensions(width, height):
            "Unsupported WonderSwan frame dimensions: \(width)×\(height)."
        case .invalidFrameBuffer:
            "The WonderSwan frame buffer is invalid."
        case .invalidPNG:
            "The saved WonderSwan frame preview is not a valid PNG."
        }
    }
}

/// Losslessly transports the opaque BGRA frames produced by the engine through
/// PNG without performing per-pixel `NSColor` color-space conversion.
public enum EngineFramePNGCodec {
    public static func encode(_ frame: EngineVideoFrame) throws -> Data {
        guard isSupported(width: frame.width, height: frame.height) else {
            throw EngineFramePNGCodecError.unsupportedDimensions(
                width: frame.width,
                height: frame.height
            )
        }
        guard
            frame.width <= Int.max / 4,
            frame.strideBytes >= frame.width * 4,
            frame.height <= Int.max / frame.strideBytes,
            frame.pixels.count >= frame.strideBytes * frame.height,
            let provider = CGDataProvider(data: frame.pixels as CFData),
            let image = CGImage(
                width: frame.width,
                height: frame.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: frame.strideBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: [
                    .byteOrder32Little,
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
                ],
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw EngineFramePNGCodecError.invalidFrameBuffer
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw EngineFramePNGCodecError.invalidFrameBuffer
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EngineFramePNGCodecError.invalidFrameBuffer
        }
        return output as Data
    }

    public static func decode(
        _ data: Data,
        frameNumber: UInt64
    ) throws -> EngineVideoFrame {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) as String? == UTType.png.identifier,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = integerProperty(properties[kCGImagePropertyPixelWidth]),
            let height = integerProperty(properties[kCGImagePropertyPixelHeight])
        else {
            throw EngineFramePNGCodecError.invalidPNG
        }
        guard isSupported(width: width, height: height) else {
            throw EngineFramePNGCodecError.unsupportedDimensions(width: width, height: height)
        }
        guard
            let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            ),
            image.width == width,
            image.height == height,
            image.colorSpace?.model == .rgb,
            width <= Int.max / 4
        else {
            throw EngineFramePNGCodecError.invalidPNG
        }

        let bytesPerRow = width * 4
        guard height <= Int.max / bytesPerRow else {
            throw EngineFramePNGCodecError.invalidPNG
        }
        var rgba = Data(count: bytesPerRow * height)
        let rendered = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard
                let baseAddress = raw.baseAddress,
                let colorSpace = image.colorSpace,
                let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else { throw EngineFramePNGCodecError.invalidPNG }

        // Bitmap contexts above expose source pixels as raw RGBA. The engine
        // and Metal renderer consume packed little-endian BGRA.
        rgba.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for offset in Swift.stride(from: 0, to: bytes.count, by: 4) {
                bytes.swapAt(offset, offset + 2)
            }
        }
        return EngineVideoFrame(
            pixels: rgba,
            width: width,
            height: height,
            strideBytes: bytesPerRow,
            isVertical: height > width,
            number: frameNumber
        )
    }

    public static func isSupported(width: Int, height: Int) -> Bool {
        switch (width, height) {
        case (224, 157), (157, 224),
             (237, 144), (144, 237),
             (224, 144), (144, 224):
            true
        default:
            false
        }
    }

    private static func integerProperty(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }
}
